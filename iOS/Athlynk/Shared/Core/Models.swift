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
    /// Whether the user has accepted Terms of Service + Privacy Policy.
    /// Optional for back-compat; nil is treated as "already accepted" so older
    /// servers don't trap users behind the consent gate.
    let termsAccepted: Bool?

    var isClient: Bool { role.uppercased() == "CLIENT" }
    /// First-login mascot tutorial should run only for clients who haven't met Chiron.
    var needsChironIntro: Bool { isClient && (chironSeen != true) }
    /// Gate the app until the user has consented, but only when the server
    /// actually told us they haven't (false) — never on a missing field.
    var needsTermsConsent: Bool { termsAccepted == false }

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case chironSeen = "chiron_seen"
        case termsAccepted = "terms_accepted"
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
    let brandPrimary: String?
    let brandAccent: String?
    enum CodingKeys: String, CodingKey {
        case imageUrl = "profile_image_url"
        case brandPrimary = "brand_primary"
        case brandAccent = "brand_accent"
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

/// Athlete-facing exercise shape. Coach counterpart: `CoachWorkoutExerciseDTO`
/// (AthlynkCoach/Core/CoachModels.swift) — same backend resource, kept separate
/// because the coach payload carries editing-only fields. Keep field names in sync.
struct ExerciseDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let videoUrl: String?
    let targetMuscleGroup: String?
    let equipment: [String]
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
    /// Catalog media/detail (exercises-dataset sourcing) — the coach's own
    /// note (`techniqueNotes`) is per-prescription and separate from these.
    let demoGifUrl: String?
    let coverImageUrl: String?
    let description: String?
    let instructionSteps: [String]?
    let muscleDetail: String?

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
    /// Single execution text. Prefer `instruction_steps`; fall back to splitting
    /// the legacy `description` prose for any not-yet-migrated exercise.
    var executionSteps: [String]? {
        if let s = instructionSteps, !s.isEmpty { return s }
        guard let d = description, !d.isEmpty else { return nil }
        let byLine = d.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if byLine.count > 1 { return byLine }
        return d.split(whereSeparator: { ".!?".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, equipment, tempo, rir, rpe, description
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
        case demoGifUrl = "demo_gif"
        case coverImageUrl = "cover_image"
        case instructionSteps = "instruction_steps"
        case muscleDetail = "muscle_detail"
    }
}

/// Athlete-facing workout day shape. Coach counterpart: `CoachWorkoutDayDTO`
/// (AthlynkCoach/Core/CoachModels.swift). Keep field names in sync.
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

/// Athlete-facing workout plan shape. Coach counterpart: `CoachWorkoutDetailDTO`
/// (AthlynkCoach/Core/CoachModels.swift). Keep field names in sync.
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

/// Athlete-facing meal item shape, backed by `config/api.py`'s athlete nutrition
/// endpoints (JSON key `carbs`, plural). Coach counterpart: `CoachMealItemDTO`
/// (AthlynkCoach/Core/CoachModels.swift) is backed by a *different* endpoint
/// (`config/api_coach.py`'s `_food_macros()`, JSON key `carb`, singular) — the
/// key mismatch is real but each DTO is correct for its own endpoint. Don't
/// "fix" one to match the other without changing the backend serializer too.
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

/// Athlete-facing meal shape. Coach counterpart: `CoachMealDTO`
/// (AthlynkCoach/Core/CoachModels.swift). Keep field names in sync.
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

    /// Plan-level overview targets (matches the web app's plan summary card,
    /// not a single day). MACRO plans don't set a plan-level daily_kcal/macro
    /// — those live per-day, so fall back to the week's average, same as the
    /// web dashboard's `_plan_macro_targets(plan)['avg']` for MACRO plans.
    var overviewTargets: (kcal: Int, protein: Int?, carb: Int?, fat: Int?) {
        if let k = dailyKcal, k > 0 { return (k, proteinTargetG, carbTargetG, fatTargetG) }
        if planMode == "MACRO" {
            func avg(_ f: (DietDayDTO) -> Int?) -> Int? {
                let vals = days.compactMap(f)
                return vals.isEmpty ? nil : vals.reduce(0, +) / vals.count
            }
            return (avg { $0.targetKcal } ?? 0, avg { $0.targetProteinG }, avg { $0.targetCarbG }, avg { $0.targetFatG })
        }
        let kcal = Int((days.first?.meals.reduce(0) { $0 + $1.kcal }) ?? 0)
        return (kcal, proteinTargetG, carbTargetG, fatTargetG)
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

// MARK: - Check detail (storico) — GET /api/v1/checks/<id>
// Mirrors WebApp check/detail.html's server-computed sections, so the athlete
// reads back exactly what the coach sees, including read-only tool summaries
// (e.g. Calcolo Fabbisogni) they never fill in themselves.

/// A scalar answer value of unknown shape (numbers stay numbers so "80" vs
/// "80.5" render as sent; anything else is text).
enum CheckValue: Codable, Hashable {
    case number(Double), text(String), none

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .none }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .text(let s): try c.encode(s)
        case .none: try c.encodeNil()
        }
    }
    var display: String? {
        switch self {
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .text(let s): return s.isEmpty ? nil : s
        case .none: return nil
        }
    }
}

struct CheckAttachmentFile: Codable, Identifiable, Hashable {
    let id: Int
    let url: String
    let fileName: String
    let mimeType: String?
    enum CodingKeys: String, CodingKey { case id, url; case fileName = "file_name"; case mimeType = "mime_type" }
}

/// One side (DX/SX) of a paired limb measurement (e.g. bicep circumference).
struct CheckMeasureSide: Codable, Hashable {
    let label: String
    let unit: String?
    let value: CheckValue?
    let previous: CheckValue?
    let delta: Double?
    let tag: String?
}

struct CheckFabbisogniMacro: Codable, Hashable {
    let label: String
    let gkg: CheckValue?
    let g: Int?
    let kcal: Int?
    let note: CheckValue?
}

/// Read-only summary of the coach-only «Calcolo Fabbisogni» tool.
struct CheckFabbisogni: Codable, Hashable {
    let altezza: CheckValue?
    let peso: CheckValue?
    let eta: CheckValue?
    let sesso: CheckValue?
    let formula: CheckValue?
    let mb: Int?
    let pal: CheckValue?
    let palDesc: CheckValue?
    let detBase: Int?
    let detAdjust: Int
    let detFinale: Int?
    let detNote: CheckValue?
    let macros: [CheckFabbisogniMacro]
    let fibra: CheckValue?
    let fibraNote: CheckValue?
    let idrico: CheckValue?
    let idricoNote: CheckValue?
    let micro: CheckValue?
    let noteOp: CheckValue?

    enum CodingKeys: String, CodingKey {
        case altezza, peso, eta, sesso, formula, mb, pal, macros, fibra, idrico, micro
        case palDesc = "pal_desc"
        case detBase = "det_base"
        case detAdjust = "det_adjust"
        case detFinale = "det_finale"
        case detNote = "det_note"
        case fibraNote = "fibra_note"
        case idricoNote = "idrico_note"
        case noteOp = "note_op"
    }
}

/// One rendered question inside a check-history section. Fields beyond
/// `id`/`type`/`label` are populated depending on `type`: `strumento_fabbisogni`
/// uses `fb`, `metrica_pair` uses `sides`, `allegato` uses `files`, everything
/// else uses `value`/`previous`/`delta`.
struct CheckSectionQuestion: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let label: String
    let unit: String?
    let value: CheckValue?
    let previous: CheckValue?
    let delta: Double?
    let files: [CheckAttachmentFile]?
    let sides: [CheckMeasureSide]?
    let fb: CheckFabbisogni?

    enum CodingKeys: String, CodingKey { case id, type, label, unit, value, previous, delta, files, sides, fb }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        type = (try? c.decode(String.self, forKey: .type)) ?? "aperta"
        label = (try? c.decode(String.self, forKey: .label)) ?? id
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        value = try? c.decodeIfPresent(CheckValue.self, forKey: .value)
        previous = try? c.decodeIfPresent(CheckValue.self, forKey: .previous)
        delta = try? c.decodeIfPresent(Double.self, forKey: .delta)
        files = try? c.decodeIfPresent([CheckAttachmentFile].self, forKey: .files)
        sides = try? c.decodeIfPresent([CheckMeasureSide].self, forKey: .sides)
        fb = try? c.decodeIfPresent(CheckFabbisogni.self, forKey: .fb)
    }
}

struct CheckSection: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String?
    let questions: [CheckSectionQuestion]

    enum CodingKeys: String, CodingKey { case id, label, icon, questions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? "Sezione"
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        questions = (try? c.decode([CheckSectionQuestion].self, forKey: .questions)) ?? []
    }
}

struct CheckDetailPhoto: Codable, Identifiable, Hashable {
    let id: Int
    let url: String
    let type: String?
    let capturedAt: String?
    enum CodingKeys: String, CodingKey { case id, url, type; case capturedAt = "captured_at" }
}

struct CheckDetailDTO: Codable {
    let id: Int
    let title: String
    let submittedAt: String?
    let sections: [CheckSection]
    let photos: [CheckDetailPhoto]
    let notes: String?
    let injuries: String?
    let limitations: String?
    let coachFeedback: String

    enum CodingKeys: String, CodingKey {
        case id, title, sections, photos, notes, injuries, limitations
        case submittedAt = "submitted_at"
        case coachFeedback = "coach_feedback"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Check"
        submittedAt = try? c.decodeIfPresent(String.self, forKey: .submittedAt)
        sections = (try? c.decode([CheckSection].self, forKey: .sections)) ?? []
        photos = (try? c.decode([CheckDetailPhoto].self, forKey: .photos)) ?? []
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        injuries = try? c.decodeIfPresent(String.self, forKey: .injuries)
        limitations = try? c.decodeIfPresent(String.self, forKey: .limitations)
        coachFeedback = (try? c.decode(String.self, forKey: .coachFeedback)) ?? ""
    }
}

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

/// Google/Apple Calendar subscription feed — shared shape for both the
/// athlete's and the coach's own agenda feed.
struct CalendarFeedDTO: Codable {
    let feedUrl: String
    let webcalUrl: String
    let googleSubscribeUrl: String
    enum CodingKeys: String, CodingKey {
        case feedUrl = "feed_url"
        case webcalUrl = "webcal_url"
        case googleSubscribeUrl = "google_subscribe_url"
    }
}

struct MessageDTO: Codable, Identifiable, Hashable {
    let id: Int
    let body: String
    let messageType: String
    let isMine: Bool
    let sentAt: String?
    let attachmentUrl: String?
    let appointmentId: Int?
    let appointmentStatus: String?
    let appointmentTitle: String?
    let appointmentStart: String?
    let appointmentExpired: Bool?
    let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case messageType = "message_type"
        case isMine = "is_mine"
        case sentAt = "sent_at"
        case attachmentUrl = "attachment_url"
        case appointmentId = "appointment_id"
        case appointmentStatus = "appointment_status"
        case appointmentTitle = "appointment_title"
        case appointmentStart = "appointment_start"
        case appointmentExpired = "appointment_expired"
        case readAt = "read_at"
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
    let kind: String?
    let description: String?
    let price: Double
    let currency: String
    let durationDays: Int?
    let billingInterval: String?
    let includedServices: [String]
    let isOnlinePurchasable: Bool
    let coach: Coach?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, currency, coach, kind
        case planType = "plan_type"
        case durationDays = "duration_days"
        case billingInterval = "billing_interval"
        case includedServices = "included_services"
        case isOnlinePurchasable = "is_online_purchasable"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        planType = try c.decodeIfPresent(String.self, forKey: .planType)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        price = (try? c.decode(Double.self, forKey: .price)) ?? 0
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "EUR"
        durationDays = try c.decodeIfPresent(Int.self, forKey: .durationDays)
        billingInterval = try c.decodeIfPresent(String.self, forKey: .billingInterval)
        // included_services is a free-form JSON field: tolerate non-string arrays.
        includedServices = (try? c.decode([String].self, forKey: .includedServices)) ?? []
        isOnlinePurchasable = (try? c.decode(Bool.self, forKey: .isOnlinePurchasable)) ?? false
        coach = try c.decodeIfPresent(Coach.self, forKey: .coach)
    }
}

struct SubscriptionDTO: Codable, Hashable, Identifiable {
    let id: Int
    let status: String
    let paymentStatus: String?
    let startDate: String?
    let endDate: String?
    let autoRenew: Bool
    let manageable: Bool
    let plan: SubscriptionPlanDTO

    enum CodingKeys: String, CodingKey {
        case id, status, plan, manageable
        case paymentStatus = "payment_status"
        case startDate = "start_date"
        case endDate = "end_date"
        case autoRenew = "auto_renew"
    }
}

struct SubscriptionListResponse: Codable { let subscriptions: [SubscriptionDTO] }

/// Dashboard KPIs — same numbers as the web dashboard's tiles, computed
/// server-side by `_client_dashboard_kpis` so both surfaces always match.
struct DashboardSummaryDTO: Codable, Hashable {
    let weightCurrent: Double?
    let weightDelta: Double?
    let sessionsThisWeek: Int
    let kcalTarget: Double?
    let daysToRenewal: Int?

    enum CodingKeys: String, CodingKey {
        case weightCurrent = "weight_current"
        case weightDelta = "weight_delta"
        case sessionsThisWeek = "sessions_this_week"
        case kcalTarget = "kcal_target"
        case daysToRenewal = "days_to_renewal"
    }
}

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

struct AppointmentsResponse: Codable {
    let appointments: [AppointmentDTO]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case appointments; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appointments = try c.decodeIfPresent([AppointmentDTO].self, forKey: .appointments) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

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

/// Athlete-facing progress-check entry. Coach counterpart: `CoachProgressEntry`
/// (AthlynkCoach/Core/CoachModels.swift) — near-identical shape, differs in
/// `measurements`/`skinfolds` optionality and photo type. Keep field names in sync.
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

/// Site keys the client has ever recorded a value for — see APIClient.measurementSites().
struct MeasurementSitesDTO: Codable, Hashable {
    let measurements: [String]
    let skinfolds: [String]
}

struct ProgressResponse: Codable {
    let entries: [ProgressEntryDTO]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case entries; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([ProgressEntryDTO].self, forKey: .entries) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

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
    let brandName: String?
    let brandPrimary: String?
    let brandAccent: String?

    enum CodingKeys: String, CodingKey {
        case phone, gender, sport
        case firstName = "first_name"
        case lastName = "last_name"
        case weightKg = "weight_kg"
        case birthDate = "birth_date"
        case imageUrl = "profile_image_url"
        case brandName = "brand_name"
        case brandPrimary = "brand_primary"
        case brandAccent = "brand_accent"
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

/// Athlete-facing macro totals. Coach counterpart: `CoachMacros`
/// (AthlynkCoach/Core/CoachModels.swift) adds a `micros` field. Keep the
/// shared fields (kcal/protein/carb/fat) in sync.
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

struct FoodSearchResponse: Codable {
    let results: [FoodDTO]
    let categories: [String]?
}
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
    let hasMore: Bool

    enum CodingKeys: String, CodingKey { case events, phases; case hasMore = "has_more" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([JourneyEventDTO].self, forKey: .events) ?? []
        phases = try c.decodeIfPresent([JourneyPhaseDTO].self, forKey: .phases) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
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
    let exerciseSubstituted: Bool
    let actualExercise: SubstituteExerciseDTO?
    var id: Int { setNumber }

    enum CodingKeys: String, CodingKey {
        case rpe, completed
        case setNumber = "set_number"
        case repsDone = "reps_done"
        case loadUsed = "load_used"
        case loadUnit = "load_unit"
        case exerciseSubstituted = "exercise_substituted"
        case actualExercise = "actual_exercise"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setNumber = try c.decode(Int.self, forKey: .setNumber)
        repsDone = try c.decodeIfPresent(Int.self, forKey: .repsDone)
        loadUsed = try c.decodeIfPresent(Double.self, forKey: .loadUsed)
        loadUnit = try c.decodeIfPresent(String.self, forKey: .loadUnit)
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        exerciseSubstituted = try c.decodeIfPresent(Bool.self, forKey: .exerciseSubstituted) ?? false
        actualExercise = try c.decodeIfPresent(SubstituteExerciseDTO.self, forKey: .actualExercise)
    }
}

struct SessionLoggedExerciseDTO: Codable, Identifiable, Hashable {
    /// nil for exercises added in-session (no plan slot).
    let workoutExerciseId: Int?
    let exerciseName: String
    let exerciseNote: String?
    let prescribedReps: String?
    let added: Bool
    let sets: [LoggedSetDetailDTO]
    var id: String { workoutExerciseId.map { "we-\($0)" } ?? "add-\(exerciseName)" }

    /// Name of the movement actually performed (substituted sets carry it).
    var performedName: String {
        sets.first(where: { $0.actualExercise != nil })?.actualExercise?.name ?? exerciseName
    }
    var wasSubstituted: Bool { sets.contains { $0.exerciseSubstituted } }

    enum CodingKeys: String, CodingKey {
        case sets, added
        case workoutExerciseId = "workout_exercise_id"
        case exerciseName = "exercise_name"
        case exerciseNote = "exercise_note"
        case prescribedReps = "prescribed_reps"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutExerciseId = try c.decodeIfPresent(Int.self, forKey: .workoutExerciseId)
        exerciseName = try c.decode(String.self, forKey: .exerciseName)
        exerciseNote = try c.decodeIfPresent(String.self, forKey: .exerciseNote)
        prescribedReps = try c.decodeIfPresent(String.self, forKey: .prescribedReps)
        added = try c.decodeIfPresent(Bool.self, forKey: .added) ?? false
        sets = try c.decodeIfPresent([LoggedSetDetailDTO].self, forKey: .sets) ?? []
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

/// Athlete-facing supplement item. Coach counterpart: `CoachSupplementItem`
/// (AthlynkCoach/Core/CoachModels.swift). Keep field names in sync.
struct SupplementItemDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let quantity: String?
    let unit: String?
    let timing: String?
    let notes: String?

    /// "5 g" / "2 cps" — quantity + unit, blanks tolerated.
    var dose: String {
        [quantity ?? "", unit ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct SupplementSheetDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let notes: String?
    let coach: Coach?
    let items: [SupplementItemDTO]
}

struct SupplementsResponse: Codable {
    let sheets: [SupplementSheetDTO]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case sheets; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sheets = try c.decodeIfPresent([SupplementSheetDTO].self, forKey: .sheets) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

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
    let foodSearchMode: String
    enum CodingKeys: String, CodingKey {
        case email, notifications
        case foodSearchMode = "food_search_mode"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        notifications = try c.decodeIfPresent([SettingToggleDTO].self, forKey: .notifications) ?? []
        foodSearchMode = (try? c.decode(String.self, forKey: .foodSearchMode)) ?? "alimento"
    }
}

struct SettingsResponse: Codable { let settings: SettingsDTO }

// MARK: - Customizable dashboard layout (synced web ↔ iOS)

/// Per-widget options. v1 knows a single key (`client_ids` for the coach's
/// pinned-athletes widget); grow this struct as widget types gain options.
struct DashboardWidgetConfigDTO: Codable, Hashable {
    var clientIds: [Int]?
    /// Athlete-monitor widgets (athlete_body/training/nutrition): which athlete
    /// this instance shows. The in-widget picker can change it at view time.
    var clientId: Int?
    enum CodingKeys: String, CodingKey {
        case clientIds = "client_ids"
        case clientId = "client_id"
    }
}

/// One placed widget. `x`/`y`/`size` are the web grid's presentation hints —
/// iOS renders widgets in ARRAY ORDER (the canonical cross-platform order)
/// and, when reordering, rewrites `y = index` so the web grid re-flows.
struct DashboardWidgetDTO: Codable, Identifiable, Hashable {
    var id: String
    let type: String
    var x: Int
    var y: Int
    var size: String
    var config: DashboardWidgetConfigDTO?
}

struct DashboardLayoutDTO: Codable, Hashable {
    var version: Int
    var widgets: [DashboardWidgetDTO]
}

/// Catalog entry from the server registry (role-filtered).
struct WidgetCatalogItemDTO: Codable, Identifiable, Hashable {
    let type: String
    let title: String
    let desc: String
    let sfSymbol: String
    let mobileSize: String
    var id: String { type }
    enum CodingKeys: String, CodingKey {
        case type, title, desc
        case sfSymbol = "sf_symbol"
        case mobileSize = "mobile_size"
    }
}

struct DashboardLayoutResponse: Codable {
    let layout: DashboardLayoutDTO
    let catalog: [WidgetCatalogItemDTO]
}

/// Row of the coach's "Atleti in evidenza" widget.
struct PinnedAthleteDTO: Codable, Identifiable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let displayName: String
    let profileImageUrl: String?
    let sport: String?
    let lastCheckAt: String?
    let weightDelta: Double?
    let hasPendingCheck: Bool
    enum CodingKeys: String, CodingKey {
        case id, sport
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case profileImageUrl = "profile_image_url"
        case lastCheckAt = "last_check_at"
        case weightDelta = "weight_delta"
        case hasPendingCheck = "has_pending_check"
    }
}

struct PinnedAthletesResponse: Codable { let athletes: [PinnedAthleteDTO] }

// MARK: - Plans on offer (Piani e Prezzi)

struct PlansResponse: Codable { let plans: [SubscriptionPlanDTO] }

struct CheckoutStartResponse: Codable {
    let checkoutUrl: String
    enum CodingKeys: String, CodingKey { case checkoutUrl = "checkout_url" }
}

// MARK: - Active session (Sessione Attiva)

/// Reference to a catalog exercise chosen as substitute for a plan slot.
struct SubstituteExerciseDTO: Codable, Hashable {
    let id: Int
    let name: String
}

struct SessionExerciseDTO: Codable, Identifiable, Hashable {
    /// nil for exercises added by the athlete during the session (no plan slot).
    let workoutExerciseId: Int?
    /// Catalog exercise id — set only for added exercises.
    let exerciseId: Int?
    /// Catalog id of the plan slot's exercise (for "similar to" lookups).
    let exerciseCatalogId: Int?
    let name: String
    let targetMuscleGroup: String?
    let sets: Int
    let reps: String
    let loadValue: Double?
    let loadUnit: String?
    let recoverySeconds: Int?
    let tempo: String?
    let notes: String?
    let added: Bool
    let removed: Bool
    let substitutedWith: SubstituteExerciseDTO?
    /// Coach-prescribed targets — distinct from the athlete's own per-set
    /// logged RPE (`LoggedSetDTO.rpe`).
    let rir: Int?
    let rpe: Int?
    let coverImageUrl: String?
    let demoGifUrl: String?

    var id: String { workoutExerciseId.map { "we-\($0)" } ?? "add-\(exerciseId ?? 0)" }
    var displayName: String { substitutedWith?.name ?? name }

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, notes, tempo, added, removed, rir, rpe
        case workoutExerciseId = "workout_exercise_id"
        case exerciseId = "exercise_id"
        case exerciseCatalogId = "exercise_catalog_id"
        case targetMuscleGroup = "target_muscle_group"
        case loadValue = "load_value"
        case loadUnit = "load_unit"
        case recoverySeconds = "recovery_seconds"
        case substitutedWith = "substituted_with"
        case coverImageUrl = "cover_image"
        case demoGifUrl = "demo_gif"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutExerciseId = try c.decodeIfPresent(Int.self, forKey: .workoutExerciseId)
        exerciseId = try c.decodeIfPresent(Int.self, forKey: .exerciseId)
        exerciseCatalogId = try c.decodeIfPresent(Int.self, forKey: .exerciseCatalogId)
        name = try c.decode(String.self, forKey: .name)
        targetMuscleGroup = try c.decodeIfPresent(String.self, forKey: .targetMuscleGroup)
        // No fabricated default — a blank prescription stays blank (0 / "").
        sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 0
        reps = try c.decodeIfPresent(String.self, forKey: .reps) ?? ""
        loadValue = try c.decodeIfPresent(Double.self, forKey: .loadValue)
        loadUnit = try c.decodeIfPresent(String.self, forKey: .loadUnit)
        recoverySeconds = try c.decodeIfPresent(Int.self, forKey: .recoverySeconds)
        tempo = try c.decodeIfPresent(String.self, forKey: .tempo)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        added = try c.decodeIfPresent(Bool.self, forKey: .added) ?? false
        removed = try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        substitutedWith = try c.decodeIfPresent(SubstituteExerciseDTO.self, forKey: .substitutedWith)
        rir = try c.decodeIfPresent(Int.self, forKey: .rir)
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
        coverImageUrl = try c.decodeIfPresent(String.self, forKey: .coverImageUrl)
        demoGifUrl = try c.decodeIfPresent(String.self, forKey: .demoGifUrl)
    }

    /// Local construction for exercises the athlete adds mid-session.
    init(addedExerciseId: Int, name: String, targetMuscleGroup: String? = nil,
         coverImageUrl: String? = nil, demoGifUrl: String? = nil) {
        self.workoutExerciseId = nil
        self.exerciseId = addedExerciseId
        self.exerciseCatalogId = addedExerciseId
        self.name = name
        self.targetMuscleGroup = targetMuscleGroup
        self.sets = 3
        self.reps = "10"
        self.loadValue = nil
        self.loadUnit = "KG"
        self.recoverySeconds = 90
        self.tempo = nil
        self.notes = nil
        self.added = true
        self.removed = false
        self.substitutedWith = nil
        self.rir = nil
        self.rpe = nil
        self.coverImageUrl = coverImageUrl
        self.demoGifUrl = demoGifUrl
    }
}

struct LoggedSetDTO: Codable, Hashable {
    let workoutExerciseId: Int?
    /// Catalog exercise id for sets of added exercises (workoutExerciseId nil).
    let exerciseId: Int?
    let setNumber: Int
    let repsDone: Int?
    let loadUsed: Double?
    let loadUnit: String?
    let rpe: Int?
    let completed: Bool

    /// Matches SessionExerciseDTO.id
    var exerciseKey: String { workoutExerciseId.map { "we-\($0)" } ?? "add-\(exerciseId ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case rpe, completed
        case workoutExerciseId = "workout_exercise_id"
        case exerciseId = "exercise_id"
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

// MARK: - Exercise catalog search (add / substitute in session)

struct ExerciseSearchItemDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let primaryMuscle: String
    let muscles: [String]
    let equipment: [String]
    /// The backend never actually sends this key today — kept optional so a
    /// missing key doesn't fail the whole decode (it used to, silently,
    /// since this was non-optional: every search came back empty).
    let videoUrl: String?
    let coverImageUrl: String?
    let demoGifUrl: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, muscles, equipment, description
        case primaryMuscle = "primary_muscle"
        case videoUrl = "video_url"
        case coverImageUrl = "cover_image"
        case demoGifUrl = "demo_gif"
    }
}

struct MuscleGroupDTO: Codable, Identifiable, Hashable {
    let name: String
    let slug: String
    let region: String
    var id: String { slug }
}

struct ExerciseSearchResponse: Codable {
    let results: [ExerciseSearchItemDTO]
    let muscleGroups: [MuscleGroupDTO]?

    enum CodingKeys: String, CodingKey {
        case results
        case muscleGroups = "muscle_groups"
    }
}

// MARK: - Exercise catalog detail (gif/description/instructions, by id)

/// Full catalog detail for one exercise — backs `ExerciseCatalogDetailSheet`,
/// shown from any list/picker row that only has a bare exercise id in hand
/// (no prescription attached yet). Mirrors `_serialize_exercise_full`
/// (`WebApp/src/config/views_workouts_taxonomy.py`), reachable by both apps
/// via the same dual-auth `GET /api/exercises/<id>/` endpoint.
struct ExerciseCatalogDetailDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let coverImageUrl: String?
    let demoGifUrl: String?
    let instructionSteps: [String]
    let muscleDetail: String?
    let isCustom: Bool
    let category: ExerciseCatalogCategoryDTO?
    let equipment: [ExerciseCatalogEquipmentDTO]
    let primaryMuscles: [ExerciseCatalogMuscleDTO]
    let secondaryMuscles: [ExerciseCatalogMuscleDTO]
    let coachNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, equipment
        case coverImageUrl = "cover_image"
        case demoGifUrl = "demo_gif"
        case instructionSteps = "instruction_steps"
        case muscleDetail = "muscle_detail"
        case isCustom = "is_custom"
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case coachNotes = "coach_notes"
    }
}

struct ExerciseCatalogCategoryDTO: Codable, Hashable {
    let id: Int
    let name: String
}

struct ExerciseCatalogEquipmentDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct ExerciseCatalogMuscleDTO: Codable, Identifiable, Hashable {
    let id: Int
    let slug: String
    let name: String
    let region: String?
    let colorToken: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, region
        case colorToken = "color_token"
    }
}

/// One row of the history-based progress list (all movements ever performed).
struct ExerciseHistoryItemDTO: Codable, Identifiable, Hashable {
    let name: String
    let lastDone: String?
    let sessionsCount: Int
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case lastDone = "last_done"
        case sessionsCount = "sessions_count"
    }
}

struct ExercisesHistoryResponse: Codable { let exercises: [ExerciseHistoryItemDTO] }

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
