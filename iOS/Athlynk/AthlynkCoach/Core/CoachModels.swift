//
//  CoachModels.swift
//  Codable DTOs mirroring the Django /api/v1/coach JSON shapes. Coach-app only.
//

import Foundation

// MARK: - Client (the "other party" on the coach side)

struct CoachClient: Codable, Identifiable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let displayName: String
    let profileImageUrl: String?
    let primaryGoal: String?
    let sport: String?
    // Extended fields (present only in client detail).
    let phone: String?
    let gender: String?
    let birthDate: String?
    let heightCm: Int?
    let weightKg: Double?
    let activityLevel: String?
    let email: String?

    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    enum CodingKeys: String, CodingKey {
        case id, phone, gender, sport, email
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case profileImageUrl = "profile_image_url"
        case primaryGoal = "primary_goal"
        case birthDate = "birth_date"
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case activityLevel = "activity_level"
    }
}

// MARK: - Coach's own profile

struct CoachProfileDTO: Codable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let professionalType: String?
    let specialization: String?
    let city: String?
    let phone: String?
    let bio: String?
    let description: String?
    let certifications: String?
    let yearsExperience: Int?
    let profileImageUrl: String?
    let socialInstagram: String?
    let socialYoutube: String?
    let socialTiktok: String?
    let socialWebsite: String?
    let email: String?

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
    var initials: String {
        let s = ((firstName.first.map(String.init) ?? "") + (lastName.first.map(String.init) ?? "")).uppercased()
        return s.isEmpty ? "C" : s
    }
    var roleLabel: String {
        switch (professionalType ?? "").uppercased() {
        case "ALLENATORE": return "Allenatore"
        case "NUTRIZIONISTA": return "Nutrizionista"
        default: return "Coach"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, city, phone, bio, description, certifications, email, specialization
        case firstName = "first_name"
        case lastName = "last_name"
        case professionalType = "professional_type"
        case yearsExperience = "years_experience"
        case profileImageUrl = "profile_image_url"
        case socialInstagram = "social_instagram"
        case socialYoutube = "social_youtube"
        case socialTiktok = "social_tiktok"
        case socialWebsite = "social_website"
    }
}

struct CoachProfileResponse: Codable { let profile: CoachProfileDTO }

// MARK: - Dashboard

struct CoachStats: Codable, Hashable {
    let activeClients: Int
    let pendingChecks: Int
    let appointmentsToday: Int
    let unreadMessages: Int
    enum CodingKeys: String, CodingKey {
        case activeClients = "active_clients"
        case pendingChecks = "pending_checks"
        case appointmentsToday = "appointments_today"
        case unreadMessages = "unread_messages"
    }
}

struct CoachAgendaItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let type: String?
    let description: String?
    let start: String?
    let durationMinutes: Int?
    let location: String?
    let meetingUrl: String?
    let status: String?
    let client: CoachClient?

    enum CodingKeys: String, CodingKey {
        case id, title, type, description, start, location, status, client
        case durationMinutes = "duration_minutes"
        case meetingUrl = "meeting_url"
    }
}

struct CoachActivity: Codable, Identifiable, Hashable {
    let id: Int
    let type: String
    let title: String
    let body: String?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, type, title, body
        case createdAt = "created_at"
    }
}

struct CoachInsight: Codable, Hashable {
    let checksThisWeek: Int
    let text: String
    enum CodingKeys: String, CodingKey {
        case checksThisWeek = "checks_this_week"
        case text
    }
}

struct CoachDashboardDTO: Codable {
    let coach: CoachProfileDTO
    let stats: CoachStats
    let agenda: [CoachAgendaItem]
    let activity: [CoachActivity]
    let insight: CoachInsight
}

struct CoachAgendaResponse: Codable { let appointments: [CoachAgendaItem] }

// MARK: - Clients list

struct CoachClientRow: Codable, Identifiable, Hashable {
    let id: Int
    let displayName: String
    let firstName: String
    let lastName: String
    let profileImageUrl: String?
    let primaryGoal: String?
    let relationshipType: String?
    let status: String?
    let startDate: String?
    let activeWorkout: String?
    let activePlan: String?
    let lastCheckAt: String?

    var initials: String {
        let s = ((firstName.first.map(String.init) ?? "") + (lastName.first.map(String.init) ?? "")).uppercased()
        return s.isEmpty ? "A" : s
    }
    var relationshipLabel: String {
        switch (relationshipType ?? "").uppercased() {
        case "WORKOUT": return "Allenamento"
        case "NUTRITION": return "Nutrizione"
        case "FULL": return "Full Coaching"
        default: return "Cliente"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageUrl = "profile_image_url"
        case primaryGoal = "primary_goal"
        case relationshipType = "relationship_type"
        case startDate = "start_date"
        case activeWorkout = "active_workout"
        case activePlan = "active_plan"
        case lastCheckAt = "last_check_at"
    }
}

struct CoachClientsResponse: Codable {
    let clients: [CoachClientRow]
    let total: Int
    let active: Int
}

// MARK: - Client detail

struct TitleRef: Codable, Hashable {
    let assignmentId: Int?
    let title: String
    enum CodingKeys: String, CodingKey { case title; case assignmentId = "assignment_id" }
}

struct CoachSubRef: Codable, Hashable {
    let id: Int
    let name: String
    let price: Double
    let status: String
    let endDate: String?
    enum CodingKeys: String, CodingKey { case id, name, price, status; case endDate = "end_date" }
}

struct CoachRelationship: Codable, Hashable {
    let id: Int
    let type: String?
    let status: String?
    let startDate: String?
    let internalNotes: String?
    enum CodingKeys: String, CodingKey {
        case id, type, status
        case startDate = "start_date"
        case internalNotes = "internal_notes"
    }
}

struct CoachCheckRow: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let submittedAt: String?
    let weightKg: Double?
    let reviewed: Bool
    let client: CoachClient?
    enum CodingKeys: String, CodingKey {
        case id, title, reviewed, client
        case submittedAt = "submitted_at"
        case weightKg = "weight_kg"
    }
}

struct IdTitle: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
}

struct CoachClientDetailDTO: Codable {
    let client: CoachClient
    let relationship: CoachRelationship
    let activeWorkout: TitleRef?
    let activeNutrition: TitleRef?
    let activeSubscription: CoachSubRef?
    let checks: [CoachCheckRow]
    let supplementSheets: [IdTitle]
    let hasAnamnesis: Bool
    let conversationId: Int?

    enum CodingKeys: String, CodingKey {
        case client, relationship, checks
        case activeWorkout = "active_workout"
        case activeNutrition = "active_nutrition"
        case activeSubscription = "active_subscription"
        case supplementSheets = "supplement_sheets"
        case hasAnamnesis = "has_anamnesis"
        case conversationId = "conversation_id"
    }
}

// MARK: - Check review

struct CoachChecksResponse: Codable {
    let checks: [CoachCheckRow]
    let pendingCount: Int
    enum CodingKeys: String, CodingKey { case checks; case pendingCount = "pending_count" }
}

struct CoachCheckPhoto: Codable, Identifiable, Hashable {
    let id: Int
    let url: String
    let type: String?
    let capturedAt: String?
    enum CodingKeys: String, CodingKey { case id, url, type; case capturedAt = "captured_at" }
}

struct CoachCheckDetailDTO: Codable {
    let id: Int
    let title: String
    let submittedAt: String?
    let weightKg: Double?
    let measurements: [String: String]
    let skinfolds: [String: String]
    let notes: String?
    let injuries: String?
    let limitations: String?
    let coachFeedback: String
    let coachPrivateNotes: String
    let client: CoachClient
    let photos: [CoachCheckPhoto]

    enum CodingKeys: String, CodingKey {
        case id, title, measurements, skinfolds, notes, injuries, limitations, client, photos
        case submittedAt = "submitted_at"
        case weightKg = "weight_kg"
        case coachFeedback = "coach_feedback"
        case coachPrivateNotes = "coach_private_notes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        submittedAt = try? c.decodeIfPresent(String.self, forKey: .submittedAt)
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        measurements = (try? c.decode([String: String].self, forKey: .measurements)) ?? [:]
        skinfolds = (try? c.decode([String: String].self, forKey: .skinfolds)) ?? [:]
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        injuries = try? c.decodeIfPresent(String.self, forKey: .injuries)
        limitations = try? c.decodeIfPresent(String.self, forKey: .limitations)
        coachFeedback = (try? c.decode(String.self, forKey: .coachFeedback)) ?? ""
        coachPrivateNotes = (try? c.decode(String.self, forKey: .coachPrivateNotes)) ?? ""
        client = try c.decode(CoachClient.self, forKey: .client)
        photos = (try? c.decode([CoachCheckPhoto].self, forKey: .photos)) ?? []
    }
}

struct CoachCheckDetailResponse: Codable { let check: CoachCheckDetailDTO }

// MARK: - Workout / Nutrition management

struct CoachPlanRow: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let goal: String?
    let level: String?
    let durationWeeks: Int?
    let frequencyPerWeek: Int?
    let planMode: String?
    let planKind: String?
    let dailyKcal: Int?
    let assignedCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, goal, level
        case durationWeeks = "duration_weeks"
        case frequencyPerWeek = "frequency_per_week"
        case planMode = "plan_mode"
        case planKind = "plan_kind"
        case dailyKcal = "daily_kcal"
        case assignedCount = "assigned_count"
    }
}

struct CoachAssignmentRow: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let client: CoachClient
    let startDate: String?
    enum CodingKeys: String, CodingKey { case id, title, client; case startDate = "start_date" }
}

struct CoachWorkoutsResponse: Codable {
    let plans: [CoachPlanRow]
    let assignments: [CoachAssignmentRow]
}

struct CoachNutritionResponse: Codable {
    let plans: [CoachPlanRow]
    let assignments: [CoachAssignmentRow]
}

// MARK: - Subscriptions

struct CoachPlanSummary: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let planType: String?
    let price: Double
    let currency: String
    let billingInterval: String?
    let isActive: Bool
    let activeCount: Int
    enum CodingKeys: String, CodingKey {
        case id, name, price, currency
        case planType = "plan_type"
        case billingInterval = "billing_interval"
        case isActive = "is_active"
        case activeCount = "active_count"
    }
}

struct CoachSubscriptionRow: Codable, Identifiable, Hashable {
    let id: Int
    let client: CoachClient
    let planName: String
    let price: Double
    let status: String
    let paymentStatus: String?
    let startDate: String?
    let endDate: String?
    enum CodingKeys: String, CodingKey {
        case id, client, price, status
        case planName = "plan_name"
        case paymentStatus = "payment_status"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct CoachSubscriptionsDTO: Codable {
    let plans: [CoachPlanSummary]
    let subscriptions: [CoachSubscriptionRow]
    let activeCount: Int
    let monthlyRevenue: Double
    let currency: String
    enum CodingKeys: String, CodingKey {
        case plans, subscriptions, currency
        case activeCount = "active_count"
        case monthlyRevenue = "monthly_revenue"
    }
}

// MARK: - Resources

struct CoachResourceItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let goal: String?
    let planMode: String?
    let type: String?
    let active: Bool?
    enum CodingKeys: String, CodingKey { case id, title, goal, type, active; case planMode = "plan_mode" }
}

struct CoachResourceSection: Codable, Identifiable, Hashable {
    let key: String
    let label: String
    let icon: String
    let count: Int
    let items: [CoachResourceItem]
    var id: String { key }
}

struct CoachResourcesResponse: Codable { let sections: [CoachResourceSection] }

// MARK: - Analytics

struct CoachWeekPoint: Codable, Identifiable, Hashable {
    let weekStart: String
    let count: Int
    var id: String { weekStart }
    enum CodingKeys: String, CodingKey { case count; case weekStart = "week_start" }
}

struct CoachAnalyticsDTO: Codable {
    let activeClients: Int
    let totalChecks: Int
    let reviewedChecks: Int
    let reviewRate: Double
    let checksSeries: [CoachWeekPoint]
    enum CodingKeys: String, CodingKey {
        case activeClients = "active_clients"
        case totalChecks = "total_checks"
        case reviewedChecks = "reviewed_checks"
        case reviewRate = "review_rate"
        case checksSeries = "checks_series"
    }
}

// MARK: - Messaging

struct CoachConversation: Codable, Identifiable, Hashable {
    let id: Int
    let client: CoachClient
    let lastMessage: String?
    let lastMessageAt: String?
    let unread: Int
    enum CodingKeys: String, CodingKey {
        case id, client, unread
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
    }
}

struct CoachConversationsResponse: Codable { let conversations: [CoachConversation] }

struct CoachMessagesResponse: Codable {
    let messages: [MessageDTO]
    let hasMore: Bool?
    let client: CoachClient?
    enum CodingKeys: String, CodingKey { case messages, client; case hasMore = "has_more" }
}

// MARK: - Client progress / charts

struct CoachProgressEntry: Codable, Identifiable, Hashable {
    let id: Int
    let submittedAt: String?
    let weightKg: Double?
    let measurements: [String: String]
    let coachFeedback: String?
    let notes: String?
    let photos: [CoachCheckPhoto]

    enum CodingKeys: String, CodingKey {
        case id, measurements, notes, photos
        case submittedAt = "submitted_at"
        case weightKg = "weight_kg"
        case coachFeedback = "coach_feedback"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        submittedAt = try? c.decodeIfPresent(String.self, forKey: .submittedAt)
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        measurements = (try? c.decode([String: String].self, forKey: .measurements)) ?? [:]
        coachFeedback = try? c.decodeIfPresent(String.self, forKey: .coachFeedback)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        photos = (try? c.decode([CoachCheckPhoto].self, forKey: .photos)) ?? []
    }
}

struct CoachProgressResponse: Codable { let entries: [CoachProgressEntry] }

// MARK: - Plan detail (workout)

struct CoachWorkoutExerciseDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let sets: Int?
    let reps: Int?
    let repRange: String?
    let rir: Int?
    let rpe: Int?
    let recoverySeconds: Int?
    let tempo: String?
    let notes: String?
    enum CodingKeys: String, CodingKey {
        case id, name, sets, reps, rir, rpe, tempo, notes
        case repRange = "rep_range"
        case recoverySeconds = "recovery_seconds"
    }
    var prescription: String {
        var parts: [String] = []
        if let sets { parts.append("\(sets)") }
        if let repRange, !repRange.isEmpty { parts.append(repRange) }
        else if let reps { parts.append("\(reps)") }
        let core = parts.joined(separator: " × ")
        var extra: [String] = []
        if let rir { extra.append("RIR \(rir)") }
        if let rpe { extra.append("RPE \(rpe)") }
        if let recoverySeconds { extra.append("\(recoverySeconds)s rec") }
        return ([core] + extra).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct CoachWorkoutDayDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let order: Int
    let focus: String?
    let notes: String?
    let exercises: [CoachWorkoutExerciseDTO]
}

struct CoachWorkoutDetailDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let goal: String?
    let level: String?
    let durationWeeks: Int?
    let frequencyPerWeek: Int?
    let planKind: String?
    let description: String?
    let status: String?
    let days: [CoachWorkoutDayDTO]
    enum CodingKeys: String, CodingKey {
        case id, title, goal, level, description, status, days
        case durationWeeks = "duration_weeks"
        case frequencyPerWeek = "frequency_per_week"
        case planKind = "plan_kind"
    }
}

struct CoachWorkoutDetailResponse: Codable { let plan: CoachWorkoutDetailDTO }

// MARK: - Plan detail (nutrition)

struct CoachMacros: Codable, Hashable {
    let kcal: Double
    let protein: Double
    let carb: Double
    let fat: Double
}

struct CoachMealItemDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let quantityG: Double?
    let kcal: Double?
    let protein: Double?
    let carb: Double?
    let fat: Double?
    enum CodingKeys: String, CodingKey {
        case id, name, kcal, protein, carb, fat
        case quantityG = "quantity_g"
    }
}

struct CoachMealDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let order: Int
    let notes: String?
    let items: [CoachMealItemDTO]
}

struct CoachNutritionDetailDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let planMode: String?
    let planKind: String?
    let dailyKcal: Int?
    let description: String?
    let status: String?
    let meals: [CoachMealDTO]
    let totals: CoachMacros
    enum CodingKeys: String, CodingKey {
        case id, title, description, status, meals, totals
        case planMode = "plan_mode"
        case planKind = "plan_kind"
        case dailyKcal = "daily_kcal"
    }
}

struct CoachNutritionDetailResponse: Codable { let plan: CoachNutritionDetailDTO }

// MARK: - Automatic replies

struct CoachAutoMessage: Codable, Identifiable, Hashable {
    let eventType: String
    let label: String
    var body: String
    var isEnabled: Bool
    let attachmentUrl: String?
    var id: String { eventType }
    enum CodingKeys: String, CodingKey {
        case label, body
        case eventType = "event_type"
        case isEnabled = "is_enabled"
        case attachmentUrl = "attachment_url"
    }
}

struct CoachAutoMessagesResponse: Codable { let messages: [CoachAutoMessage] }

// MARK: - New conversation

struct CoachMessageableClient: Codable, Identifiable, Hashable {
    let id: Int
    let displayName: String
    let firstName: String
    let lastName: String
    let profileImageUrl: String?
    let primaryGoal: String?
    let sport: String?
    let hasConversation: Bool

    var initials: String {
        let s = ((firstName.first.map(String.init) ?? "") + (lastName.first.map(String.init) ?? "")).uppercased()
        return s.isEmpty ? "A" : s
    }
    enum CodingKeys: String, CodingKey {
        case id, sport
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageUrl = "profile_image_url"
        case primaryGoal = "primary_goal"
        case hasConversation = "has_conversation"
    }
}

struct CoachMessageableClientsResponse: Codable { let clients: [CoachMessageableClient] }

struct CoachStartConversationResponse: Codable {
    let conversationId: Int
    let messageId: Int
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case messageId = "message_id"
    }
}

struct CoachAppointmentResponse: Codable { let appointment: CoachAgendaItem }

// MARK: - Business analytics + churn risk

/// KPI snapshot. All values optional Doubles (counts decode from JSON ints too)
/// so a not-yet-computed metric renders as a dash rather than failing decode.
struct CoachBusinessKPIs: Codable {
    let activeClientsCount: Double?
    let atRiskClientsCount: Double?
    let renewalsDue7d: Double?
    let churnRate30d: Double?
    let monthlyRevenue: Double?
    let revenuePerActiveClient: Double?
    let slaAdherenceRate: Double?
    let backlogOpenReviews: Double?

    enum CodingKeys: String, CodingKey {
        case activeClientsCount = "active_clients_count"
        case atRiskClientsCount = "at_risk_clients_count"
        case renewalsDue7d = "renewals_due_7d"
        case churnRate30d = "churn_rate_30d"
        case monthlyRevenue = "monthly_revenue"
        case revenuePerActiveClient = "revenue_per_active_client"
        case slaAdherenceRate = "sla_adherence_rate"
        case backlogOpenReviews = "backlog_open_reviews"
    }
}

struct CoachMetricPoint: Codable, Identifiable {
    var id: String { snapshotDate }
    let snapshotDate: String
    let atRiskClientsCount: Int
    let avgRiskScore: Double

    enum CodingKeys: String, CodingKey {
        case snapshotDate = "snapshot_date"
        case atRiskClientsCount = "at_risk_clients_count"
        case avgRiskScore = "avg_risk_score"
    }
}

struct CoachBusinessDTO: Codable {
    let snapshotDate: String?
    let kpis: CoachBusinessKPIs
    let series: [CoachMetricPoint]
    enum CodingKeys: String, CodingKey {
        case snapshotDate = "snapshot_date"
        case kpis, series
    }
}

struct CoachRiskReason: Codable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let label: String
}

struct CoachRiskClient: Codable, Identifiable {
    let id: Int
    let displayName: String
    let profileImageUrl: String?
    let riskScore: Int
    let riskClass: String
    let riskProbabilityMl: Double?
    let reasons: [CoachRiskReason]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case profileImageUrl = "profile_image_url"
        case riskScore = "risk_score"
        case riskClass = "risk_class"
        case riskProbabilityMl = "risk_probability_ml"
        case reasons
    }
}

struct CoachRiskResponse: Codable {
    let snapshotDate: String?
    let clients: [CoachRiskClient]
    enum CodingKeys: String, CodingKey {
        case snapshotDate = "snapshot_date"
        case clients
    }
}
