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
    let sport: String?
    // Extended fields (present only in client detail).
    let phone: String?
    let gender: String?
    let birthDate: String?
    let weightKg: Double?
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
        case birthDate = "birth_date"
        case weightKg = "weight_kg"
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
    let stripeConnectAccountId: String?
    let stripeConnectChargesEnabled: Bool
    let stripeConnectDetailsSubmitted: Bool
    let brandName: String
    let brandPrimary: String
    let brandAccent: String
    let platformPurchase: PlatformPurchaseDTO?

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
        case stripeConnectAccountId = "stripe_connect_account_id"
        case stripeConnectChargesEnabled = "stripe_connect_charges_enabled"
        case stripeConnectDetailsSubmitted = "stripe_connect_details_submitted"
        case brandName = "brand_name"
        case brandPrimary = "brand_primary"
        case brandAccent = "brand_accent"
        case platformPurchase = "platform_purchase"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastName = try c.decode(String.self, forKey: .lastName)
        professionalType = try c.decodeIfPresent(String.self, forKey: .professionalType)
        specialization = try c.decodeIfPresent(String.self, forKey: .specialization)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        certifications = try c.decodeIfPresent(String.self, forKey: .certifications)
        yearsExperience = try c.decodeIfPresent(Int.self, forKey: .yearsExperience)
        profileImageUrl = try c.decodeIfPresent(String.self, forKey: .profileImageUrl)
        socialInstagram = try c.decodeIfPresent(String.self, forKey: .socialInstagram)
        socialYoutube = try c.decodeIfPresent(String.self, forKey: .socialYoutube)
        socialTiktok = try c.decodeIfPresent(String.self, forKey: .socialTiktok)
        socialWebsite = try c.decodeIfPresent(String.self, forKey: .socialWebsite)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        stripeConnectAccountId = try c.decodeIfPresent(String.self, forKey: .stripeConnectAccountId)
        stripeConnectChargesEnabled = (try? c.decode(Bool.self, forKey: .stripeConnectChargesEnabled)) ?? false
        stripeConnectDetailsSubmitted = (try? c.decode(Bool.self, forKey: .stripeConnectDetailsSubmitted)) ?? false
        brandName = try c.decodeIfPresent(String.self, forKey: .brandName) ?? ""
        brandPrimary = try c.decodeIfPresent(String.self, forKey: .brandPrimary) ?? ""
        brandAccent = try c.decodeIfPresent(String.self, forKey: .brandAccent) ?? ""
        platformPurchase = try c.decodeIfPresent(PlatformPurchaseDTO.self, forKey: .platformPurchase)
    }
}

/// The coach's own Athlynk platform subscription (Athena/Apollo/Zeus, paid via
/// Stripe from the marketing site) — surfaced read-only above the "Gestisci
/// abbonamento" billing-portal action, mirroring the web settings page.
struct PlatformPurchaseDTO: Codable, Hashable {
    let plan: String
    let status: String
    let billingInterval: String?
    let currentPeriodEnd: String?
    enum CodingKeys: String, CodingKey {
        case plan, status
        case billingInterval = "billing_interval"
        case currentPeriodEnd = "current_period_end"
    }
}

struct CoachProfileResponse: Codable { let profile: CoachProfileDTO }

// MARK: - Stripe Connect onboarding

struct CoachConnectStartResponse: Codable {
    let accountLinkUrl: String
    enum CodingKeys: String, CodingKey { case accountLinkUrl = "account_link_url" }
}

struct CoachConnectStatusResponse: Codable {
    let stripeConnectAccountId: String?
    let stripeConnectChargesEnabled: Bool
    let stripeConnectDetailsSubmitted: Bool
    enum CodingKeys: String, CodingKey {
        case stripeConnectAccountId = "stripe_connect_account_id"
        case stripeConnectChargesEnabled = "stripe_connect_charges_enabled"
        case stripeConnectDetailsSubmitted = "stripe_connect_details_submitted"
    }
}

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

struct CoachAgendaResponse: Codable {
    let appointments: [CoachAgendaItem]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case appointments; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appointments = try c.decodeIfPresent([CoachAgendaItem].self, forKey: .appointments) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

// MARK: - Clients list

struct CoachClientRow: Codable, Identifiable, Hashable {
    let id: Int
    let displayName: String
    let firstName: String
    let lastName: String
    let profileImageUrl: String?
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
    var hasMore: Bool = false

    enum CodingKeys: String, CodingKey {
        case clients, total, active
        case hasMore = "has_more"
    }

    // `has_more` is optional so a backend that predates pagination still decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clients = try c.decode([CoachClientRow].self, forKey: .clients)
        total = try c.decode(Int.self, forKey: .total)
        active = try c.decode(Int.self, forKey: .active)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

// MARK: - Onboarding (coach crea atleta)

struct CoachSubscriptionPlanDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let price: Double
    let durationDays: Int?
    enum CodingKeys: String, CodingKey {
        case id, name, price
        case durationDays = "duration_days"
    }
}

struct CoachSubscriptionPlansResponse: Codable { let plans: [CoachSubscriptionPlanDTO] }

// MARK: - Gestione modelli check (parità web)

struct CoachCheckTemplate: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String
    let presetKey: String
    let isModifiedPreset: Bool
    let questionnaireType: String
    let questionsCount: Int
    let stepsCount: Int
    let updatedAt: String?

    var isPreset: Bool { !presetKey.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case presetKey = "preset_key"
        case isModifiedPreset = "is_modified_preset"
        case questionnaireType = "questionnaire_type"
        case questionsCount = "questions_count"
        case stepsCount = "steps_count"
        case updatedAt = "updated_at"
    }
}

struct CoachCheckTemplatesResponse: Codable {
    let presets: [CoachCheckTemplate]
    let customs: [CoachCheckTemplate]
}

/// Full template: `questions` are resolved (ISAK labels) for the fill form;
/// the builder reconstructs its blocks from them.
struct CoachCheckTemplateDetail: Codable, Hashable {
    let id: Int
    let title: String
    let presetKey: String
    let questions: [CheckQuestion]
    let steps: [CheckStep]

    var isPreset: Bool { !presetKey.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, title, questions
        case presetKey = "preset_key"
        case steps = "steps_config"
    }
}

/// ISAK catalog entry for the builder's antropometria block.
struct CheckCatalogItem: Codable, Identifiable, Hashable {
    let key: String
    let label: String
    let isLimb: Bool
    var id: String { key }
    enum CodingKeys: String, CodingKey {
        case key
        case label = "it"
        case isLimb = "is_limb"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = (try? c.decode(String.self, forKey: .label)) ?? key
        isLimb = (try? c.decode(Bool.self, forKey: .isLimb)) ?? false
    }
}

struct CheckCatalog: Codable {
    let circumferences: [CheckCatalogItem]
    let skinfolds: [CheckCatalogItem]
}

/// Snapshot + current values for the "edit values" form.
struct CoachCheckPrefill: Codable, Identifiable {
    let id = UUID()
    let questions: [CheckQuestion]
    let steps: [CheckStep]
    let prefill: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case questions, prefill
        case steps = "steps_config"
    }
}

/// Minimal heterogeneous JSON value (prefill values are numbers, strings or arrays).
enum AnyCodable: Codable, Hashable {
    case string(String), double(Double), bool(Bool), array([String]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([String].self) { self = .array(a) }
        else { self = .null }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// String form for text fields.
    var asString: String {
        switch self {
        case .string(let s): return s
        case .double(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "1" : "0"
        case .array(let a): return a.joined(separator: ",")
        case .null: return ""
        }
    }
    var asStringArray: [String] {
        if case .array(let a) = self { return a }
        let s = asString
        return s.isEmpty ? [] : [s]
    }
}

// MARK: - Client detail

struct TitleRef: Codable, Hashable {
    let assignmentId: Int?
    let title: String
    let planMode: String?   // only set for nutrition refs ("FOOD" | "MACRO")
    enum CodingKeys: String, CodingKey {
        case title
        case assignmentId = "assignment_id"
        case planMode = "plan_mode"
    }
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
    var reviewed: Bool
    let client: CoachClient?
    let questionnaireType: String?
    let isQuickMeasurement: Bool
    let filledByCoach: Bool
    enum CodingKeys: String, CodingKey {
        case id, title, reviewed, client
        case submittedAt = "submitted_at"
        case weightKg = "weight_kg"
        case questionnaireType = "questionnaire_type"
        case isQuickMeasurement = "is_quick_measurement"
        case filledByCoach = "filled_by_coach"
    }
}

struct IdTitle: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
}

// MARK: - Supplement protocols (Integratori)

struct CoachSupplementSummary: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let itemCount: Int
    let assignedCount: Int
    enum CodingKeys: String, CodingKey {
        case id, title
        case itemCount = "item_count"
        case assignedCount = "assigned_count"
    }
}
struct CoachSupplementsResponse: Codable { let protocols: [CoachSupplementSummary] }

/// One editable supplement row. `rowId` keeps SwiftUI identity stable while editing;
/// the server item id (if any) is irrelevant once loaded into the builder.
/// Athlete counterpart: `SupplementItemDTO` (Shared/Core/Models.swift). Keep field names in sync.
struct CoachSupplementItem: Codable, Identifiable, Hashable {
    var rowId = UUID()
    var name: String = ""
    var quantity: String = ""
    var unit: String = "g"
    var timing: String = ""
    var notes: String = ""
    var id: UUID { rowId }
    enum CodingKeys: String, CodingKey { case name, quantity, unit, timing, notes }
}

struct CoachSupplementDetail: Codable {
    let id: Int
    let title: String
    let notes: String
    let items: [CoachSupplementItem]
}

struct CoachSupplementActiveAssignmentRef: Codable, Hashable {
    let assignmentId: Int
    let protocolId: Int
    let protocolTitle: String
    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case protocolId = "protocol_id"
        case protocolTitle = "protocol_title"
    }
}

struct CoachSupplementAssignableClient: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let activeAssignment: CoachSupplementActiveAssignmentRef?
    enum CodingKeys: String, CodingKey {
        case id, name
        case activeAssignment = "active_assignment"
    }
}

struct CoachClientDetailDTO: Codable {
    let client: CoachClient
    let relationship: CoachRelationship
    let activeWorkout: TitleRef?
    let activeNutrition: TitleRef?
    let activeSubscription: CoachSubRef?
    let checks: [CoachCheckRow]
    let supplementSheets: [IdTitle]
    let conversationId: Int?

    enum CodingKeys: String, CodingKey {
        case client, relationship, checks
        case activeWorkout = "active_workout"
        case activeNutrition = "active_nutrition"
        case activeSubscription = "active_subscription"
        case supplementSheets = "supplement_sheets"
        case conversationId = "conversation_id"
    }
}

// MARK: - Check review

struct CoachChecksResponse: Codable {
    let checks: [CoachCheckRow]
    let pendingCount: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case checks; case pendingCount = "pending_count"; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checks = try c.decodeIfPresent([CoachCheckRow].self, forKey: .checks) ?? []
        pendingCount = (try? c.decode(Int.self, forKey: .pendingCount)) ?? 0
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

struct CoachClientChecksResponse: Codable {
    let checks: [CoachCheckRow]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case checks; case hasMore = "has_more" }
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
    let answers: [String: AnyCodable]
    let notes: String?
    let injuries: String?
    let limitations: String?
    let coachFeedback: String
    let coachPrivateNotes: String
    let client: CoachClient
    let photos: [CoachCheckPhoto]

    enum CodingKeys: String, CodingKey {
        case id, title, measurements, skinfolds, answers, notes, injuries, limitations, client, photos
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
        answers = (try? c.decode([String: AnyCodable].self, forKey: .answers)) ?? [:]
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
    let folderId: Int?
    let status: String?
    let isTemplate: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, goal, level
        case durationWeeks = "duration_weeks"
        case frequencyPerWeek = "frequency_per_week"
        case planMode = "plan_mode"
        case planKind = "plan_kind"
        case dailyKcal = "daily_kcal"
        case assignedCount = "assigned_count"
        case folderId = "folder_id"
        case status
        case isTemplate = "is_template"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        goal = try c.decodeIfPresent(String.self, forKey: .goal)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        durationWeeks = try c.decodeIfPresent(Int.self, forKey: .durationWeeks)
        frequencyPerWeek = try c.decodeIfPresent(Int.self, forKey: .frequencyPerWeek)
        planMode = try c.decodeIfPresent(String.self, forKey: .planMode)
        planKind = try c.decodeIfPresent(String.self, forKey: .planKind)
        dailyKcal = try c.decodeIfPresent(Int.self, forKey: .dailyKcal)
        assignedCount = try c.decode(Int.self, forKey: .assignedCount)
        folderId = try c.decodeIfPresent(Int.self, forKey: .folderId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        isTemplate = try c.decodeIfPresent(Bool.self, forKey: .isTemplate) ?? false
    }
}

// MARK: - Folders (workout / nutrition / check — identical shape server-side)

struct CoachFolder: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let labelText: String
    let labelColor: String
    let order: Int
    let count: Int

    enum CodingKeys: String, CodingKey {
        case id, title, order
        case labelText = "label_text"
        case labelColor = "label_color"
        case planCount = "plan_count"
        case templateCount = "template_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        labelText = try c.decodeIfPresent(String.self, forKey: .labelText) ?? ""
        labelColor = try c.decodeIfPresent(String.self, forKey: .labelColor) ?? ""
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        count = (try? c.decode(Int.self, forKey: .planCount))
            ?? (try? c.decode(Int.self, forKey: .templateCount)) ?? 0
    }

    /// The auto-created "Template" folder every coach has by default — pinned
    /// first, not renamable/deletable. Matched by title (server enforces one
    /// unique folder per coach per title, so this is unambiguous).
    var isDefaultTemplates: Bool { title == "Template" }
}

/// Lightweight row shape returned by the paginated check-templates-by-folder
/// endpoint — distinct from `CoachCheckTemplate` (which backs the unpaginated
/// presets+customs list and requires preset_key/questionnaire_type).
struct CoachFolderedCheckTemplate: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String
    let questionsCount: Int
    let stepsCount: Int
    let folderId: Int?
    let isPreset: Bool
    let isModifiedPreset: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case questionsCount = "questions_count"
        case stepsCount = "steps_count"
        case folderId = "folder_id"
        case isPreset = "is_preset"
        case isModifiedPreset = "is_modified_preset"
    }
}

struct CoachCheckTemplatePage: Codable {
    let templates: [CoachFolderedCheckTemplate]
    let hasMore: Bool
    let total: Int
    enum CodingKeys: String, CodingKey { case templates, total; case hasMore = "has_more" }
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
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case plans, assignments; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plans = try c.decodeIfPresent([CoachPlanRow].self, forKey: .plans) ?? []
        assignments = try c.decodeIfPresent([CoachAssignmentRow].self, forKey: .assignments) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

struct CoachNutritionResponse: Codable {
    let plans: [CoachPlanRow]
    let assignments: [CoachAssignmentRow]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case plans, assignments; case hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plans = try c.decodeIfPresent([CoachPlanRow].self, forKey: .plans) ?? []
        assignments = try c.decodeIfPresent([CoachAssignmentRow].self, forKey: .assignments) ?? []
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

// MARK: - Subscriptions

struct CoachPlanSummary: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let planType: String?
    let kind: String?
    let description: String
    let price: Double
    let currency: String
    let durationDays: Int?
    let billingInterval: String?
    let isActive: Bool
    let isOnlinePurchasable: Bool
    let activeCount: Int
    enum CodingKeys: String, CodingKey {
        case id, name, price, currency, kind, description
        case planType = "plan_type"
        case durationDays = "duration_days"
        case billingInterval = "billing_interval"
        case isActive = "is_active"
        case isOnlinePurchasable = "is_online_purchasable"
        case activeCount = "active_count"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        planType = try c.decodeIfPresent(String.self, forKey: .planType)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        price = try c.decode(Double.self, forKey: .price)
        currency = try c.decode(String.self, forKey: .currency)
        durationDays = try c.decodeIfPresent(Int.self, forKey: .durationDays)
        billingInterval = try c.decodeIfPresent(String.self, forKey: .billingInterval)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        isOnlinePurchasable = (try? c.decode(Bool.self, forKey: .isOnlinePurchasable)) ?? false
        activeCount = try c.decode(Int.self, forKey: .activeCount)
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
    let hasMore: Bool
    let stripeConnectChargesEnabled: Bool
    enum CodingKeys: String, CodingKey {
        case plans, subscriptions, currency
        case activeCount = "active_count"
        case monthlyRevenue = "monthly_revenue"
        case hasMore = "has_more"
        case stripeConnectChargesEnabled = "stripe_connect_charges_enabled"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plans = try c.decodeIfPresent([CoachPlanSummary].self, forKey: .plans) ?? []
        subscriptions = try c.decodeIfPresent([CoachSubscriptionRow].self, forKey: .subscriptions) ?? []
        activeCount = (try? c.decode(Int.self, forKey: .activeCount)) ?? 0
        monthlyRevenue = (try? c.decode(Double.self, forKey: .monthlyRevenue)) ?? 0
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "EUR"
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
        stripeConnectChargesEnabled = (try? c.decode(Bool.self, forKey: .stripeConnectChargesEnabled)) ?? false
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

/// Coach-facing progress-check entry. Athlete counterpart: `ProgressEntryDTO`
/// (Shared/Core/Models.swift) — near-identical shape, differs in
/// `measurements`/`skinfolds` optionality and photo type. Keep field names in sync.
struct CoachProgressEntry: Codable, Identifiable, Hashable {
    let id: Int
    let submittedAt: String?
    let weightKg: Double?
    let measurements: [String: String]
    let skinfolds: [String: String]
    let coachFeedback: String?
    let notes: String?
    let photos: [CoachCheckPhoto]

    enum CodingKeys: String, CodingKey {
        case id, measurements, skinfolds, notes, photos
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
        skinfolds = (try? c.decode([String: String].self, forKey: .skinfolds)) ?? [:]
        coachFeedback = try? c.decodeIfPresent(String.self, forKey: .coachFeedback)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        photos = (try? c.decode([CoachCheckPhoto].self, forKey: .photos)) ?? []
    }
}

struct CoachProgressResponse: Codable { let entries: [CoachProgressEntry] }

// MARK: - Client active workout (for the per-exercise trend drill-down)

struct CoachClientWorkoutDTO: Codable {
    struct PlanRef: Codable { let id: Int; let title: String }
    struct Day: Codable, Identifiable {
        let id: Int
        let title: String?
        let dayName: String?
        let exercises: [ExerciseDTO]
        enum CodingKeys: String, CodingKey {
            case id, title, exercises
            case dayName = "day_name"
        }
        var label: String { title ?? dayName ?? "Giorno" }
    }
    let plan: PlanRef?
    let days: [Day]
}

// MARK: - Plan detail (workout)

/// Coach-facing exercise shape (editable, so carries extra builder-only fields).
/// Athlete counterpart: `ExerciseDTO` (Shared/Core/Models.swift). Keep field names in sync.
struct CoachWorkoutExerciseDTO: Codable, Identifiable, Hashable {
    let id: Int
    /// Catalog `Exercise` id — distinct from `id` above (the `WorkoutExercise`
    /// prescription pk). Use this one for `APIClient.exerciseCatalogDetail`.
    let exerciseId: Int?
    let name: String
    let coverImageUrl: String?
    let demoGifUrl: String?
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
        case exerciseId = "exercise_id"
        case coverImageUrl = "cover_image"
        case demoGifUrl = "demo_gif"
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

/// Coach-facing workout day shape. Athlete counterpart: `WorkoutDayDTO`
/// (Shared/Core/Models.swift). Keep field names in sync.
struct CoachWorkoutDayDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let order: Int
    let focus: String?
    let notes: String?
    let exercises: [CoachWorkoutExerciseDTO]
}

/// Coach-facing workout plan shape. Athlete counterpart: `WorkoutPlanDTO`
/// (Shared/Core/Models.swift). Keep field names in sync.
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

/// Coach-facing macro totals (adds `micros` over the athlete side). Athlete
/// counterpart: `MacroMacrosDTO` (Shared/Core/Models.swift). Keep the shared
/// fields (kcal/protein/carb/fat) in sync.
struct CoachMacros: Codable, Hashable {
    let kcal: Double
    let protein: Double
    let carb: Double
    let fat: Double
    /// Aggregated micronutrients of the whole plan (coach-only). Nil on payloads
    /// that don't compute them. Mirrors the web micro flip card.
    let micros: CoachMicrosDTO?
}

/// Plan-level micronutrient totals. Keys mirror the web `microDefs()` grouping.
struct CoachMicrosDTO: Codable, Hashable {
    let iron, calcium, sodium, potassium, phosphorus, zinc, magnesium, copper: Double
    let selenium, iodine, manganese: Double
    let vitB1, vitB2, vitC, niacin, vitB6, folate, vitB12: Double
    let isoleucine, leucine, valine, lactose: Double

    enum CodingKeys: String, CodingKey {
        case iron, calcium, sodium, potassium, phosphorus, zinc, magnesium, copper
        case selenium, iodine, manganese
        case vitB1 = "vit_b1", vitB2 = "vit_b2", vitC = "vit_c", niacin
        case vitB6 = "vit_b6", folate, vitB12 = "vit_b12"
        case isoleucine, leucine, valine, lactose
    }
}

/// Coach-facing meal item shape, backed by `config/api_coach.py`'s
/// `_food_macros()` (JSON key `carb`, singular). Athlete counterpart:
/// `MealItemDTO` (Shared/Core/Models.swift) is backed by a *different*
/// endpoint (`config/api.py`, JSON key `carbs`, plural) — the key mismatch is
/// real but each DTO is correct for its own endpoint. Don't "fix" one to
/// match the other without changing the backend serializer too.
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

/// Coach-facing meal shape. Athlete counterpart: `MealDTO`
/// (Shared/Core/Models.swift). Keep field names in sync.
struct CoachMealDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let order: Int
    let dayOfWeek: String?
    let notes: String?
    let items: [CoachMealItemDTO]
    enum CodingKeys: String, CodingKey {
        case id, name, order, notes, items
        case dayOfWeek = "day_of_week"
    }
}

struct CoachDayTarget: Codable, Hashable, Identifiable {
    let dayOfWeek: String
    let kcal: Int?
    let protein: Int?
    let carb: Int?
    let fat: Int?
    var id: String { dayOfWeek }
    enum CodingKeys: String, CodingKey {
        case kcal, protein, carb, fat
        case dayOfWeek = "day_of_week"
    }
}

struct CoachNutritionDetailDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let planMode: String?
    let planKind: String?
    let dailyKcal: Int?
    let proteinTargetG: Int?
    let carbTargetG: Int?
    let fatTargetG: Int?
    let description: String?
    let status: String?
    let meals: [CoachMealDTO]
    let dayTargets: [CoachDayTarget]?
    let totals: CoachMacros
    enum CodingKeys: String, CodingKey {
        case id, title, description, status, meals, totals
        case planMode = "plan_mode"
        case planKind = "plan_kind"
        case dailyKcal = "daily_kcal"
        case proteinTargetG = "protein_target_g"
        case carbTargetG = "carb_target_g"
        case fatTargetG = "fat_target_g"
        case dayTargets = "day_targets"
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

// MARK: - Builder search results (exercise DB + food DB)

struct BuilderEquipmentRef: Codable, Identifiable, Hashable {
    let id: Int
    let nameIt: String

    enum CodingKeys: String, CodingKey {
        case id
        case nameIt = "name_it"
    }
}

struct BuilderExercise: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let targetMuscleGroup: String?
    let equipment: [BuilderEquipmentRef]
    let coverImageUrl: String?
    let demoGifUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, equipment
        case targetMuscleGroup = "target_muscle_group"
        case coverImageUrl = "cover_image"
        case demoGifUrl = "demo_gif"
    }
}

struct BuilderFood: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String?
    let kcal: Double
    let protein: Double
    let carb: Double
    let fat: Double
}

struct BuilderFoodSearchResponse: Codable {
    let results: [BuilderFood]
    let categories: [String]?
}

// MARK: - Assignable clients (wizard finalize step)

struct CoachActiveAssignmentRef: Codable, Hashable {
    let assignmentId: Int
    let planId: Int
    let planTitle: String
    let endDate: String?
    let weeksRemaining: Int?
    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case planId = "plan_id"
        case planTitle = "plan_title"
        case endDate = "end_date"
        case weeksRemaining = "weeks_remaining"
    }
}

struct CoachAssignableClient: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let activeAssignment: CoachActiveAssignmentRef?
    enum CodingKeys: String, CodingKey {
        case id, name
        case activeAssignment = "active_assignment"
    }
}

struct CoachFabbisogniDTO: Codable {
    let fresh: Bool
    let submittedAt: String?
    let data: Data?

    struct Data: Codable {
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
    enum CodingKeys: String, CodingKey {
        case fresh
        case submittedAt = "submitted_at"
        case data
    }
}

// MARK: - Client "Progressi" dashboard (mirrors the web progressi page)

struct CoachProgressKpiDTO: Codable {
    let totalSessions: Int
    let avgSetsPerSession: Double
    let streakDays: Int
    let overallAdherencePct: Double?

    enum CodingKeys: String, CodingKey {
        case totalSessions = "total_sessions"
        case avgSetsPerSession = "avg_sets_per_session"
        case streakDays = "streak_days"
        case overallAdherencePct = "overall_adherence_pct"
    }
}

struct AdherencePointDTO: Codable, Identifiable {
    let week: String
    let pct: Double
    var id: String { week }
}

struct RpePointDTO: Codable, Identifiable {
    let week: String
    let avgRpe: Double?
    var id: String { week }
    enum CodingKeys: String, CodingKey { case week; case avgRpe = "avg_rpe" }
}
