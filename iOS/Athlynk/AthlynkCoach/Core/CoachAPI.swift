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

    func coachAgenda(offset: Int = 0) async throws -> CoachAgendaResponse {
        try decode(CoachAgendaResponse.self, from: try await request("/api/v1/coach/agenda?offset=\(offset)"))
    }

    func coachClients(query: String = "", status: String = "",
                      offset: Int = 0, limit: Int? = nil, hasChecks: Bool = false) async throws -> CoachClientsResponse {
        var path = "/api/v1/coach/clients"
        var qs: [String] = []
        if !query.isEmpty { qs.append("q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") }
        if !status.isEmpty { qs.append("status=\(status)") }
        if offset > 0 { qs.append("offset=\(offset)") }
        if let limit { qs.append("limit=\(limit)") }
        if hasChecks { qs.append("has_checks=1") }
        if !qs.isEmpty { path += "?" + qs.joined(separator: "&") }
        return try decode(CoachClientsResponse.self, from: try await request(path))
    }

    func coachClient(id: Int) async throws -> CoachClientDetailDTO {
        try decode(CoachClientDetailDTO.self, from: try await request("/api/v1/coach/clients/\(id)"))
    }

    func coachClientChecks(clientId: Int, offset: Int = 0) async throws -> CoachClientChecksResponse {
        try decode(CoachClientChecksResponse.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/checks?offset=\(offset)"))
    }

    func coachChecks(filter: String = "pending", offset: Int = 0) async throws -> CoachChecksResponse {
        try decode(CoachChecksResponse.self, from: try await request("/api/v1/coach/checks?filter=\(filter)&offset=\(offset)"))
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

    /// folderId: nil = all plans, "unfiled" = no folder, or a numeric folder id as string.
    func coachWorkouts(q: String = "", offset: Int = 0, folderId: String? = nil) async throws -> CoachWorkoutsResponse {
        var path = "/api/v1/coach/workouts?offset=\(offset)"
        if !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(enc)"
        }
        if let folderId { path += "&folder_id=\(folderId)" }
        return try decode(CoachWorkoutsResponse.self, from: try await request(path))
    }

    func coachNutrition(q: String = "", offset: Int = 0, folderId: String? = nil) async throws -> CoachNutritionResponse {
        var path = "/api/v1/coach/nutrition?offset=\(offset)"
        if !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(enc)"
        }
        if let folderId { path += "&folder_id=\(folderId)" }
        return try decode(CoachNutritionResponse.self, from: try await request(path))
    }

    func coachSubscriptions(offset: Int = 0) async throws -> CoachSubscriptionsDTO {
        try decode(CoachSubscriptionsDTO.self, from: try await request("/api/v1/coach/subscriptions?offset=\(offset)"))
    }

    /// Create/edit/delete a subscription plan. `body` mirrors `SubscriptionPlanForm`'s
    /// fields (name/plan_type/kind/description/price/currency/duration_days/
    /// billing_interval/is_active) — see `CoachPlanFormView`.
    func coachCreatePlan(_ body: [String: Any]) async throws -> CoachPlanSummary {
        try decode(CoachPlanSummary.self, from: try await request(
            "/api/v1/coach/subscription-plans/create", method: "POST", body: body))
    }

    func coachUpdatePlan(id: Int, _ body: [String: Any]) async throws -> CoachPlanSummary {
        try decode(CoachPlanSummary.self, from: try await request(
            "/api/v1/coach/subscription-plans/\(id)", method: "PUT", body: body))
    }

    func coachDeletePlan(id: Int) async throws {
        _ = try await request("/api/v1/coach/subscription-plans/\(id)", method: "DELETE")
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

    /// Accepts or rejects an athlete's PENDING appointment request. `action` is
    /// "accept" | "reject". Accept requires `confirmedDate`/`confirmedTime`;
    /// reject may include a counter-proposal.
    func coachRequestAppointment(conversation: Int, title: String, preferredDate: String,
                                  timeFrom: String, timeTo: String, notes: String?) async throws -> MessageDTO {
        let data = try await request("/api/v1/coach/conversations/\(conversation)/appointment", method: "POST", body: [
            "title": title, "preferred_date": preferredDate,
            "time_from": timeFrom, "time_to": timeTo, "notes": notes ?? "",
        ])
        return try decode(MessageDTO.self, from: data)
    }

    func coachRespondAppointment(conversation: Int, appointmentId: Int, action: String,
                                  counterDate: String? = nil, counterTime: String? = nil) async throws -> MessageDTO {
        var body: [String: Any] = ["action": action]
        if let counterDate { body["counter_date"] = counterDate }
        if let counterTime { body["counter_time"] = counterTime }
        let data = try await request("/api/v1/coach/conversations/\(conversation)/appointment/\(appointmentId)/respond",
                                     method: "POST", body: body)
        return try decode(MessageDTO.self, from: data)
    }

    func coachProfile() async throws -> CoachProfileDTO {
        try decode(CoachProfileResponse.self, from: try await request("/api/v1/coach/profile")).profile
    }

    /// Kicks off (or resumes) Stripe Connect Express onboarding. The returned
    /// URL is opened in StripeWebFlow; the app never talks to Stripe directly.
    func coachConnectStart() async throws -> String {
        try decode(CoachConnectStartResponse.self,
                   from: try await request("/api/v1/coach/connect/start", method: "POST")).accountLinkUrl
    }

    /// Best-effort refresh after the onboarding web view closes — the
    /// account.updated webhook remains the source of truth server-side.
    func coachConnectStatus() async throws -> CoachConnectStatusResponse {
        try decode(CoachConnectStatusResponse.self, from: try await request("/api/v1/coach/connect/status"))
    }

    /// Stripe-hosted Billing Portal URL for the coach's own Athlynk platform
    /// subscription — open the returned URL in StripeWebFlow.
    func coachBillingPortal() async throws -> String {
        struct Resp: Decodable { let url: String }
        return try decode(Resp.self, from: try await request("/api/v1/coach/billing-portal", method: "POST")).url
    }

    func coachCalendarFeed() async throws -> CalendarFeedDTO {
        try decode(CalendarFeedDTO.self, from: try await request("/api/v1/coach/calendar-feed"))
    }

    @discardableResult
    func coachRotateCalendarFeed() async throws -> CalendarFeedDTO {
        try decode(CalendarFeedDTO.self, from: try await request(
            "/api/v1/coach/calendar-feed", method: "POST", body: ["action": "rotate"]))
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

    /// Adds an athlete to the coach's roster. `mode == "new"` creates a
    /// brand-new account and emails an activation link (first/last name
    /// required); `mode == "existing"` attaches an athlete already on the
    /// platform by email (all other `new`-only fields are ignored server-side).
    /// `subscriptionPlanId`/`paymentNotes` only matter when `alreadyPaid`.
    /// `birthDate` is ISO `yyyy-MM-dd` or nil; `gender` is "M"/"F"/"X"/nil.
    func coachCreateClient(mode: String = "new", firstName: String? = nil, lastName: String? = nil,
                           email: String, phone: String? = nil, birthDate: String? = nil, gender: String? = nil,
                           alreadyPaid: Bool, subscriptionPlanId: Int? = nil, paymentNotes: String? = nil) async throws {
        var body: [String: Any] = ["mode": mode, "email": email, "already_paid": alreadyPaid]
        body["first_name"] = firstName ?? NSNull()
        body["last_name"] = lastName ?? NSNull()
        body["phone"] = phone ?? NSNull()
        body["birth_date"] = birthDate ?? NSNull()
        body["gender"] = gender ?? NSNull()
        body["subscription_plan_id"] = subscriptionPlanId ?? NSNull()
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

    func coachClientPercorso(clientId: Int, offset: Int = 0) async throws -> JourneyResponse {
        try decode(JourneyResponse.self,
                   from: try await request("/api/v1/coach/clients/\(clientId)/percorso?offset=\(offset)"))
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
    /// `plan_title`) for in-app review before confirming.
    func coachImportDietExcel(file: Data, filename: String, title: String) async throws -> [String: Any] {
        let data = try await coachMultipartUpload(
            "/api/nutrizione/import/excel/", fields: ["plan_title": title],
            fileField: "file", fileName: filename,
            fileMime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileData: file)
        return try coachJSONObject(data)
    }

    func coachImportDietPDF(file: Data, filename: String, title: String) async throws -> String {
        let data = try await coachMultipartUpload(
            "/api/nutrizione/import/pdf/", fields: ["plan_title": title],
            fileField: "file", fileName: filename, fileMime: "application/pdf", fileData: file)
        return try coachJSONObject(data)["job_id"] as? String ?? ""
    }

    func coachDietImportStatus(jobId: String) async throws -> [String: Any] {
        try coachJSONObject(try await request("/api/nutrizione/import/pdf/status/?job_id=\(jobId)"))
    }

    /// Import never assigns to an athlete: assignment lives in the builder.
    func coachConfirmDiet(dietJson: [String: Any], title: String,
                          planKind: String = "DAILY", planMode: String = "FOOD") async throws {
        let body: [String: Any] = [
            "diet_json": dietJson, "plan_title": title,
            "plan_kind": planKind, "plan_mode": planMode,
        ]
        _ = try await request("/api/nutrizione/import/conferma/", method: "POST", body: body)
    }

    // MARK: Manual progression grid (1:1 with the web Step-3 editor)

    /// Per-week effective values for every exercise of a day (forward-filled).
    /// Returns `{ exercises: [...], cells: {ex_id: {week: {metric: {...}}}}, duration_weeks }`.
    func coachProgressionGrid(planId: Int, dayId: Int) async throws -> [String: Any] {
        let data = try await request("/api/allenamenti/\(planId)/progression/day/\(dayId)/grid/")
        return (try coachJSONObject(data)["grid"] as? [String: Any]) ?? [:]
    }

    /// Upsert (or clear) one (exercise, week, metric) value. Week 1 writes
    /// straight onto the builder's base exercise fields; week 2+ writes a
    /// forward-filled WeeklyOverride — same branch the web builder uses.
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

    func coachImportWorkoutExcel(file: Data, filename: String, title: String) async throws -> [String: Any] {
        let data = try await coachMultipartUpload(
            "/api/allenamenti/import/excel/", fields: ["plan_title": title],
            fileField: "file", fileName: filename,
            fileMime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileData: file)
        return try coachJSONObject(data)
    }

    func coachImportWorkoutPDF(file: Data, filename: String, title: String) async throws -> String {
        let data = try await coachMultipartUpload(
            "/api/allenamenti/import/pdf/", fields: ["plan_title": title],
            fileField: "file", fileName: filename, fileMime: "application/pdf", fileData: file)
        return try coachJSONObject(data)["job_id"] as? String ?? ""
    }

    func coachWorkoutImportStatus(jobId: String) async throws -> [String: Any] {
        try coachJSONObject(try await request("/api/allenamenti/import/pdf/status/?job_id=\(jobId)"))
    }

    /// Import never assigns to an athlete: assignment lives in the builder.
    func coachConfirmWorkout(workoutJson: [String: Any], title: String,
                             planKind: String = "WEEKLY", durationWeeks: Int = 1) async throws {
        let body: [String: Any] = [
            "workout_json": workoutJson, "plan_title": title,
            "plan_kind": planKind, "duration_weeks": durationWeeks,
        ]
        _ = try await request("/api/allenamenti/import/conferma/", method: "POST", body: body)
    }

    /// Create a coach-private custom exercise (same endpoint as the web
    /// import-review drawer). Returns the created {id, name, ...} payload.
    func coachCreateCustomExercise(name: String, primaryMuscleIds: [Int],
                                   secondaryMuscleIds: [Int] = [],
                                   equipmentIds: [Int] = [],
                                   categoryId: Int? = nil,
                                   notes: String = "") async throws -> [String: Any] {
        var body: [String: Any] = [
            "name": name,
            "primary_muscle_ids": primaryMuscleIds,
            "secondary_muscle_ids": secondaryMuscleIds,
            "equipment_ids": equipmentIds,
            "coach_notes": notes,
        ]
        if let categoryId { body["category_id"] = categoryId }
        return try coachJSONObject(try await request("/api/exercises/custom/", method: "POST", body: body))
    }

    /// Muscle-group taxonomy for the custom-exercise sheet.
    func coachMuscleGroups() async throws -> [[String: Any]] {
        let data = try await request("/api/muscle-groups/")
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
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

    /// Assignable athletes with their currently active diet plan (for overwrite warnings).
    func coachNutritionAssignableClients(excludePlanId: Int? = nil) async throws -> [CoachAssignableClient] {
        var path = "/api/v1/coach/nutrition/assignable-clients"
        if let excludePlanId { path += "?exclude_plan_id=\(excludePlanId)" }
        return try decode([CoachAssignableClient].self, from: try await request(path))
    }

    /// Assignable athletes with their currently active supplement protocol (for overwrite warnings).
    func coachSupplementAssignableClients(excludeProtocolId: Int? = nil) async throws -> [CoachSupplementAssignableClient] {
        var path = "/api/v1/coach/supplements/assignable-clients"
        if let excludeProtocolId { path += "?exclude_protocol_id=\(excludeProtocolId)" }
        return try decode([CoachSupplementAssignableClient].self, from: try await request(path))
    }

    // MARK: Folders (workout / nutrition / check — identical CRUD shape server-side)

    func coachFolders(_ domain: CoachFolderDomain) async throws -> [CoachFolder] {
        try decode([CoachFolder].self, from: try await request("\(domain.basePath)/"))
    }

    @discardableResult
    func coachCreateFolder(_ domain: CoachFolderDomain, title: String,
                           labelText: String = "", labelColor: String = "") async throws -> CoachFolder {
        var body: [String: Any] = ["title": title]
        if !labelText.isEmpty { body["label_text"] = labelText }
        if !labelColor.isEmpty { body["label_color"] = labelColor }
        return try decode(CoachFolder.self,
                          from: try await request("\(domain.basePath)/", method: "POST", body: body))
    }

    @discardableResult
    func coachRenameFolder(_ domain: CoachFolderDomain, folderId: Int, title: String) async throws -> CoachFolder {
        try decode(CoachFolder.self, from: try await request(
            "\(domain.basePath)/\(folderId)/", method: "PATCH", body: ["title": title]))
    }

    /// action: "move_to_unfiled" | "move_to" (needs targetFolderId) | "delete_plans"
    /// (same action names server-side for all three domains — checks call their contents "plans" too).
    @discardableResult
    func coachDeleteFolder(_ domain: CoachFolderDomain, folderId: Int,
                           action: String, targetFolderId: Int? = nil) async throws -> Bool {
        var path = "\(domain.basePath)/\(folderId)/?action=\(action)"
        if let targetFolderId { path += "&target_folder_id=\(targetFolderId)" }
        _ = try await request(path, method: "DELETE")
        return true
    }

    /// Moves a single plan/template in or out of a folder. `folderId: nil` unfiles it.
    @discardableResult
    func coachMoveItemToFolder(_ domain: CoachFolderDomain, itemId: Int, folderId: Int?) async throws -> Bool {
        let body: [String: Any] = ["folder_id": (folderId as Any?) ?? NSNull()]
        _ = try await request("\(domain.moveItemPath)/\(itemId)/cartella/", method: "PATCH", body: body)
        return true
    }

    /// Paginated custom check templates for one folder — the check-only counterpart
    /// of coachWorkouts/coachNutrition's built-in folder_id + offset pagination.
    func coachCheckTemplatesPage(folderId: String = "all", q: String = "", offset: Int = 0) async throws -> CoachCheckTemplatePage {
        var path = "/api/v1/coach/check-templates/page?folder_id=\(folderId)&offset=\(offset)"
        if !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(enc)"
        }
        return try decode(CoachCheckTemplatePage.self, from: try await request(path))
    }
}

enum CoachFolderDomain {
    case workout, nutrition, check

    var basePath: String {
        switch self {
        case .workout: return "/api/allenamenti/cartelle"
        case .nutrition: return "/api/nutrizione/cartelle"
        case .check: return "/api/check/cartelle"
        }
    }
    /// Path used to move a single plan/template into a folder (`/{id}/cartella/` appended by the caller).
    var moveItemPath: String {
        switch self {
        case .workout: return "/api/allenamenti/piani"
        case .nutrition: return "/api/nutrizione/piani"
        case .check: return "/api/check/modelli"
        }
    }
}
