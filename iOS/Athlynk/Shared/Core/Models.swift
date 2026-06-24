//
//  Models.swift
//  Codable DTOs mirroring the Django /api/v1 JSON shapes.
//

import Foundation

struct AuthUser: Codable, Identifiable, Hashable {
    let id: Int
    let email: String
    let role: String
    let firstName: String
    let lastName: String
    let displayName: String
    /// Optional for back-compat with servers that predate the field.
    let chironSeen: Bool?

    var isClient: Bool { role.uppercased() == "CLIENT" }
    /// First-login mascot tutorial should run only for clients who haven't met Chiron.
    var needsChironIntro: Bool { isClient && (chironSeen != true) }

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case chironSeen = "chiron_seen"
    }
}

struct LoginResponse: Codable {
    let token: String
    let user: AuthUser
}

struct Coach: Codable, Identifiable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let professionalType: String?
    let specialization: String?
    let city: String?
    let profileImageUrl: String?

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    enum CodingKeys: String, CodingKey {
        case id, city
        case firstName = "first_name"
        case lastName = "last_name"
        case professionalType = "professional_type"
        case specialization
        case profileImageUrl = "profile_image_url"
    }
}

struct MeProfile: Codable {
    let imageUrl: String?
    enum CodingKeys: String, CodingKey {
        case imageUrl = "profile_image_url"
    }
}

struct MeResponse: Codable {
    let user: AuthUser
    let coach: Coach?
    let trainer: Coach?
    let nutritionist: Coach?
    let profile: MeProfile?
}

// MARK: - Workouts

struct ExerciseDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let videoUrl: String?
    let targetMuscleGroup: String?
    let equipment: String?
    let orderIndex: Int
    let setCount: Int?
    let repCount: Int?
    let repRange: String?
    let rir: Int?
    let rpe: Int?
    let loadValue: Double?
    let loadUnit: String?
    let recoverySeconds: Int?
    let tempo: String?
    let techniqueNotes: String?
    let supersetGroupId: Int?

    var setsReps: String {
        let s = setCount.map { "\($0)" } ?? "—"
        let r = repRange ?? repCount.map { "\($0)" } ?? "—"
        return "\(s)×\(r)"
    }
    var loadLabel: String? {
        guard let v = loadValue else { return nil }
        let n = v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
        switch loadUnit {
        case "PERCENT_1RM": return "\(n)% 1RM"
        case "BODYWEIGHT": return "BW"
        default: return "\(n) kg"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, equipment, tempo, rir, rpe
        case videoUrl = "video_url"
        case targetMuscleGroup = "target_muscle_group"
        case orderIndex = "order_index"
        case setCount = "set_count"
        case repCount = "rep_count"
        case repRange = "rep_range"
        case loadValue = "load_value"
        case loadUnit = "load_unit"
        case recoverySeconds = "recovery_seconds"
        case techniqueNotes = "technique_notes"
        case supersetGroupId = "superset_group_id"
    }
}

struct WorkoutDayDTO: Codable, Identifiable, Hashable {
    let id: Int
    let dayOrder: Int
    let dayName: String?
    let title: String?
    let focusArea: String?
    let dayType: String?
    let notes: String?
    let exercises: [ExerciseDTO]

    var label: String { title ?? dayName ?? "Day \(dayOrder)" }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, exercises
        case dayOrder = "day_order"
        case dayName = "day_name"
        case focusArea = "focus_area"
        case dayType = "day_type"
    }
}

struct WorkoutDaySelection: Hashable {
    let day: WorkoutDayDTO
    let assignmentId: Int
}

struct WorkoutPlanDTO: Codable, Identifiable, Hashable {
    let assignmentId: Int
    let planId: Int
    let title: String
    let description: String?
    let goal: String?
    let level: String?
    let frequencyPerWeek: Int?
    let durationWeeks: Int?
    let startDate: String?
    let coach: Coach?
    let days: [WorkoutDayDTO]

    var id: Int { assignmentId }

    enum CodingKeys: String, CodingKey {
        case title, description, goal, level, coach, days
        case assignmentId = "assignment_id"
        case planId = "plan_id"
        case frequencyPerWeek = "frequency_per_week"
        case durationWeeks = "duration_weeks"
        case startDate = "start_date"
    }
}

struct WorkoutsResponse: Codable { let plans: [WorkoutPlanDTO] }

// MARK: - Nutrition

struct MealItemDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let quantityG: Double
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    enum CodingKeys: String, CodingKey {
        case id, name, kcal, protein, carbs, fat
        case quantityG = "quantity_g"
    }
}

struct MealDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let timeOfDay: String?
    let items: [MealItemDTO]

    var kcal: Double { items.reduce(0) { $0 + $1.kcal } }

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case timeOfDay = "time_of_day"
    }
}

struct DietDayDTO: Codable, Identifiable, Hashable {
    let id: Int
    let dayOfWeek: String
    let targetKcal: Int?
    let targetProteinG: Int?
    let targetCarbG: Int?
    let targetFatG: Int?
    let meals: [MealDTO]

    enum CodingKeys: String, CodingKey {
        case id, meals
        case dayOfWeek = "day_of_week"
        case targetKcal = "target_kcal"
        case targetProteinG = "target_protein_g"
        case targetCarbG = "target_carb_g"
        case targetFatG = "target_fat_g"
    }
}

struct NutritionPlanDTO: Codable, Identifiable, Hashable {
    let assignmentId: Int
    let planId: Int
    let title: String
    let planMode: String
    let planKind: String
    let nutritionGoal: String?
    let dailyKcal: Int?
    let proteinTargetG: Int?
    let carbTargetG: Int?
    let fatTargetG: Int?
    let coach: Coach?
    let days: [DietDayDTO]

    var id: Int { assignmentId }

    enum CodingKeys: String, CodingKey {
        case title, coach, days
        case assignmentId = "assignment_id"
        case planId = "plan_id"
        case planMode = "plan_mode"
        case planKind = "plan_kind"
        case nutritionGoal = "nutrition_goal"
        case dailyKcal = "daily_kcal"
        case proteinTargetG = "protein_target_g"
        case carbTargetG = "carb_target_g"
        case fatTargetG = "fat_target_g"
    }
}

struct NutritionResponse: Codable { let plans: [NutritionPlanDTO] }

// MARK: - Checks / Notifications / Chat

/// One section of a multi-step check.
struct CheckStep: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}

/// One selectable anthropometry measure (circonferenza / plica). `key` is the
/// stored key (with `_l`/`_r` for limbs); `label` is the resolved ISAK name.
struct AntroItem: Codable, Identifiable, Hashable {
    let key: String
    let label: String
    var id: String { key }
}

/// A single question the athlete must answer. `type` mirrors the web builder:
/// antropometria | metrica | media | si_no | radio | checkbox | aperta | allegato.
struct CheckQuestion: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let label: String
    let required: Bool
    let unit: String?
    let options: [String]
    let min: Double?
    let max: Double?
    let minLabel: String?
    let maxLabel: String?
    let placeholder: String?
    let stepId: String?
    // antropometria-only
    let weight: Bool
    let circumferences: [AntroItem]
    let skinfolds: [AntroItem]

    enum CodingKeys: String, CodingKey {
        case id, type, label, required, unit, options, min, max
        case minLabel = "min_label"
        case maxLabel = "max_label"
        case placeholder
        case stepId = "step_id"
        case weight, circumferences, skinfolds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = (try? c.decode(String.self, forKey: .type)) ?? "aperta"
        label = (try? c.decode(String.self, forKey: .label)) ?? id
        required = (try? c.decode(Bool.self, forKey: .required)) ?? false
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        options = (try? c.decode([String].self, forKey: .options)) ?? []
        min = try? c.decodeIfPresent(Double.self, forKey: .min)
        max = try? c.decodeIfPresent(Double.self, forKey: .max)
        minLabel = try? c.decodeIfPresent(String.self, forKey: .minLabel)
        maxLabel = try? c.decodeIfPresent(String.self, forKey: .maxLabel)
        placeholder = try? c.decodeIfPresent(String.self, forKey: .placeholder)
        stepId = try? c.decodeIfPresent(String.self, forKey: .stepId)
        weight = (try? c.decode(Bool.self, forKey: .weight)) ?? true
        circumferences = (try? c.decode([AntroItem].self, forKey: .circumferences)) ?? []
        skinfolds = (try? c.decode([AntroItem].self, forKey: .skinfolds)) ?? []
    }
}

struct CheckDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let dueDate: String?
    let expiresAt: String?
    let coach: Coach?
    let steps: [CheckStep]
    let questions: [CheckQuestion]

    enum CodingKeys: String, CodingKey {
        case id, title, coach, steps, questions
        case dueDate = "due_date"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        dueDate = try? c.decodeIfPresent(String.self, forKey: .dueDate)
        expiresAt = try? c.decodeIfPresent(String.self, forKey: .expiresAt)
        coach = try? c.decodeIfPresent(Coach.self, forKey: .coach)
        steps = (try? c.decode([CheckStep].self, forKey: .steps)) ?? []
        questions = (try? c.decode([CheckQuestion].self, forKey: .questions)) ?? []
    }
}

struct ChecksResponse: Codable { let pending: [CheckDTO] }

struct NotificationDTO: Codable, Identifiable, Hashable {
    let id: Int
    let type: String
    let title: String
    let body: String?
    let isRead: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, body
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

struct NotificationsResponse: Codable {
    let notifications: [NotificationDTO]
    let hasMore: Bool?
    enum CodingKeys: String, CodingKey { case notifications; case hasMore = "has_more" }
}

struct ConversationDTO: Codable, Identifiable, Hashable {
    let id: Int
    let coach: Coach?
    let lastMessage: String?
    let lastMessageAt: String?

    enum CodingKeys: String, CodingKey {
        case id, coach
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
    }
}

struct ConversationsResponse: Codable { let conversations: [ConversationDTO] }

struct MessageDTO: Codable, Identifiable, Hashable {
    let id: Int
    let body: String
    let messageType: String
    let isMine: Bool
    let sentAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case messageType = "message_type"
        case isMine = "is_mine"
        case sentAt = "sent_at"
    }
}

struct MessagesResponse: Codable {
    let messages: [MessageDTO]
    let hasMore: Bool?
    enum CodingKeys: String, CodingKey { case messages; case hasMore = "has_more" }
}

// MARK: - Subscription (Il Mio Abbonamento)

struct SubscriptionPlanDTO: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let planType: String?
    let description: String?
    let price: Double
    let currency: String
    let durationDays: Int?
    let billingInterval: String?
    let includedServices: [String]
    let coach: Coach?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, currency, coach
        case planType = "plan_type"
        case durationDays = "duration_days"
        case billingInterval = "billing_interval"
        case includedServices = "included_services"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        planType = try c.decodeIfPresent(String.self, forKey: .planType)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        price = (try? c.decode(Double.self, forKey: .price)) ?? 0
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "EUR"
        durationDays = try c.decodeIfPresent(Int.self, forKey: .durationDays)
        billingInterval = try c.decodeIfPresent(String.self, forKey: .billingInterval)
        // included_services is a free-form JSON field: tolerate non-string arrays.
        includedServices = (try? c.decode([String].self, forKey: .includedServices)) ?? []
        coach = try c.decodeIfPresent(Coach.self, forKey: .coach)
    }
}

struct SubscriptionDTO: Codable, Hashable {
    let id: Int
    let status: String
    let paymentStatus: String?
    let startDate: String?
    let endDate: String?
    let autoRenew: Bool
    let plan: SubscriptionPlanDTO

    enum CodingKeys: String, CodingKey {
        case id, status, plan
        case paymentStatus = "payment_status"
        case startDate = "start_date"
        case endDate = "end_date"
        case autoRenew = "auto_renew"
    }
}

struct SubscriptionResponse: Codable { let subscription: SubscriptionDTO? }

// MARK: - Appointments (Agenda)

struct AppointmentDTO: Codable, Identifiable, Hashable {
    let id: Int
    let type: String?
    let title: String
    let description: String?
    let start: String?
    let end: String?
    let durationMinutes: Int?
    let location: String?
    let meetingUrl: String?
    let status: String?
    let coach: Coach?

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, start, end, location, status, coach
        case durationMinutes = "duration_minutes"
        case meetingUrl = "meeting_url"
    }
}

struct AppointmentsResponse: Codable { let appointments: [AppointmentDTO] }

// MARK: - Progress (check history)

struct ProgressPhotoDTO: Codable, Identifiable, Hashable {
    let id: Int
    let url: String
    let type: String?
    let capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, url, type
        case capturedAt = "captured_at"
    }
}

struct ProgressEntryDTO: Codable, Identifiable, Hashable {
    let id: Int
    let submittedAt: String?
    let weightKg: Double?
    /// Body circumferences in cm, keyed by site (waist, chest, …). Server sends
    /// values as strings ("85.0"); empty sites are omitted.
    let measurements: [String: String]?
    /// Skinfolds in mm, keyed by site (chest, abdomen, …). Same string encoding.
    let skinfolds: [String: String]?
    let coachFeedback: String?
    let notes: String?
    let photos: [ProgressPhotoDTO]

    enum CodingKeys: String, CodingKey {
        case id, notes, photos, measurements, skinfolds
        case submittedAt = "submitted_at"
        case weightKg = "weight_kg"
        case coachFeedback = "coach_feedback"
    }
}

struct ProgressResponse: Codable { let entries: [ProgressEntryDTO] }

// MARK: - Single measurement catalog ("pesata/circonferenza/plica del giorno X")

/// One selectable measurement site (e.g. "waist" → "Vita"). Limb circumferences
/// expose the two sides as separate options (key suffixed `_l` / `_r`).
struct MeasurementOption: Codable, Identifiable, Hashable {
    let key: String
    let label: String
    var id: String { key }
}

struct MeasurementCatalog: Codable {
    let circumferences: [MeasurementOption]
    let skinfolds: [MeasurementOption]
}

// MARK: - Exercise trend (per-session over time) — shared by athlete & coach

struct ExerciseTrendDTO: Codable {
    struct Meta: Codable { let name: String; let loadUnit: String
        enum CodingKeys: String, CodingKey { case name; case loadUnit = "load_unit" } }
    let exercise: Meta
    let hasData: Bool
    let sessions: [TrendSessionDTO]
    enum CodingKeys: String, CodingKey { case exercise, sessions; case hasData = "has_data" }
}

struct TrendSessionDTO: Codable, Identifiable {
    let sessionId: Int
    let date: String?
    let avgRpe: Double?
    let volume: Double?
    let topSet: Double?
    let weightedAvgLoad: Double?
    let loadUnit: String?
    let sets: [TrendSetDTO]
    var id: Int { sessionId }
    enum CodingKeys: String, CodingKey {
        case date, volume, sets
        case sessionId = "session_id"
        case avgRpe = "avg_rpe"
        case topSet = "top_set"
        case weightedAvgLoad = "weighted_avg_load"
        case loadUnit = "load_unit"
    }
}

struct TrendSetDTO: Codable, Identifiable {
    let setNumber: Int
    let reps: Int?
    let load: Double?
    let rpe: Double?
    let isExtra: Bool?
    let actualExercise: String?
    var id: Int { setNumber }
    enum CodingKeys: String, CodingKey {
        case reps, load, rpe
        case setNumber = "set_number"
        case isExtra = "is_extra"
        case actualExercise = "actual_exercise"
    }
}

// MARK: - Editable profile

struct ClientProfileDTO: Codable, Hashable {
    let firstName: String
    let lastName: String
    let phone: String?
    let weightKg: Double?
    let sport: String?
    let gender: String?
    let birthDate: String?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case phone, gender, sport
        case firstName = "first_name"
        case lastName = "last_name"
        case weightKg = "weight_kg"
        case birthDate = "birth_date"
        case imageUrl = "profile_image_url"
    }
}

struct ProfilePhotoResponse: Codable {
    let imageUrl: String
    enum CodingKeys: String, CodingKey { case imageUrl = "profile_image_url" }
}

// MARK: - MACRO-mode food logging

struct FoodDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String?
    let kcal: Double      // per 100 g
    let protein: Double
    let carb: Double
    let fat: Double
}

struct MacroMacrosDTO: Codable, Hashable {
    let kcal: Double
    let protein: Double
    let carb: Double
    let fat: Double
}

struct MacroEntryDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let mealName: String
    let quantityG: Double
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    enum CodingKeys: String, CodingKey {
        case id, name, kcal, protein, carbs, fat
        case mealName = "meal_name"
        case quantityG = "quantity_g"
    }
}

struct MacroDayDTO: Codable, Hashable {
    let date: String
    let target: MacroMacrosDTO
    let consumed: MacroMacrosDTO
    let entries: [MacroEntryDTO]
}

struct FoodSearchResponse: Codable { let results: [FoodDTO] }
struct MacroDayResponse: Codable { let macroDay: MacroDayDTO
    enum CodingKeys: String, CodingKey { case macroDay = "macro_day" } }

/// One past day of the athlete's compiled meal log.
struct MacroHistoryDayDTO: Codable, Identifiable, Hashable {
    let date: String          // ISO yyyy-MM-dd — stable id
    let dowShort: String      // LUN…DOM
    let target: MacroMacrosDTO
    let consumed: MacroMacrosDTO
    let entries: [MacroEntryDTO]

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, target, consumed, entries
        case dowShort = "dow_short"
    }
}

struct MacroHistoryResponse: Codable {
    let days: [MacroHistoryDayDTO]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case days; case hasMore = "has_more" }
}

// MARK: - "Il mio percorso" timeline

struct JourneyEventDTO: Codable, Identifiable, Hashable {
    let id: String
    let type: String          // allenamento | nutrizione | check
    let date: String          // ISO yyyy-MM-dd
    let title: String
    let subtitle: String?
    let statusLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, type, date, title, subtitle
        case statusLabel = "status_label"
    }
}

struct JourneyPhaseDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let note: String
    let start: String          // ISO yyyy-MM-dd
    let end: String            // ISO yyyy-MM-dd
    let durationValue: Int
    let durationUnit: String   // WEEKS | MONTHS

    enum CodingKeys: String, CodingKey {
        case id, title, note, start, end
        case durationValue = "duration_value"
        case durationUnit = "duration_unit"
    }
}

struct JourneyResponse: Codable {
    let events: [JourneyEventDTO]
    let phases: [JourneyPhaseDTO]

    enum CodingKeys: String, CodingKey { case events, phases }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([JourneyEventDTO].self, forKey: .events) ?? []
        phases = try c.decodeIfPresent([JourneyPhaseDTO].self, forKey: .phases) ?? []
    }
}

struct ProfileResponse: Codable { let profile: ClientProfileDTO }

// MARK: - Workout history (Storico Allenamenti)

struct WorkoutSessionDTO: Codable, Identifiable, Hashable {
    let id: Int
    let dayLabel: String
    let focusArea: String?
    let startedAt: String?
    let endedAt: String?
    let durationMinutes: Int?
    let avgRpe: Double?
    let completed: Bool
    let interrupted: Bool
    let setCount: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, completed, interrupted, notes
        case dayLabel = "day_label"
        case focusArea = "focus_area"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMinutes = "duration_minutes"
        case avgRpe = "avg_rpe"
        case setCount = "set_count"
    }
}

struct WorkoutHistoryResponse: Codable {
    let sessions: [WorkoutSessionDTO]
    let hasMore: Bool?
    enum CodingKeys: String, CodingKey { case sessions; case hasMore = "has_more" }
}

// MARK: - Past session detail (athlete + coach share these via _serialize_session_*)

/// Brief row for the coach's per-client session history list.
struct SessionBriefDTO: Codable, Identifiable, Hashable {
    let id: Int
    let dayName: String?
    let startedAt: String?
    let durationMinutes: Int?
    let avgRpe: Double?
    let completed: Bool
    let interrupted: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, completed, interrupted, notes
        case dayName = "day_name"
        case startedAt = "started_at"
        case durationMinutes = "duration_minutes"
        case avgRpe = "avg_rpe"
    }
}

struct SessionBriefListDTO: Codable {
    let sessions: [SessionBriefDTO]
    let hasMore: Bool?
    enum CodingKeys: String, CodingKey { case sessions; case hasMore = "has_more" }
}

struct LoggedSetDetailDTO: Codable, Identifiable, Hashable {
    let setNumber: Int
    let repsDone: Int?
    let loadUsed: Double?
    let loadUnit: String?
    let rpe: Int?
    let completed: Bool
    var id: Int { setNumber }

    enum CodingKeys: String, CodingKey {
        case rpe, completed
        case setNumber = "set_number"
        case repsDone = "reps_done"
        case loadUsed = "load_used"
        case loadUnit = "load_unit"
    }
}

struct SessionLoggedExerciseDTO: Codable, Identifiable, Hashable {
    let workoutExerciseId: Int
    let exerciseName: String
    let exerciseNote: String?
    let prescribedReps: String?
    let sets: [LoggedSetDetailDTO]
    var id: Int { workoutExerciseId }

    enum CodingKeys: String, CodingKey {
        case sets
        case workoutExerciseId = "workout_exercise_id"
        case exerciseName = "exercise_name"
        case exerciseNote = "exercise_note"
        case prescribedReps = "prescribed_reps"
    }
}

struct SessionDetailDTO: Codable, Identifiable {
    let id: Int
    let dayName: String?
    let startedAt: String?
    let durationMinutes: Int?
    let avgRpe: Double?
    let completed: Bool
    let interrupted: Bool
    let notes: String?
    let exercises: [SessionLoggedExerciseDTO]

    enum CodingKeys: String, CodingKey {
        case id, completed, interrupted, notes, exercises
        case dayName = "day_name"
        case startedAt = "started_at"
        case durationMinutes = "duration_minutes"
        case avgRpe = "avg_rpe"
    }
}

// MARK: - Supplements (Integratori)

struct SupplementItemDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String?
    let unit: String?
    let dose: String
    let timing: String?
    let notes: String?
}

struct SupplementSheetDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let notes: String?
    let coach: Coach?
    let items: [SupplementItemDTO]
}

struct SupplementsResponse: Codable { let sheets: [SupplementSheetDTO] }

// MARK: - Coach detail (Profilo Coach)

struct CoachDetailDTO: Codable, Identifiable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let professionalType: String?
    let specialization: String?
    let city: String?
    let profileImageUrl: String?
    let bio: String?
    let description: String?
    let certifications: String?
    let yearsExperience: Int?
    let socialInstagram: String?
    let socialYoutube: String?
    let socialWebsite: String?

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    enum CodingKeys: String, CodingKey {
        case id, city, bio, description, certifications
        case firstName = "first_name"
        case lastName = "last_name"
        case professionalType = "professional_type"
        case specialization
        case profileImageUrl = "profile_image_url"
        case yearsExperience = "years_experience"
        case socialInstagram = "social_instagram"
        case socialYoutube = "social_youtube"
        case socialWebsite = "social_website"
    }
}

struct CoachDetailResponse: Codable { let coach: CoachDetailDTO }

// MARK: - Settings (Impostazioni)

struct SettingToggleDTO: Codable, Identifiable, Hashable {
    let key: String
    let label: String
    let desc: String
    let enabled: Bool
    var id: String { key }
}

struct SettingsDTO: Codable, Hashable {
    let email: String
    let notifications: [SettingToggleDTO]
}

struct SettingsResponse: Codable { let settings: SettingsDTO }

// MARK: - Plans on offer (Piani e Prezzi)

struct PlansResponse: Codable { let plans: [SubscriptionPlanDTO] }

// MARK: - Active session (Sessione Attiva)

struct SessionExerciseDTO: Codable, Identifiable, Hashable {
    let workoutExerciseId: Int
    let name: String
    let targetMuscleGroup: String?
    let sets: Int
    let reps: String
    let loadValue: Double?
    let loadUnit: String?
    let recoverySeconds: Int?
    let tempo: String?
    let notes: String?

    var id: Int { workoutExerciseId }

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, notes, tempo
        case workoutExerciseId = "workout_exercise_id"
        case targetMuscleGroup = "target_muscle_group"
        case loadValue = "load_value"
        case loadUnit = "load_unit"
        case recoverySeconds = "recovery_seconds"
    }
}

struct LoggedSetDTO: Codable, Hashable {
    let workoutExerciseId: Int
    let setNumber: Int
    let repsDone: Int?
    let loadUsed: Double?
    let loadUnit: String?
    let rpe: Int?
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case rpe, completed
        case workoutExerciseId = "workout_exercise_id"
        case setNumber = "set_number"
        case repsDone = "reps_done"
        case loadUsed = "load_used"
        case loadUnit = "load_unit"
    }
}

struct SessionStartDTO: Codable {
    let sessionId: Int
    let exercises: [SessionExerciseDTO]
    let setsLogged: [LoggedSetDTO]
    let startedAt: String?

    enum CodingKeys: String, CodingKey {
        case exercises
        case sessionId = "session_id"
        case setsLogged = "sets_logged"
        case startedAt = "started_at"
    }
}

// MARK: - Anamnesis (Questionario Anamnesi, read-only)

struct AnamnesisDTO: Codable, Hashable {
    let id: Int
    let date: String?
    let age: Int?
    let weightKg: Double?
    let heightCm: Double?
    let medicalHistory: String?
    let medications: String?
    let injuries: String?
    let allergies: String?
    let intolerances: String?
    let lifestyleNotes: String?
    let sleepQuality: String?
    let stressLevel: String?
    let foodHabits: String?
    let weightHistory: String?
    let pathGoal: String?
    let coach: Coach?

    enum CodingKeys: String, CodingKey {
        case id, date, age, medications, injuries, allergies, intolerances, coach
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case medicalHistory = "medical_history"
        case lifestyleNotes = "lifestyle_notes"
        case sleepQuality = "sleep_quality"
        case stressLevel = "stress_level"
        case foodHabits = "food_habits"
        case weightHistory = "weight_history"
        case pathGoal = "path_goal"
    }
}

struct AnamnesisResponse: Codable { let anamnesis: AnamnesisDTO? }

struct PrimaValutazioneDTO: Codable {
    let submittedAt: String?
    let data: DataPayload?

    struct DataPayload: Codable {
        let storia: Storia?
        let antropometria: Antropometria?
        let allenamento: Allenamento?
        let fabbisogni: Fabbisogni?
        let obiettivi: Obiettivi?
    }

    struct Storia: Codable {
        let patologie: String?
        let allergie: String?
        let interventi: String?
        let familiarita: String?
        let farmaci: String?
        let professionistiSeguiti: [String]?
        enum CodingKeys: String, CodingKey {
            case patologie, allergie, interventi, familiarita, farmaci
            case professionistiSeguiti = "professionisti_seguiti"
        }
    }

    struct Antropometria: Codable {
        let altezzaCm: Double?
        let pesoKg: Double?
        let pesoAbitualeKg: Double?
        enum CodingKeys: String, CodingKey {
            case altezzaCm = "altezza_cm"
            case pesoKg = "peso_kg"
            case pesoAbitualeKg = "peso_abituale_kg"
        }
    }

    struct Allenamento: Codable {
        let discipline: [String]?
        let anniEsperienza: Int?
        let seduteSettimana: Int?
        let durataMedMin: Int?
        enum CodingKeys: String, CodingKey {
            case discipline
            case anniEsperienza = "anni_esperienza"
            case seduteSettimana = "sedute_settimana"
            case durataMedMin = "durata_media_min"
        }
    }

    struct Fabbisogni: Codable {
        let detKcal: Int?
        let proteineG: Int?
        let carboidratiG: Int?
        let lipidiG: Int?
        let fibraG: Int?
        let idricoMl: Int?
        enum CodingKeys: String, CodingKey {
            case detKcal = "det_kcal"
            case proteineG = "proteine_g"
            case carboidratiG = "carboidrati_g"
            case lipidiG = "lipidi_g"
            case fibraG = "fibra_g"
            case idricoMl = "idrico_ml"
        }
    }

    struct Obiettivi: Codable {
        let obiettivoPrincipale: String?
        let motivazione: String?
        let scadenza: String?
        enum CodingKeys: String, CodingKey {
            case obiettivoPrincipale = "obiettivo_principale"
            case motivazione, scadenza
        }
    }

    enum CodingKeys: String, CodingKey {
        case submittedAt = "submitted_at"
        case data
    }

    var hasData: Bool { submittedAt != nil && data != nil }
}
