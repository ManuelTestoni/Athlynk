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
}
