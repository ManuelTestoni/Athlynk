//
//  APIClient.swift
//  Thin async wrapper over the Django /api/v1 backend.
//
//  Base URL is http://localhost:8000 in development (the running web app).
//  All authenticated calls attach `Authorization: Bearer <token>`.
//

import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "URL non valido"
        case .http(let code, let msg): return msg.isEmpty ? "Errore server (\(code))" : msg
        case .decoding(let d): return "Risposta non leggibile: \(d)"
        case .transport(let t): return t
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    /// Override-able so a physical device can point at the host's LAN IP.
    var baseURL = "http://localhost:8000"
    var token: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private let decoder = JSONDecoder()

    // MARK: Core request

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Nessuna risposta") }
        guard (200..<300).contains(http.statusCode) else {
            var msg = ""
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let dict = obj as? [String: Any],
               let err = dict["error"] as? String {
                msg = err
            }
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    // MARK: Endpoints

    func login(email: String, password: String) async throws -> LoginResponse {
        let data = try await request("/api/v1/auth/login", method: "POST",
                                     body: ["email": email, "password": password])
        return try decode(LoginResponse.self, from: data)
    }

    func me() async throws -> MeResponse {
        try decode(MeResponse.self, from: try await request("/api/v1/me"))
    }

    func workouts() async throws -> [WorkoutPlanDTO] {
        try decode(WorkoutsResponse.self, from: try await request("/api/v1/workouts")).plans
    }

    func nutrition() async throws -> [NutritionPlanDTO] {
        try decode(NutritionResponse.self, from: try await request("/api/v1/nutrition")).plans
    }

    func checks() async throws -> [CheckDTO] {
        try decode(ChecksResponse.self, from: try await request("/api/v1/checks")).pending
    }

    func notifications() async throws -> [NotificationDTO] {
        try decode(NotificationsResponse.self, from: try await request("/api/v1/notifications")).notifications
    }

    func conversations() async throws -> [ConversationDTO] {
        try decode(ConversationsResponse.self, from: try await request("/api/v1/conversations")).conversations
    }

    /// `since` = id of the last message held; the server returns only newer ones
    /// (empty when nothing changed). Used by the open chat's foreground poll.
    func messages(conversation: Int, since: Int? = nil) async throws -> [MessageDTO] {
        var path = "/api/v1/conversations/\(conversation)/messages"
        if let since { path += "?since=\(since)" }
        return try decode(MessagesResponse.self, from: try await request(path)).messages
    }

    func send(conversation: Int, body: String) async throws {
        _ = try await request("/api/v1/conversations/\(conversation)/send",
                              method: "POST", body: ["body": body])
    }

    func subscription() async throws -> SubscriptionDTO? {
        try decode(SubscriptionResponse.self, from: try await request("/api/v1/subscription")).subscription
    }

    func appointments() async throws -> [AppointmentDTO] {
        try decode(AppointmentsResponse.self, from: try await request("/api/v1/appointments")).appointments
    }

    func progress() async throws -> [ProgressEntryDTO] {
        try decode(ProgressResponse.self, from: try await request("/api/v1/progress")).entries
    }

    func profile() async throws -> ClientProfileDTO {
        try decode(ProfileResponse.self, from: try await request("/api/v1/profile")).profile
    }

    @discardableResult
    func updateProfile(_ fields: [String: Any]) async throws -> ClientProfileDTO {
        try decode(ProfileResponse.self,
                   from: try await request("/api/v1/profile", method: "PATCH", body: fields)).profile
    }

    /// Upload the athlete's avatar (JPEG bytes) as multipart; returns the new URL.
    @discardableResult
    func uploadProfilePhoto(_ imageData: Data) async throws -> String {
        guard let url = URL(string: baseURL + "/api/v1/profile/photo") else { throw APIError.badURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"profile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.upload(for: req, from: body) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Nessuna risposta") }
        guard (200..<300).contains(http.statusCode) else {
            var msg = ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String { msg = err }
            throw APIError.http(http.statusCode, msg)
        }
        return try decode(ProfilePhotoResponse.self, from: data).imageUrl
    }

    /// Register this device's APNs token for push. Best-effort, never throws.
    func registerDevice(token: String) async {
        _ = try? await request("/api/v1/devices/register", method: "POST",
                               body: ["token": token, "platform": "ios"])
    }

    func markNotificationRead(id: Int) async throws {
        _ = try await request("/api/v1/notifications/\(id)/read", method: "POST")
    }

    func workoutHistory() async throws -> [WorkoutSessionDTO] {
        try decode(WorkoutHistoryResponse.self, from: try await request("/api/v1/workout-history")).sessions
    }

    func supplements() async throws -> [SupplementSheetDTO] {
        try decode(SupplementsResponse.self, from: try await request("/api/v1/supplements")).sheets
    }

    func coach(id: Int) async throws -> CoachDetailDTO {
        try decode(CoachDetailResponse.self, from: try await request("/api/v1/coaches/\(id)")).coach
    }

    func settings() async throws -> SettingsDTO {
        try decode(SettingsResponse.self, from: try await request("/api/v1/settings")).settings
    }

    @discardableResult
    func updateSetting(key: String, enabled: Bool) async throws -> SettingsDTO {
        try decode(SettingsResponse.self,
                   from: try await request("/api/v1/settings", method: "PATCH", body: [key: enabled])).settings
    }

    func plans() async throws -> [SubscriptionPlanDTO] {
        try decode(PlansResponse.self, from: try await request("/api/v1/plans")).plans
    }

    // MARK: Write flows

    func sessionStart(assignmentId: Int, dayId: Int) async throws -> SessionStartDTO {
        try decode(SessionStartDTO.self,
                   from: try await request("/api/v1/sessions/start", method: "POST",
                                           body: ["assignment_id": assignmentId, "day_id": dayId]))
    }

    func logSet(sessionId: Int, exerciseId: Int, setNumber: Int,
                reps: Int?, load: Double?, loadUnit: String, rpe: Int?, completed: Bool) async throws {
        var body: [String: Any] = [
            "workout_exercise_id": exerciseId,
            "set_number": setNumber,
            "load_unit": loadUnit,
            "completed": completed,
        ]
        body["reps_done"] = reps ?? NSNull()
        body["load_used"] = load ?? NSNull()
        body["rpe"] = rpe ?? NSNull()
        _ = try await request("/api/v1/sessions/\(sessionId)/log-set", method: "POST", body: body)
    }

    func finishSession(sessionId: Int, notes: String, interrupted: Bool) async throws {
        _ = try await request("/api/v1/sessions/\(sessionId)/finish", method: "POST",
                              body: ["notes": notes, "interrupted": interrupted])
    }

    /// Submit a multi-step check. `answers` is keyed by question id; values are
    /// String for text/metric/choice questions and [String] for multi-select.
    /// `attachments` maps an `allegato` question id to already-compressed JPEG
    /// bytes; when present the request is sent as multipart.
    func submitCheck(instanceId: Int, answers: [String: Any],
                     attachments: [String: [Data]] = [:]) async throws {
        let path = "/api/v1/checks/\(instanceId)/submit"
        let hasFiles = attachments.values.contains { !$0.isEmpty }
        if !hasFiles {
            _ = try await request(path, method: "POST", body: ["answers": answers])
            return
        }

        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        func field(_ s: String) { body.append(s.data(using: .utf8)!) }

        let answersJSON = String(data: try JSONSerialization.data(withJSONObject: answers), encoding: .utf8) ?? "{}"
        field("--\(boundary)\r\n")
        field("Content-Disposition: form-data; name=\"answers\"\r\n\r\n")
        field("\(answersJSON)\r\n")

        for (qid, images) in attachments {
            for (i, data) in images.enumerated() {
                field("--\(boundary)\r\n")
                field("Content-Disposition: form-data; name=\"attachment_\(qid)\"; filename=\"\(qid)_\(i).jpg\"\r\n")
                field("Content-Type: image/jpeg\r\n\r\n")
                body.append(data)
                field("\r\n")
            }
        }
        field("--\(boundary)--\r\n")

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.upload(for: req, from: body) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Nessuna risposta") }
        guard (200..<300).contains(http.statusCode) else {
            var msg = ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String { msg = err }
            throw APIError.http(http.statusCode, msg)
        }
    }

    func anamnesis() async throws -> AnamnesisDTO? {
        try decode(AnamnesisResponse.self, from: try await request("/api/v1/anamnesis")).anamnesis
    }

    func forgotPassword(email: String) async throws {
        _ = try await request("/api/v1/auth/forgot-password", method: "POST", body: ["email": email])
    }

    func deleteAccount() async throws {
        _ = try await request("/api/v1/account", method: "DELETE")
    }

    func completeTutorial() async throws {
        _ = try await request("/api/v1/tutorial/complete", method: "POST")
    }

    // MARK: MACRO-mode logging

    func searchFoods(_ query: String) async throws -> [FoodDTO] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try decode(FoodSearchResponse.self,
                          from: try await request("/api/v1/nutrition/foods?q=\(q)")).results
    }

    func macroDay(assignment: Int) async throws -> MacroDayDTO {
        try decode(MacroDayResponse.self,
                   from: try await request("/api/v1/nutrition/assignments/\(assignment)/macro-day")).macroDay
    }

    func addMacroLog(assignment: Int, foodId: Int, quantityG: Double, mealName: String?) async throws {
        var body: [String: Any] = ["food_id": foodId, "quantity_g": quantityG]
        if let mealName, !mealName.isEmpty { body["meal_name"] = mealName }
        _ = try await request("/api/v1/nutrition/assignments/\(assignment)/macro-log",
                              method: "POST", body: body)
    }

    func deleteMacroLog(entryId: Int) async throws {
        _ = try await request("/api/v1/nutrition/macro-log/\(entryId)", method: "DELETE")
    }

    // MARK: Journey timeline

    func journey() async throws -> [JourneyEventDTO] {
        try decode(JourneyResponse.self, from: try await request("/api/v1/journey")).events
    }
}
