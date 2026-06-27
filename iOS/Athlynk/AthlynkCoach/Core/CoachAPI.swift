//
//  CoachAPI.swift
//  Coach-side endpoints, layered onto the shared APIClient. Compiled only into
//  the Athlynk Coach target.
//

import Foundation

// MARK: - Chiron DTOs

struct ChironSource {
    let url: String
    let title: String
}

/// In-app "section" link Chiron emits (open a check, a client, …). `url` is a
/// web path (Django reverse), mapped to a native screen on tap.
struct ChironAction: Identifiable {
    let label: String
    let url: String
    var id: String { url }
}

private func parseChironActions(_ json: [String: Any]) -> [ChironAction] {
    (json["actions"] as? [[String: Any]] ?? []).compactMap { a in
        guard let u = a["url"] as? String, !u.isEmpty else { return nil }
        return ChironAction(label: a["label"] as? String ?? u, url: u)
    }
}

struct ChironEntry: Identifiable {
    let id: Int
    let role: String
    let content: String
    let sources: [ChironSource]
    let actions: [ChironAction]
    let usedWebSearch: Bool

    static func from(_ json: [String: Any]) -> ChironEntry? {
        guard let id = json["id"] as? Int,
              let role = json["role"] as? String,
              let content = json["content"] as? String else { return nil }
        let srcs = (json["sources"] as? [[String: Any]] ?? []).compactMap { s -> ChironSource? in
            guard let u = s["url"] as? String, let t = s["title"] as? String else { return nil }
            return ChironSource(url: u, title: t)
        }
        return ChironEntry(id: id, role: role, content: content, sources: srcs,
                           actions: parseChironActions(json),
                           usedWebSearch: json["used_web_search"] as? Bool ?? false)
    }
}

/// Streaming chat event: text arrives token-by-token, then one final `done`
/// carrying the authoritative full text + sources/actions/pending_action.
enum ChironStreamEvent {
    case token(String)
    case done(ChironChatResult)
}

struct ChironChatResult {
    let assistantContent: String
    let usedWebSearch: Bool
    let sources: [ChironSource]
    let actions: [ChironAction]
    let pendingAction: [String: Any]?
    let pendingActionLabel: String

    init(json: [String: Any]) {
        assistantContent = json["response"] as? String ?? ""
        usedWebSearch = json["used_web_search"] as? Bool ?? false
        sources = (json["sources"] as? [[String: Any]] ?? []).compactMap { s -> ChironSource? in
            guard let u = s["url"] as? String, let t = s["title"] as? String else { return nil }
            return ChironSource(url: u, title: t)
        }
        actions = parseChironActions(json)
        let pa = json["pending_action"] as? [String: Any]
        pendingAction = pa
        pendingActionLabel = pa?["label"] as? String
            ?? pa?["description"] as? String
            ?? pa?["type"] as? String
            ?? ""
    }
}

// MARK: -

extension APIClient {
    func coachDashboard() async throws -> CoachDashboardDTO {
        try decode(CoachDashboardDTO.self, from: try await request("/api/v1/coach/dashboard"))
    }

    func coachAgenda() async throws -> [CoachAgendaItem] {
        try decode(CoachAgendaResponse.self, from: try await request("/api/v1/coach/agenda")).appointments
    }

    func coachClients(query: String = "", status: String = "",
                      offset: Int = 0, limit: Int? = nil) async throws -> CoachClientsResponse {
        var path = "/api/v1/coach/clients"
        var qs: [String] = []
        if !query.isEmpty { qs.append("q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") }
        if !status.isEmpty { qs.append("status=\(status)") }
        if offset > 0 { qs.append("offset=\(offset)") }
        if let limit { qs.append("limit=\(limit)") }
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

    // MARK: Gestione modelli check (parità web)

    func coachCheckTemplates() async throws -> CoachCheckTemplatesResponse {
        try decode(CoachCheckTemplatesResponse.self,
                   from: try await request("/api/v1/coach/check-templates"))
    }

    func coachCheckTemplate(id: Int) async throws -> CoachCheckTemplateDetail {
        try decode(CoachCheckTemplateDetail.self,
                   from: try await request("/api/v1/coach/check-templates/\(id)"))
    }

    func coachCheckCatalog() async throws -> CheckCatalog {
        try decode(CheckCatalog.self, from: try await request("/api/v1/coach/check-catalog"))
    }

    @discardableResult
    func coachCreateCheckTemplate(title: String, steps: [[String: Any]],
                                  questions: [[String: Any]]) async throws -> CoachCheckTemplate {
        try decode(CoachCheckTemplate.self,
                   from: try await request("/api/v1/coach/check-templates/create", method: "POST",
                                           body: ["title": title, "steps_config": steps, "questions_config": questions]))
    }

    @discardableResult
    func coachUpdateCheckTemplate(id: Int, title: String, steps: [[String: Any]],
                                  questions: [[String: Any]]) async throws -> CoachCheckTemplate {
        try decode(CoachCheckTemplate.self,
                   from: try await request("/api/v1/coach/check-templates/\(id)/update", method: "POST",
                                           body: ["title": title, "steps_config": steps, "questions_config": questions]))
    }

    func coachDuplicateCheckTemplate(id: Int) async throws {
        _ = try await request("/api/v1/coach/check-templates/\(id)/duplicate", method: "POST")
    }

    func coachDeleteCheckTemplate(id: Int) async throws {
        _ = try await request("/api/v1/coach/check-templates/\(id)/delete", method: "POST")
    }

    func coachRestoreCheckTemplate(id: Int) async throws {
        _ = try await request("/api/v1/coach/check-templates/\(id)/restore", method: "POST")
    }

    func coachAssignCheck(templateId: Int, clientIds: [Int], recurrence: String,
                          weeklyDay: Int?, monthlyDay: Int?, durationHours: Int, notes: String) async throws {
        var body: [String: Any] = [
            "client_ids": clientIds, "recurrence_type": recurrence,
            "duration_hours": durationHours, "notes": notes,
        ]
        body["weekly_day"] = weeklyDay ?? NSNull()
        body["monthly_day"] = monthlyDay ?? NSNull()
        _ = try await request("/api/v1/coach/check-templates/\(templateId)/assign", method: "POST", body: body)
    }

    func coachFillCheck(templateId: Int, clientId: Int, answers: [String: Any], date: String?) async throws {
        var body: [String: Any] = ["client_id": clientId, "answers": answers]
        body["date"] = date ?? NSNull()
        _ = try await request("/api/v1/coach/check-templates/\(templateId)/fill", method: "POST", body: body)
    }

    func coachCheckPrefill(responseId: Int) async throws -> CoachCheckPrefill {
        try decode(CoachCheckPrefill.self,
                   from: try await request("/api/v1/coach/checks/\(responseId)/values"))
    }

    func coachUpdateCheckValues(responseId: Int, answers: [String: Any]) async throws {
        _ = try await request("/api/v1/coach/checks/\(responseId)/values/update",
                              method: "POST", body: ["answers": answers])
    }

    // MARK: Onboarding (coach crea atleta)

    func coachSubscriptionPlans() async throws -> [CoachSubscriptionPlanDTO] {
        try decode(CoachSubscriptionPlansResponse.self,
                   from: try await request("/api/v1/coach/subscription-plans")).plans
    }

    /// Creates a brand-new athlete; the server emails them an activation link.
    /// `birthDate` is ISO `yyyy-MM-dd` or nil; `gender` is "M"/"F"/nil.
    func coachCreateClient(firstName: String, lastName: String, email: String,
                           phone: String?, birthDate: String?, gender: String?,
                           subscriptionPlanId: Int, paymentNotes: String?) async throws {
        var body: [String: Any] = [
            "first_name": firstName, "last_name": lastName, "email": email,
            "subscription_plan_id": subscriptionPlanId,
        ]
        body["phone"] = phone ?? NSNull()
        body["birth_date"] = birthDate ?? NSNull()
        body["gender"] = gender ?? NSNull()
        body["payment_notes"] = paymentNotes ?? NSNull()
        _ = try await request("/api/v1/coach/clients/create", method: "POST", body: body)
    }

    /// Coach records one measurement for a client on a given day. Mirrors the
    /// athlete `addMeasurement`; `key` is the ISAK site (nil for weight).
    func coachAddMeasurement(clientId: Int, type: String, key: String?, value: Double, date: String) async throws {
        var body: [String: Any] = ["type": type, "value": value, "date": date]
        body["key"] = key ?? NSNull()
        _ = try await request("/api/v1/coach/clients/\(clientId)/measurement", method: "POST", body: body)
    }

    func coachClientFabbisogni(clientId: Int) async throws -> CoachFabbisogniDTO {
        try decode(CoachFabbisogniDTO.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/fabbisogni"))
    }

    func coachExerciseTrend(clientId: Int, workoutExerciseId: Int) async throws -> ExerciseTrendDTO {
        try decode(ExerciseTrendDTO.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/exercises/\(workoutExerciseId)/trend"))
    }

    func coachClientWorkout(clientId: Int) async throws -> CoachClientWorkoutDTO {
        try decode(CoachClientWorkoutDTO.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/workout"))
    }

    // MARK: Client percorso (journey + phases)

    func coachClientPercorso(clientId: Int) async throws -> JourneyResponse {
        try decode(JourneyResponse.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/percorso"))
    }

    @discardableResult
    func coachAddPhase(clientId: Int, title: String, startDate: String,
                       durationValue: Int, durationUnit: String, note: String) async throws -> JourneyPhaseDTO {
        let body: [String: Any] = [
            "title": title, "start_date": startDate,
            "duration_value": durationValue, "duration_unit": durationUnit, "note": note,
        ]
        return try decode(JourneyPhaseDTO.self,
                          from: try await request("/api/v1/coach/clients/\(clientId)/percorso/phases",
                                                  method: "POST", body: body))
    }

    @discardableResult
    func coachUpdatePhase(clientId: Int, phaseId: Int, title: String, startDate: String,
                          durationValue: Int, durationUnit: String, note: String) async throws -> JourneyPhaseDTO {
        let body: [String: Any] = [
            "title": title, "start_date": startDate,
            "duration_value": durationValue, "duration_unit": durationUnit, "note": note,
        ]
        return try decode(JourneyPhaseDTO.self,
                          from: try await request("/api/v1/coach/clients/\(clientId)/percorso/phases/\(phaseId)",
                                                  method: "PATCH", body: body))
    }

    func coachDeletePhase(clientId: Int, phaseId: Int) async throws {
        _ = try await request("/api/v1/coach/clients/\(clientId)/percorso/phases/\(phaseId)", method: "DELETE")
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

    /// Read-only view of what the athlete actually logged (active MACRO plan).
    /// Reuses the athlete's MacroHistory DTOs. `offset` pages back (14 per page).
    func coachClientMacroHistory(clientId: Int, offset: Int = 0) async throws -> MacroHistoryResponse {
        try decode(MacroHistoryResponse.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/macro-history?offset=\(offset)"))
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

    // MARK: Full plan wizard (web save/finalize/delete endpoints via dual auth)

    /// Edit-ready wizard payload of a workout plan (same shape the web wizard uses).
    func coachWorkoutBuilder(planId: Int) async throws -> [String: Any] {
        let data = try await request("/api/v1/coach/workouts/\(planId)/builder")
        return try coachJSONObject(data)["plan"] as? [String: Any] ?? [:]
    }

    /// Create (planId == nil) or update a workout plan through the web wizard
    /// save endpoint. Returns the saved plan dict (with server pks).
    @discardableResult
    func coachSaveWorkoutPlan(planId: Int?, payload: [String: Any]) async throws -> [String: Any] {
        let path = planId.map { "/api/allenamenti/\($0)/save/" } ?? "/api/allenamenti/save/"
        let data = try await request(path, method: "POST", body: payload)
        return try coachJSONObject(data)["plan"] as? [String: Any] ?? [:]
    }

    /// action = "template" | "assign" (with client_ids, weeks, overwrite).
    func coachFinalizeWorkoutPlan(planId: Int, payload: [String: Any]) async throws {
        _ = try await request("/api/allenamenti/\(planId)/finalize/", method: "POST", body: payload)
    }

    func coachDeleteWorkoutPlan(planId: Int) async throws {
        _ = try await request("/api/allenamenti/\(planId)/elimina/", method: "POST")
    }

    /// Deep-copy a workout plan into a new DRAFT. Returns the new plan id.
    @discardableResult
    func coachDuplicateWorkoutPlan(planId: Int) async throws -> Int {
        let data = try await request("/api/allenamenti/\(planId)/duplica/", method: "POST")
        return try coachJSONObject(data)["plan_id"] as? Int ?? 0
    }

    /// Edit-ready payload of a nutrition plan (meals/foods or macro targets).
    func coachNutritionBuilder(planId: Int) async throws -> [String: Any] {
        let data = try await request("/api/v1/coach/nutrition/\(planId)/builder")
        return try coachJSONObject(data)["plan"] as? [String: Any] ?? [:]
    }

    /// Create (planId == nil) or update a nutrition plan through the web save
    /// endpoint (handles FOOD/MACRO × DAILY/WEEKLY). Returns the plan id.
    @discardableResult
    func coachSaveNutritionPlan(planId: Int?, payload: [String: Any]) async throws -> Int {
        let path = planId.map { "/nutrizione/piani/\($0)/modifica/" } ?? "/nutrizione/piani/crea/"
        let data = try await request(path, method: "POST", body: payload)
        return try coachJSONObject(data)["plan_id"] as? Int ?? 0
    }

    func coachDeleteNutritionPlan(planId: Int) async throws {
        _ = try await request("/api/nutrizione/piani/\(planId)/elimina/", method: "POST")
    }

    /// Deep-copy a nutrition plan into a new DRAFT. Returns the new plan id.
    @discardableResult
    func coachDuplicateNutritionPlan(planId: Int) async throws -> Int {
        let data = try await request("/api/nutrizione/piani/\(planId)/duplica/", method: "POST")
        return try coachJSONObject(data)["id"] as? Int ?? 0
    }

    /// Assignable athletes with their currently active plan (for overwrite warnings).
    func coachAssignableClients(excludePlanId: Int? = nil) async throws -> [CoachAssignableClient] {
        var path = "/api/clients/search/"
        if let excludePlanId { path += "?exclude_plan_id=\(excludePlanId)" }
        return try decode([CoachAssignableClient].self, from: try await request(path))
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

    // MARK: Builder search (reuses the web search endpoints via dual auth)

    func coachSearchExercises(query: String) async throws -> [BuilderExercise] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try decode([BuilderExercise].self,
                          from: try await request("/api/exercises/search/?q=\(q)"))
    }

    func coachSearchFoods(query: String, filter: String? = nil,
                          cat: String? = nil, includeCats: Bool = false) async throws -> BuilderFoodSearchResponse {
        var comps = URLComponents()
        var items: [URLQueryItem] = []
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        if let filter, !filter.isEmpty { items.append(.init(name: "filter", value: filter)) }
        if let cat, !cat.isEmpty { items.append(.init(name: "cat", value: cat)) }
        if includeCats { items.append(.init(name: "include_cats", value: "1")) }
        comps.queryItems = items
        let qs = comps.percentEncodedQuery ?? ""
        return try decode(BuilderFoodSearchResponse.self,
                          from: try await request("/api/nutrizione/alimenti/?\(qs)"))
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

    // MARK: Manual progression grid (1:1 with the web Step-3 editor)

    /// Per-week effective values for every exercise of a day (forward-filled).
    /// Returns `{ exercises: [...], cells: {ex_id: {week: {metric: {...}}}}, duration_weeks }`.
    func coachProgressionGrid(planId: Int, dayId: Int) async throws -> [String: Any] {
        let data = try await request("/api/allenamenti/\(planId)/progression/day/\(dayId)/grid/")
        return (try coachJSONObject(data)["grid"] as? [String: Any]) ?? [:]
    }

    /// Upsert (or clear) one (exercise, week, metric) override. Week 1 is the
    /// builder-defined base and must not be edited here.
    @discardableResult
    func coachProgressionCell(planId: Int, exerciseId: Int, week: Int,
                              metric: String, value: Any?, clear: Bool) async throws -> [String: Any] {
        var body: [String: Any] = [
            "workout_exercise_id": exerciseId, "week_number": week,
            "metric": metric, "clear": clear,
        ]
        body["value"] = value ?? NSNull()
        return try coachJSONObject(try await request(
            "/api/allenamenti/\(planId)/progression/cell/", method: "POST", body: body))
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

    @discardableResult
    func coachUploadProfilePhoto(_ imageData: Data) async throws -> CoachProfileDTO {
        let data = try await coachMultipartUpload(
            "/api/v1/coach/profile/photo",
            fields: [:],
            fileField: "photo",
            fileName: "photo.jpg",
            fileMime: "image/jpeg",
            fileData: imageData
        )
        return try decode(CoachProfileResponse.self, from: data).profile
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

    // MARK: - Client progressi dashboard (reuses the web progressi endpoints)

    func coachClientKpi(clientId: Int) async throws -> CoachProgressKpiDTO {
        try decode(CoachProgressKpiDTO.self,
                   from: try await request("/api/coach/clienti/\(clientId)/progressi/kpi/"))
    }

    func coachClientAdherence(clientId: Int) async throws -> [AdherencePointDTO] {
        struct R: Codable { let series: [AdherencePointDTO] }
        return try decode(R.self,
                          from: try await request("/api/coach/clienti/\(clientId)/progressi/aderenza/")).series
    }

    func coachClientRpe(clientId: Int) async throws -> [RpePointDTO] {
        struct R: Codable { let series: [RpePointDTO] }
        return try decode(R.self,
                          from: try await request("/api/coach/clienti/\(clientId)/progressi/rpe/")).series
    }

    // MARK: - Client past sessions

    func coachClientSessions(clientId: Int, offset: Int = 0) async throws -> SessionBriefListDTO {
        try decode(SessionBriefListDTO.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/sessions?offset=\(offset)"))
    }

    func coachSessionDetail(_ id: Int) async throws -> SessionDetailDTO {
        try decode(SessionDetailDTO.self,
                   from: try await request("/api/v1/coach/sessions/\(id)"))
    }

    // MARK: - Chiron

    func coachChironHistory(before: Int? = nil) async throws -> ([ChironEntry], Bool) {
        var path = "/api/v1/coach/chiron/history/"
        if let b = before { path += "?before=\(b)" }
        let data = try await request(path)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rows = json["messages"] as? [[String: Any]] ?? []
        let hasMore = json["has_more"] as? Bool ?? false
        return (rows.compactMap { ChironEntry.from($0) }, hasMore)
    }

    func coachChironChat(message: String) async throws -> ChironChatResult {
        let data = try await request("/api/v1/coach/chiron/chat/", method: "POST", body: ["message": message])
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return ChironChatResult(json: json)
    }

    /// Streamed twin of `coachChironChat`: yields `.token` chunks as the model
    /// writes, then a final `.done`. Reads the SSE response line by line.
    func coachChironChatStream(message: String) -> AsyncThrowingStream<ChironStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: baseURL + "/api/v1/coach/chiron/chat/stream/") else {
                        throw APIError.badURL
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    req.httpBody = try JSONSerialization.data(withJSONObject: ["message": message])

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }   // SSE data frame
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                        else { continue }
                        if let err = obj["error"] as? String { throw APIError.transport(err) }
                        if let tok = obj["token"] as? String {
                            continuation.yield(.token(tok))
                        } else if obj["done"] as? Bool == true {
                            continuation.yield(.done(ChironChatResult(json: obj)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func coachChironClear() async throws {
        _ = try await request("/api/v1/coach/chiron/clear/", method: "POST", body: [:])
    }

    func coachChironExecute(_ action: [String: Any]) async throws -> (Bool, String) {
        let data = try await request("/api/v1/coach/chiron/azione/esegui/", method: "POST", body: action)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (json["ok"] as? Bool ?? false, json["message"] as? String ?? "")
    }

    // MARK: Supplement protocols (Integratori)

    func coachSupplements() async throws -> [CoachSupplementSummary] {
        try decode(CoachSupplementsResponse.self, from: try await request("/api/v1/coach/supplements")).protocols
    }

    func coachSupplementDetail(id: Int) async throws -> CoachSupplementDetail {
        try decode(CoachSupplementDetail.self, from: try await request("/api/v1/coach/supplements/\(id)"))
    }

    @discardableResult
    func coachSaveSupplement(id: Int?, title: String, notes: String, items: [[String: Any]]) async throws -> Int {
        var payload: [String: Any] = ["title": title, "notes": notes, "items": items]
        if let id { payload["id"] = id }
        let data = try await request("/api/v1/coach/supplements/save", method: "POST", body: payload)
        return try coachJSONObject(data)["id"] as? Int ?? 0
    }

    func coachDeleteSupplement(id: Int) async throws {
        _ = try await request("/api/v1/coach/supplements/\(id)/delete", method: "POST")
    }

    func coachAssignSupplement(id: Int, clientId: Int) async throws {
        _ = try await request("/api/v1/coach/supplements/\(id)/assign", method: "POST", body: ["client_id": clientId])
    }

    func coachSaveNutritionSupplements(planId: Int, items: [[String: Any]], notes: String) async throws {
        _ = try await request("/api/v1/coach/nutrition/\(planId)/supplements", method: "POST",
                              body: ["items": items, "notes": notes])
    }

    func coachSupplementModels() async throws -> [CoachSupplementModel] {
        try decode(CoachSupplementModelsResponse.self, from: try await request("/api/v1/coach/supplements/templates")).results
    }

    @discardableResult
    func coachSaveSupplementModel(_ item: [String: Any]) async throws -> Int {
        let data = try await request("/api/v1/coach/supplements/templates/save", method: "POST", body: item)
        return try coachJSONObject(data)["id"] as? Int ?? 0
    }

    func coachDeleteSupplementModel(id: Int) async throws {
        _ = try await request("/api/v1/coach/supplements/templates/\(id)/delete", method: "POST")
    }
}
