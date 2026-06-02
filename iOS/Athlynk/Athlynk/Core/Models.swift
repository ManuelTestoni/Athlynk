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

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
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
    let heightCm: Int?
    let primaryGoal: String?
    let activityLevel: String?
    enum CodingKeys: String, CodingKey {
        case heightCm = "height_cm"
        case primaryGoal = "primary_goal"
        case activityLevel = "activity_level"
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

struct CheckDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let dueDate: String?
    let expiresAt: String?
    let coach: Coach?

    enum CodingKeys: String, CodingKey {
        case id, title, coach
        case dueDate = "due_date"
        case expiresAt = "expires_at"
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

struct NotificationsResponse: Codable { let notifications: [NotificationDTO] }

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

struct MessagesResponse: Codable { let messages: [MessageDTO] }
