//
//  APIClient.swift
//  Thin async wrapper over the Django /api/v1 backend.
//
//  Base URL is configurable via xcconfig and Info.plist.
//  All authenticated calls attach `Authorization: Bearer <token>`.
//

import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)
    case transport(String)

    /// User-facing copy only — never the raw server/technical string (those leak
    /// internals like "Content-Type deve essere application/json"). Use
    /// `debugDetail` for logging.
    var errorDescription: String? {
        switch self {
        case .transport: return "Problema di connessione. Controlla la rete e riprova."
        case .http(401, _): return "Email o password errati."
        default:         return "Si è verificato un errore. Riprova."
        }
    }

    /// Raw underlying detail, for logging/diagnostics — not for display.
    var debugDetail: String {
        switch self {
        case .badURL: return "badURL"
        case .http(let code, let msg): return "http \(code): \(msg)"
        case .decoding(let d): return "decoding: \(d)"
        case .transport(let t): return "transport: \(t)"
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    /// Resolved per build config from Info.plist (see AppConfig). Override-able
    /// so a physical device can point at the host's LAN IP.
    var baseURL = AppConfig.apiBaseURL
    var token: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        // Without this, waitsForConnectivity ignores the 20s request timeout and
        // waits up to the resource default (7 days) → spinner that never ends when
        // the network is briefly unreachable. Cap the whole attempt instead.
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    private let decoder = JSONDecoder()

    // MARK: Core request

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        // A single network blip (host briefly unreachable, 5xx during a redeploy)
        // used to surface as a definitive empty screen, because callers do
        // `try? await …` and render the failure as "no data". Retry transient
        // failures a couple of times so navigating into a section recovers on its
        // own instead of needing a manual close/reopen.
        // ponytail: fixed 2-retry + linear backoff; swap for exponential if a
        // flaky network ever needs it.
        var attempt = 0
        while true {
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Nessuna risposta") }
                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode >= 500, attempt < 2 {
                        attempt += 1
                        try await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
                        continue
                    }
                    var msg = ""
                    if let obj = try? JSONSerialization.jsonObject(with: data),
                       let dict = obj as? [String: Any],
                       let err = dict["error"] as? String {
                        msg = err
                    }
                    throw APIError.http(http.statusCode, msg)
                }
                return data
            } catch let error as URLError {
                // Respect a cancelled task — the view is gone, retrying is waste.
                if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
                guard attempt < 2 else { throw APIError.transport(error.localizedDescription) }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
            }
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    // MARK: Endpoints

    /// `role` declares which app is logging in ("CLIENT" | "COACH"): the server
    /// only matches users with that role, so each app rejects the other's users.
    func login(email: String, password: String, role: String) async throws -> LoginResponse {
        let data = try await request("/api/v1/auth/login", method: "POST",
                                     body: ["email": email, "password": password, "role": role])
        return try decode(LoginResponse.self, from: data)
    }

    func me() async throws -> MeResponse {
        try decode(MeResponse.self, from: try await request("/api/v1/me"))
    }

    func acceptTerms() async throws {
        _ = try await request("/api/v1/accept-terms", method: "POST", body: [:])
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

    /// Full read-back of a past submitted check (storico), including sections
    /// the athlete never fills themselves (e.g. Calcolo Fabbisogni).
    func checkDetail(responseId: Int) async throws -> CheckDetailDTO {
        try decode(CheckDetailDTO.self, from: try await request("/api/v1/checks/\(responseId)"))
    }

    /// `offset` pages back through the feed (20 per page). Returns the page and
    /// whether older notifications remain.
    func notifications(offset: Int = 0) async throws -> NotificationsResponse {
        try decode(NotificationsResponse.self,
                   from: try await request("/api/v1/notifications?offset=\(offset)"))
    }

    func conversations() async throws -> [ConversationDTO] {
        try decode(ConversationsResponse.self, from: try await request("/api/v1/conversations")).conversations
    }

    /// One page of recent messages (oldest→newest), newest page by default.
    /// `before` = id of the oldest message held; the server returns the page just
    /// before it (scroll-up history). `hasMore` reports whether older pages exist.
    func messages(conversation: Int, before: Int? = nil) async throws -> MessagesResponse {
        var path = "/api/v1/conversations/\(conversation)/messages"
        if let before { path += "?before=\(before)" }
        return try decode(MessagesResponse.self, from: try await request(path))
    }

    /// `since` = id of the last message held; the server returns only newer ones
    /// (empty when nothing changed). Used by the open chat's foreground poll.
    func newMessages(conversation: Int, since: Int) async throws -> [MessageDTO] {
        try decode(MessagesResponse.self,
                   from: try await request("/api/v1/conversations/\(conversation)/messages?since=\(since)")).messages
    }

    func send(conversation: Int, body: String) async throws {
        _ = try await request("/api/v1/conversations/\(conversation)/send",
                              method: "POST", body: ["body": body])
    }

    /// Sends a "richiesta appuntamento" into the chat — creates a PENDING appointment
    /// and returns the APPOINTMENT_REQUEST message that represents it in the thread.
    func requestAppointment(conversation: Int, title: String, preferredDate: String,
                             timeFrom: String, timeTo: String, notes: String?) async throws -> MessageDTO {
        let data = try await request("/api/v1/conversations/\(conversation)/appointment", method: "POST", body: [
            "title": title, "preferred_date": preferredDate,
            "time_from": timeFrom, "time_to": timeTo, "notes": notes ?? "",
        ])
        return try decode(MessageDTO.self, from: data)
    }

    /// Accepts or rejects a PENDING appointment request. `action` is "accept" | "reject".
    /// Accepting confirms the slot the requester already proposed, as-is — reject
    /// may include a counter-proposal.
    func respondAppointment(conversation: Int, appointmentId: Int, action: String,
                             counterDate: String? = nil, counterTime: String? = nil) async throws -> MessageDTO {
        var body: [String: Any] = ["action": action]
        if let counterDate { body["counter_date"] = counterDate }
        if let counterTime { body["counter_time"] = counterTime }
        let data = try await request("/api/v1/conversations/\(conversation)/appointment/\(appointmentId)/respond",
                                     method: "POST", body: body)
        return try decode(MessageDTO.self, from: data)
    }

    /// All of the client's own subscriptions — can be more than one when they
    /// have multiple coaches (e.g. a trainer + a nutritionist).
    func subscription() async throws -> [SubscriptionDTO] {
        try decode(SubscriptionListResponse.self, from: try await request("/api/v1/subscription")).subscriptions
    }

    /// Stripe Billing Portal URL for one subscription (cancel / change card).
    /// Only meaningful when `SubscriptionDTO.manageable` is true.
    func subscriptionBillingPortal(id: Int) async throws -> String {
        struct Resp: Decodable { let url: String }
        return try decode(Resp.self, from: try await request(
            "/api/v1/subscription/\(id)/billing-portal", method: "POST")).url
    }

    /// The athlete's own Google/Apple Calendar subscription feed (appointments
    /// across all their coaches). Coach counterpart: `CoachAPI.coachCalendarFeed`.
    func calendarFeed() async throws -> CalendarFeedDTO {
        try decode(CalendarFeedDTO.self, from: try await request("/api/v1/calendar-feed"))
    }

    @discardableResult
    func rotateCalendarFeed() async throws -> CalendarFeedDTO {
        try decode(CalendarFeedDTO.self, from: try await request(
            "/api/v1/calendar-feed", method: "POST", body: ["action": "rotate"]))
    }

    func dashboardSummary() async throws -> DashboardSummaryDTO {
        try decode(DashboardSummaryDTO.self, from: try await request("/api/v1/dashboard/summary"))
    }

    func appointments(offset: Int = 0) async throws -> AppointmentsResponse {
        try decode(AppointmentsResponse.self, from: try await request("/api/v1/appointments?offset=\(offset)"))
    }

    func progress(offset: Int = 0) async throws -> ProgressResponse {
        try decode(ProgressResponse.self, from: try await request("/api/v1/progress?offset=\(offset)"))
    }

    /// Body-part sites the client has EVER recorded a value for — independent
    /// of `progress`'s pagination, so the trend charts can show every site
    /// with data instead of only the ones on the currently-loaded page.
    func measurementSites() async throws -> MeasurementSitesDTO {
        try decode(MeasurementSitesDTO.self, from: try await request("/api/v1/progress/measurement-sites"))
    }

    func exerciseTrend(workoutExerciseId id: Int) async throws -> ExerciseTrendDTO {
        try decode(ExerciseTrendDTO.self, from: try await request("/api/v1/exercises/\(id)/trend"))
    }

    // MARK: Single measurement (peso / circonferenza / plica del giorno X)

    func measurementCatalog() async throws -> MeasurementCatalog {
        try decode(MeasurementCatalog.self, from: try await request("/api/v1/measurement-catalog"))
    }

    /// The athlete records one measurement on a given day. `type` is
    /// "weight" | "circumference" | "skinfold"; `key` is the ISAK site (nil for weight);
    /// `date` is ISO `yyyy-MM-dd`.
    func addMeasurement(type: String, key: String?, value: Double, date: String) async throws {
        var body: [String: Any] = ["type": type, "value": value, "date": date]
        body["key"] = key ?? NSNull()
        _ = try await request("/api/v1/progress/measurement", method: "POST", body: body)
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

    /// Upload the coach's avatar (JPEG bytes) as multipart; returns the new URL.
    @discardableResult
    func uploadCoachPhoto(_ imageData: Data) async throws -> String {
        guard let url = URL(string: baseURL + "/api/v1/coach/profile/photo") else { throw APIError.badURL }
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
        // Send the app's bundle id so the server can set the correct APNs topic
        // per device — the athlete and coach apps ship different bundle ids.
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        _ = try? await request("/api/v1/devices/register", method: "POST",
                               body: ["token": token, "platform": "ios", "bundle_id": bundleId])
    }

    func markNotificationRead(id: Int) async throws {
        _ = try await request("/api/v1/notifications/\(id)/read", method: "POST")
    }

    /// `offset` pages back through past sessions (20 per page).
    func workoutHistory(offset: Int = 0) async throws -> WorkoutHistoryResponse {
        try decode(WorkoutHistoryResponse.self,
                   from: try await request("/api/v1/workout-history?offset=\(offset)"))
    }

    /// Full detail (logged sets per exercise) of one past session.
    func workoutSessionDetail(_ id: Int) async throws -> SessionDetailDTO {
        try decode(SessionDetailDTO.self,
                   from: try await request("/api/v1/workout-history/\(id)"))
    }

    func supplements(offset: Int = 0) async throws -> SupplementsResponse {
        try decode(SupplementsResponse.self, from: try await request("/api/v1/supplements?offset=\(offset)"))
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

    // MARK: Customizable dashboard layout (synced with the web grid)

    func dashboardLayout() async throws -> DashboardLayoutResponse {
        try decode(DashboardLayoutResponse.self,
                   from: try await request("/api/v1/dashboard/layout"))
    }

    /// Full-replace save. Widgets are sent in array order with `y = index`
    /// so the web grid re-flows to match the mobile ordering.
    @discardableResult
    func updateDashboardLayout(_ layout: DashboardLayoutDTO) async throws -> DashboardLayoutResponse {
        let widgets: [[String: Any]] = layout.widgets.map { w in
            var d: [String: Any] = ["id": w.id, "type": w.type,
                                    "x": w.x, "y": w.y, "size": w.size]
            if let ids = w.config?.clientIds, !ids.isEmpty {
                d["config"] = ["client_ids": ids]
            } else {
                d["config"] = [String: Any]()
            }
            return d
        }
        return try decode(DashboardLayoutResponse.self,
                          from: try await request("/api/v1/dashboard/layout", method: "PUT",
                                                  body: ["version": layout.version,
                                                         "widgets": widgets]))
    }

    /// Reset to the role default layout.
    @discardableResult
    func resetDashboardLayout() async throws -> DashboardLayoutResponse {
        try decode(DashboardLayoutResponse.self,
                   from: try await request("/api/v1/dashboard/layout", method: "DELETE"))
    }

    /// Coach only: rows for the pinned-athletes widget, in the given order.
    func pinnedAthletes(ids: [Int]) async throws -> [PinnedAthleteDTO] {
        guard !ids.isEmpty else { return [] }
        let qs = ids.map(String.init).joined(separator: ",")
        return try decode(PinnedAthletesResponse.self,
                          from: try await request("/api/v1/coach/pinned-athletes?ids=\(qs)")).athletes
    }

    func plans() async throws -> [SubscriptionPlanDTO] {
        try decode(PlansResponse.self, from: try await request("/api/v1/plans")).plans
    }

    /// Starts a Stripe Checkout Session for an online-purchasable plan.
    /// Returns the hosted Checkout URL; open it via StripeWebFlow.
    func checkoutStart(planId: Int) async throws -> String {
        try decode(CheckoutStartResponse.self,
                   from: try await request("/api/v1/checkout/start", method: "POST", body: ["plan_id": planId])).checkoutUrl
    }

    // MARK: Write flows

    func sessionStart(assignmentId: Int, dayId: Int) async throws -> SessionStartDTO {
        try decode(SessionStartDTO.self,
                   from: try await request("/api/v1/sessions/start", method: "POST",
                                           body: ["assignment_id": assignmentId, "day_id": dayId]))
    }

    /// Log one set. Pass `workoutExerciseId` for plan-slot exercises; pass
    /// `addedExerciseId` (catalog id) for exercises added in-session. When the
    /// slot was substituted, set `substituted` + `actualExerciseId`.
    func logSet(sessionId: Int, workoutExerciseId: Int?, addedExerciseId: Int? = nil,
                setNumber: Int, reps: Int?, load: Double?, loadUnit: String,
                rpe: Int?, completed: Bool, isExtraSet: Bool = false,
                substituted: Bool = false, actualExerciseId: Int? = nil) async throws {
        var body: [String: Any] = [
            "set_number": setNumber,
            "load_unit": loadUnit,
            "completed": completed,
            "is_extra_set": isExtraSet,
            "exercise_substituted": substituted,
        ]
        body["workout_exercise_id"] = workoutExerciseId ?? NSNull()
        body["exercise_id"] = addedExerciseId ?? NSNull()
        body["actual_exercise_id"] = actualExerciseId ?? NSNull()
        body["reps_done"] = reps ?? NSNull()
        body["load_used"] = load ?? NSNull()
        body["rpe"] = rpe ?? NSNull()
        _ = try await request("/api/v1/sessions/\(sessionId)/log-set", method: "POST", body: body)
    }

    /// Persist the session-only plan deviations (add / remove / substitute).
    func setSessionOverrides(sessionId: Int, removed: [Int],
                             substituted: [Int: Int], added: [Int]) async throws {
        let body: [String: Any] = [
            "removed": removed,
            "substituted": Dictionary(uniqueKeysWithValues: substituted.map { ("\($0.key)", $0.value) }),
            "added": added.enumerated().map { ["exercise_id": $0.element, "order": $0.offset] },
        ]
        _ = try await request("/api/v1/sessions/\(sessionId)/overrides", method: "POST", body: body)
    }

    /// Exercise catalog search: by name, muscle group, or similar to a catalog id.
    func searchExercises(q: String = "", muscleGroup: String = "",
                         similarTo: Int? = nil, includeGroups: Bool = false) async throws -> ExerciseSearchResponse {
        var comps = URLComponents()
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "30")]
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if !muscleGroup.isEmpty { items.append(URLQueryItem(name: "muscle_group", value: muscleGroup)) }
        if let similarTo { items.append(URLQueryItem(name: "similar_to", value: "\(similarTo)")) }
        if includeGroups { items.append(URLQueryItem(name: "include_groups", value: "1")) }
        comps.queryItems = items
        let qs = comps.percentEncodedQuery ?? ""
        return try decode(ExerciseSearchResponse.self,
                          from: try await request("/api/v1/exercises/search?\(qs)"))
    }

    /// Full catalog detail (gif/description/instructions) for one exercise
    /// by id — shared by both apps (coach and athlete sessions both resolve
    /// via the backend's dual-auth session lookup).
    func exerciseCatalogDetail(id: Int) async throws -> ExerciseCatalogDetailDTO {
        try decode(ExerciseCatalogDetailDTO.self, from: try await request("/api/exercises/\(id)/"))
    }

    /// All movements the athlete has actually performed (progress list source).
    func progressExercises() async throws -> [ExerciseHistoryItemDTO] {
        try decode(ExercisesHistoryResponse.self,
                   from: try await request("/api/v1/progress/exercises")).exercises
    }

    /// History-based trend, keyed by exercise NAME (covers substituted/added).
    func exerciseTrend(name: String) async throws -> ExerciseTrendDTO {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return try decode(ExerciseTrendDTO.self,
                          from: try await request("/api/v1/exercises/trend-by-name?name=\(enc)"))
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


    func primaValutazione() async throws -> PrimaValutazioneDTO {
        try decode(PrimaValutazioneDTO.self, from: try await request("/api/v1/prima-valutazione"))
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

    func searchFoods(_ query: String, filter: String? = nil,
                     cat: String? = nil, includeCats: Bool = false) async throws -> FoodSearchResponse {
        var comps = URLComponents()
        var params: [URLQueryItem] = []
        if !query.isEmpty { params.append(.init(name: "q", value: query)) }
        if let filter { params.append(.init(name: "filter", value: filter)) }
        if let cat { params.append(.init(name: "cat", value: cat)) }
        if includeCats { params.append(.init(name: "include_cats", value: "1")) }
        comps.queryItems = params
        let qs = comps.percentEncodedQuery ?? ""
        return try decode(FoodSearchResponse.self, from: try await request("/api/v1/nutrition/foods?\(qs)"))
    }

    /// `date` (ISO yyyy-MM-dd) loads a past day for review/edit; nil = today.
    func macroDay(assignment: Int, date: String? = nil) async throws -> MacroDayDTO {
        var path = "/api/v1/nutrition/assignments/\(assignment)/macro-day"
        if let date { path += "?date=\(date)" }
        return try decode(MacroDayResponse.self, from: try await request(path)).macroDay
    }

    /// `offset` pages back through past logged days (14 per page).
    func macroHistory(assignment: Int, offset: Int = 0) async throws -> MacroHistoryResponse {
        try decode(MacroHistoryResponse.self,
                   from: try await request("/api/v1/nutrition/assignments/\(assignment)/macro-history?offset=\(offset)"))
    }

    /// `date` (ISO yyyy-MM-dd) logs against a past day; nil = today.
    func addMacroLog(assignment: Int, foodId: Int, quantityG: Double, mealName: String?, date: String? = nil) async throws {
        var body: [String: Any] = ["food_id": foodId, "quantity_g": quantityG]
        if let mealName, !mealName.isEmpty { body["meal_name"] = mealName }
        if let date { body["date"] = date }
        _ = try await request("/api/v1/nutrition/assignments/\(assignment)/macro-log",
                              method: "POST", body: body)
    }

    func deleteMacroLog(entryId: Int) async throws {
        _ = try await request("/api/v1/nutrition/macro-log/\(entryId)", method: "DELETE")
    }

    // MARK: Journey timeline

    func journey(offset: Int = 0) async throws -> JourneyResponse {
        try decode(JourneyResponse.self, from: try await request("/api/v1/journey?offset=\(offset)"))
    }

    @discardableResult
    func updateFoodSearchMode(_ mode: String) async throws -> SettingsDTO {
        try decode(SettingsResponse.self,
                   from: try await request("/api/v1/settings", method: "PATCH", body: ["food_search_mode": mode])).settings
    }
}
