import Foundation
import SwiftUI

// MARK: - Goal Categories

enum GoalCategory: String, Codable, CaseIterable {
    case improveSleep = "improve_sleep"
    case improvePosture = "improve_posture"
    case standLonger = "stand_longer"
    case sitWithoutPain = "sit_without_pain"
    case workWithEquipment = "work_with_equipment"
    case driveWithoutPain = "drive_without_pain"
    case reduceMorningStiffness = "reduce_morning_stiffness"
    case coreAndBalance = "core_and_balance"
    case flexibilityAndMobility = "flexibility_and_mobility"
    case manageStress = "manage_stress"
    case stayActiveAsYouAge = "stay_active_as_you_age"
    case fasterWorkoutRecovery = "faster_workout_recovery"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .improveSleep: return "Improve Sleep"
        case .improvePosture: return "Improve Posture"
        case .standLonger: return "Stand Longer"
        case .sitWithoutPain: return "Sit Without Pain"
        case .workWithEquipment: return "Work with Equipment"
        case .driveWithoutPain: return "Drive Without Pain"
        case .reduceMorningStiffness: return "Reduce Morning Stiffness"
        case .coreAndBalance: return "Core & Balance"
        case .flexibilityAndMobility: return "Flexibility & Mobility"
        case .manageStress: return "Manage Stress"
        case .stayActiveAsYouAge: return "Stay Active as You Age"
        case .fasterWorkoutRecovery: return "Faster Workout Recovery"
        case .custom: return "Custom Goal"
        }
    }

    /// One-line plain-English description shown under each goal card so users can
    /// choose with confidence instead of guessing from a two-word title (audit #45).
    var subtitle: String {
        switch self {
        case .improveSleep: return "Wind-down routines & gentle evening mobility"
        case .improvePosture: return "Undo desk slouch and stand tall"
        case .standLonger: return "Build tolerance for time on your feet"
        case .sitWithoutPain: return "Ease discomfort from long sitting"
        case .workWithEquipment: return "Use bands, weights or a gym you have"
        case .driveWithoutPain: return "Comfort for commutes and long drives"
        case .reduceMorningStiffness: return "Loosen up and move easier at the start of the day"
        case .coreAndBalance: return "Steadier, stronger trunk and balance"
        case .flexibilityAndMobility: return "Move through a fuller range of motion"
        case .manageStress: return "Breathing & mobility to unwind"
        case .stayActiveAsYouAge: return "Keep strong, mobile and independent"
        case .fasterWorkoutRecovery: return "Bounce back quicker between sessions"
        case .custom: return "Describe your own goal"
        }
    }

    var icon: String {
        switch self {
        case .improveSleep: return "moon.zzz.fill"
        case .improvePosture: return "figure.stand"
        case .standLonger: return "building.2.fill"
        case .sitWithoutPain: return "chair.fill"
        case .workWithEquipment: return "wrench.and.screwdriver.fill"
        case .driveWithoutPain: return "car.fill"
        case .reduceMorningStiffness: return "sunrise.fill"
        case .coreAndBalance: return "figure.core.training"
        case .flexibilityAndMobility: return "figure.flexibility"
        case .manageStress: return "brain.head.profile"
        case .stayActiveAsYouAge: return "leaf.fill"
        case .fasterWorkoutRecovery: return "bolt.fill"
        case .custom: return "text.bubble.fill"
        }
    }

    var color: Color {
        switch self {
        case .improveSleep: return .indigo
        case .improvePosture: return .orange
        case .standLonger: return .teal
        case .sitWithoutPain: return .blue
        case .workWithEquipment: return .gray
        case .driveWithoutPain: return .red
        case .reduceMorningStiffness: return .yellow
        case .coreAndBalance: return .purple
        case .flexibilityAndMobility: return .pink
        case .manageStress: return .mint
        case .stayActiveAsYouAge: return .green
        case .fasterWorkoutRecovery: return .cyan
        case .custom: return .secondary
        }
    }
}

// MARK: - Goal Selection (used during intake flow)

struct GoalSelection: Identifiable {
    let id: UUID = UUID()
    let category: GoalCategory
    let customDescription: String?

    init(category: GoalCategory, customDescription: String? = nil) {
        self.category = category
        self.customDescription = customDescription
    }
}

// MARK: - Wellness Assessment (parallel to PainAssessment)

struct WellnessAssessment: Codable, Identifiable {

    enum ImpactLevel: String, Codable, CaseIterable {
        case mild, moderate, significant, severe
        var displayName: String {
            switch self {
            case .mild: return "Mild"
            case .moderate: return "Moderate"
            case .significant: return "Significant"
            case .severe: return "Severe"
            }
        }
    }

    enum Duration: String, Codable, CaseIterable {
        case recent, fewWeeks, fewMonths, sixPlusMonths, years, always
        var displayName: String {
            switch self {
            case .recent: return "Just recently"
            case .fewWeeks: return "A few weeks"
            case .fewMonths: return "A few months"
            case .sixPlusMonths: return "6+ months"
            case .years: return "Years"
            case .always: return "As long as I can remember"
            }
        }
    }

    enum TimeOfDay: String, Codable, CaseIterable {
        case morning, afternoon, evening, night, allDay, varies
        var displayName: String {
            switch self {
            case .morning: return "Morning"
            case .afternoon: return "Afternoon"
            case .evening: return "Evening"
            case .night: return "Night"
            case .allDay: return "All day"
            case .varies: return "Varies"
            }
        }
    }

    enum PriorAttempt: String, Codable, CaseIterable {
        case nothing, stretching, exercise, yoga, chiropractor, physicalTherapy, medication, ergonomicChanges, other
        var displayName: String {
            switch self {
            case .nothing: return "Nothing yet"
            case .stretching: return "Stretching"
            case .exercise: return "Exercise"
            case .yoga: return "Yoga / Pilates"
            case .chiropractor: return "Chiropractor"
            case .physicalTherapy: return "Physical Therapy"
            case .medication: return "Medication"
            case .ergonomicChanges: return "Ergonomic changes"
            case .other: return "Other"
            }
        }
    }

    enum CommitmentLevel: String, Codable, CaseIterable {
        case fiveMin, tenMin, fifteenMin, twentyMin, thirtyPlus
        var displayName: String {
            switch self {
            case .fiveMin: return "5 minutes/day"
            case .tenMin: return "10 minutes/day"
            case .fifteenMin: return "15 minutes/day"
            case .twentyMin: return "20 minutes/day"
            case .thirtyPlus: return "30+ minutes/day"
            }
        }
    }

    let id: UUID
    let goalCategory: GoalCategory
    let customGoalText: String?
    let impactLevel: ImpactLevel
    let motivationLevel: Int                 // 1-10
    let duration: Duration
    let timeOfDay: [TimeOfDay]
    let dailyActivitiesAffected: [String]
    let currentHabits: [String]
    let priorAttempts: [PriorAttempt]
    let commitmentLevel: CommitmentLevel
    let specificContext: String?
    let additionalNotes: String?
}
