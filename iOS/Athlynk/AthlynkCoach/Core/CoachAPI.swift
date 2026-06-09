//
//  CoachAPI.swift
//  Coach-side endpoints, layered onto the shared APIClient. Compiled only into
//  the Athlynk Coach target.
//

import Foundation

extension APIClient {
    func coachDashboard() async throws -> CoachDashboardDTO {
        try decode(CoachDashboardDTO.self, from: try await request("/api/v1/coach/dashboard"))
    }

    func coachAgenda() async throws -> [CoachAgendaItem] {
        try decode(CoachAgendaResponse.self, from: try await request("/api/v1/coach/agenda")).appointments
    }

    func coachClients(query: String = "", status: String = "") async throws -> CoachClientsResponse {
        var path = "/api/v1/coach/clients"
        var qs: [String] = []
        if !query.isEmpty { qs.append("q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") }
        if !status.isEmpty { qs.append("status=\(status)") }
        if !qs.isEmpty { path += "?" + qs.joined(separator: "&") }
        return try decode(CoachClientsResponse.self, from: try await request(path))
    }

    func coachClient(id: Int) async throws -> CoachClientDetailDTO {
        try decode(CoachClientDetailDTO.self, from: try await request("/api/v1/coach/clients/\(id)"))
    }

    func coachChecks(filter: String = "pending") async throws -> CoachChecksResponse {
        try decode(CoachChecksResponse.self, from: try await request("/api/v1/coach/checks?filter=\(filter)"))
    }

    func coachCheck(id: Int) async throws -> CoachCheckDetailDTO {
        try decode(CoachCheckDetailResponse.self, from: try await request("/api/v1/coach/checks/\(id)")).check
    }

    @discardableResult
    func coachSendFeedback(checkId: Int, feedback: String, privateNotes: String?) async throws -> Bool {
        var body: [String: Any] = ["feedback": feedback]
        if let privateNotes { body["private_notes"] = privateNotes }
        _ = try await request("/api/v1/coach/checks/\(checkId)/feedback", method: "POST", body: body)
        return true
    }

    func coachWorkouts() async throws -> CoachWorkoutsResponse {
        try decode(CoachWorkoutsResponse.self, from: try await request("/api/v1/coach/workouts"))
    }

    func coachNutrition() async throws -> CoachNutritionResponse {
        try decode(CoachNutritionResponse.self, from: try await request("/api/v1/coach/nutrition"))
    }

    func coachSubscriptions() async throws -> CoachSubscriptionsDTO {
        try decode(CoachSubscriptionsDTO.self, from: try await request("/api/v1/coach/subscriptions"))
    }

    func coachResources() async throws -> [CoachResourceSection] {
        try decode(CoachResourcesResponse.self, from: try await request("/api/v1/coach/resources")).sections
    }

    func coachAnalytics() async throws -> CoachAnalyticsDTO {
        try decode(CoachAnalyticsDTO.self, from: try await request("/api/v1/coach/analytics"))
    }

    func coachAnalyticsBusiness() async throws -> CoachBusinessDTO {
        try decode(CoachBusinessDTO.self, from: try await request("/api/v1/coach/analytics/business"))
    }

    func coachAnalyticsRisk(riskClass: String = "all") async throws -> CoachRiskResponse {
        try decode(CoachRiskResponse.self,
                   from: try await request("/api/v1/coach/analytics/risk?class=\(riskClass)"))
    }

    func coachConversations() async throws -> [CoachConversation] {
        try decode(CoachConversationsResponse.self, from: try await request("/api/v1/coach/conversations")).conversations
    }

    func coachMessages(conversation: Int, before: Int? = nil) async throws -> CoachMessagesResponse {
        var path = "/api/v1/coach/conversations/\(conversation)/messages"
        if let before { path += "?before=\(before)" }
        return try decode(CoachMessagesResponse.self, from: try await request(path))
    }

    func coachNewMessages(conversation: Int, since: Int) async throws -> [MessageDTO] {
        try decode(CoachMessagesResponse.self,
                   from: try await request("/api/v1/coach/conversations/\(conversation)/messages?since=\(since)")).messages
    }

    func coachSend(conversation: Int, body: String) async throws {
        _ = try await request("/api/v1/coach/conversations/\(conversation)/send",
                              method: "POST", body: ["body": body])
    }

    func coachProfile() async throws -> CoachProfileDTO {
        try decode(CoachProfileResponse.self, from: try await request("/api/v1/coach/profile")).profile
    }

    @discardableResult
    func coachUpdateProfile(_ fields: [String: Any]) async throws -> CoachProfileDTO {
        try decode(CoachProfileResponse.self,
                   from: try await request("/api/v1/coach/profile", method: "PATCH", body: fields)).profile
    }

    // MARK: Client charts

    func coachClientProgress(clientId: Int) async throws -> [CoachProgressEntry] {
        try decode(CoachProgressResponse.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/progress")).entries
    }

    // MARK: Agenda CRUD

    @discardableResult
    func coachCreateAppointment(clientId: Int, title: String, type: String,
                                startISO: String, durationMinutes: Int,
                                description: String?, meetingUrl: String?) async throws -> CoachAgendaItem {
        var body: [String: Any] = [
            "client_id": clientId, "title": title, "appointment_type": type,
            "start_datetime": startISO, "duration_minutes": durationMinutes,
        ]
        if let description { body["description"] = description }
        if let meetingUrl { body["meeting_url"] = meetingUrl }
        return try decode(CoachAppointmentResponse.self,
                          from: try await request("/api/v1/coach/agenda/create", method: "POST", body: body)).appointment
    }

    @discardableResult
    func coachUpdateAppointment(id: Int, fields: [String: Any]) async throws -> CoachAgendaItem {
        try decode(CoachAppointmentResponse.self,
                   from: try await request("/api/v1/coach/agenda/\(id)", method: "PATCH", body: fields)).appointment
    }

    func coachDeleteAppointment(id: Int) async throws {
        _ = try await request("/api/v1/coach/agenda/\(id)", method: "DELETE")
    }

    // MARK: Plan detail

    func coachWorkoutDetail(planId: Int) async throws -> CoachWorkoutDetailDTO {
        try decode(CoachWorkoutDetailResponse.self,
                   from: try await request("/api/v1/coach/workouts/\(planId)")).plan
    }

    func coachNutritionDetail(planId: Int) async throws -> CoachNutritionDetailDTO {
        try decode(CoachNutritionDetailResponse.self,
                   from: try await request("/api/v1/coach/nutrition/\(planId)")).plan
    }

    // MARK: Lightweight manual builders

    @discardableResult
    func coachCreateWorkout(_ payload: [String: Any]) async throws -> Int {
        let data = try await request("/api/v1/coach/workouts/create", method: "POST", body: payload)
        return try coachJSONObject(data)["plan_id"] as? Int ?? 0
    }

    @discardableResult
    func coachCreateNutrition(_ payload: [String: Any]) async throws -> Int {
        let data = try await request("/api/v1/coach/nutrition/create", method: "POST", body: payload)
        return try coachJSONObject(data)["plan_id"] as? Int ?? 0
    }

    func coachAssignWorkout(planId: Int, clientId: Int, startDate: String? = nil) async throws {
        var body: [String: Any] = ["client_id": clientId]
        if let startDate { body["start_date"] = startDate }
        _ = try await request("/api/v1/coach/workouts/\(planId)/assign", method: "POST", body: body)
    }

    /// Reuses the web nutrition-assign endpoint (dual session/Bearer auth).
    func coachAssignNutrition(planId: Int, clientId: Int, startDate: String? = nil, endDate: String? = nil) async throws {
        var body: [String: Any] = ["client_id": clientId]
        if let startDate { body["start_date"] = startDate }
        if let endDate { body["end_date"] = endDate }
        _ = try await request("/api/nutrizione/piani/\(planId)/assegna/", method: "POST", body: body)
    }

    // MARK: Automatic replies

    func coachAutoMessages() async throws -> [CoachAutoMessage] {
        try decode(CoachAutoMessagesResponse.self,
                   from: try await request("/api/v1/coach/auto-messages")).messages
    }

    @discardableResult
    func coachUpdateAutoMessages(_ messages: [[String: Any]]) async throws -> [CoachAutoMessage] {
        try decode(CoachAutoMessagesResponse.self,
                   from: try await request("/api/v1/coach/auto-messages", method: "PATCH",
                                           body: ["messages": messages])).messages
    }

    // MARK: New conversation

    func coachMessageableClients() async throws -> [CoachMessageableClient] {
        try decode(CoachMessageableClientsResponse.self,
                   from: try await request("/api/v1/coach/messageable-clients")).clients
    }

    @discardableResult
    func coachStartConversation(clientId: Int, body: String) async throws -> Int {
        try decode(CoachStartConversationResponse.self,
                   from: try await request("/api/v1/coach/conversations/start", method: "POST",
                                           body: ["client_id": clientId, "body": body])).conversationId
    }

    // MARK: Chiron AI import (reuses the web import endpoints via dual auth)

    /// Excel diet import → returns the parsed extraction payload (`extracted`,
    /// `plan_title`, `client`) for in-app review before confirming.
    func coachImportDietExcel(file: Data, filename: String, title: String, clientId: Int?) async throws -> [String: Any] {
        var fields = ["plan_title": title]
        if let clientId { fields["client_id"] = String(clientId) }
        let data = try await coachMultipartUpload(
            "/api/nutrizione/import/excel/", fields: fields,
            fileField: "file", fileName: filename,
            fileMime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileData: file)
        return try coachJSONObject(data)
    }

    func coachImportDietPDF(file: Data, filename: String, title: String, clientId: Int?) async throws -> String {
        var fields = ["plan_title": title]
        if let clientId { fields["client_id"] = String(clientId) }
        let data = try await coachMultipartUpload(
            "/api/nutrizione/import/pdf/", fields: fields,
            fileField: "file", fileName: filename, fileMime: "application/pdf", fileData: file)
        return try coachJSONObject(data)["job_id"] as? String ?? ""
    }

    func coachDietImportStatus(jobId: String) async throws -> [String: Any] {
        try coachJSONObject(try await request("/api/nutrizione/import/pdf/status/?job_id=\(jobId)"))
    }

    func coachConfirmDiet(dietJson: [String: Any], title: String, clientId: Int?, assignNow: Bool) async throws {
        var body: [String: Any] = ["diet_json": dietJson, "plan_title": title, "assign_now": assignNow]
        if let clientId { body["client_id"] = clientId }
        _ = try await request("/api/nutrizione/import/conferma/", method: "POST", body: body)
    }

    func coachImportWorkoutExcel(file: Data, filename: String, title: String, clientId: Int?) async throws -> [String: Any] {
        var fields = ["plan_title": title]
        if let clientId { fields["client_id"] = String(clientId) }
        let data = try await coachMultipartUpload(
            "/api/allenamenti/import/excel/", fields: fields,
            fileField: "file", fileName: filename,
            fileMime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileData: file)
        return try coachJSONObject(data)
    }

    func coachImportWorkoutPDF(file: Data, filename: String, title: String, clientId: Int?) async throws -> String {
        var fields = ["plan_title": title]
        if let clientId { fields["client_id"] = String(clientId) }
        let data = try await coachMultipartUpload(
            "/api/allenamenti/import/pdf/", fields: fields,
            fileField: "file", fileName: filename, fileMime: "application/pdf", fileData: file)
        return try coachJSONObject(data)["job_id"] as? String ?? ""
    }

    func coachWorkoutImportStatus(jobId: String) async throws -> [String: Any] {
        try coachJSONObject(try await request("/api/allenamenti/import/pdf/status/?job_id=\(jobId)"))
    }

    func coachConfirmWorkout(workoutJson: [String: Any], title: String, clientId: Int?,
                             assignNow: Bool, planKind: String = "WEEKLY", durationWeeks: Int = 1) async throws {
        var body: [String: Any] = [
            "workout_json": workoutJson, "plan_title": title, "assign_now": assignNow,
            "plan_kind": planKind, "duration_weeks": durationWeeks,
        ]
        if let clientId { body["client_id"] = clientId }
        _ = try await request("/api/allenamenti/import/conferma/", method: "POST", body: body)
    }

    // MARK: Multipart / raw-JSON plumbing

    private func coachMultipartUpload(_ path: String, fields: [String: String],
                                      fileField: String, fileName: String,
                                      fileMime: String, fileData: Data) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        func f(_ s: String) { body.append(s.data(using: .utf8)!) }
        for (k, v) in fields {
            f("--\(boundary)\r\n")
            f("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
            f("\(v)\r\n")
        }
        f("--\(boundary)\r\n")
        f("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        f("Content-Type: \(fileMime)\r\n\r\n")
        body.append(fileData)
        f("\r\n--\(boundary)--\r\n")

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.upload(for: req, from: body) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Nessuna risposta") }
        // 206 = import succeeded but flagged high uncertainty — still usable.
        guard (200..<300).contains(http.statusCode) else {
            var msg = ""
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = o["error"] as? String { msg = e }
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    private func coachJSONObject(_ data: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding("JSON non valido")
        }
        return o
    }
}
