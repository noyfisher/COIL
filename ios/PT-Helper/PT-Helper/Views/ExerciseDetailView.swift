import SwiftUI

struct ExerciseDetailView: View {
    let exercise: RehabExercise

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    demonstrationIcon
                    positionGuide
                    exerciseInfo
                    formTips
                    contraindications
                    if exercise.reps.contains("seconds") {
                        timerView
                    }
                }
                .padding(AppSpacing.xl)
            }
        }
        .trackScreen("ExerciseDetail")
    }

    private var demonstrationIcon: some View {
        ExerciseImagePagerView(exercise: exercise)
    }

    private var positionGuide: some View {
        Group {
            if exercise.startPosition != nil || exercise.movement != nil || exercise.endPosition != nil {
                CardSection(icon: "figure.walk.motion", color: AppColors.accent, title: "How to Do It") {
                    ExercisePositionGuideView(
                        startPosition: exercise.startPosition,
                        movement: exercise.movement,
                        endPosition: exercise.endPosition
                    )
                }
            }
        }
    }

    private var exerciseInfo: some View {
        CardSection(icon: "info.circle", color: AppColors.accent, title: exercise.name) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Target Area: \(exercise.targetArea)")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
                Text(exercise.description)
                    .font(.body)
                    .foregroundColor(AppColors.primaryText)
                HStack {
                    Text("Sets: \(exercise.sets)")
                    Text("Reps: \(exercise.reps)")
                    Text("Rest: \(exercise.restSeconds) sec")
                }
                .font(AppFonts.caption)
                .foregroundColor(AppColors.secondaryText)
            }
        }
    }

    private var formTips: some View {
        CardSection(icon: "lightbulb", color: AppColors.warning, title: "Form Tips") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(exercise.tips, id: \.self) { tip in
                    Text("- \(tip)")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }

    private var contraindications: some View {
        CardSection(icon: "exclamationmark.triangle", color: AppColors.danger, title: "Contraindications") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(exercise.contraindications, id: \.self) { contraindication in
                    Text("- \(contraindication)")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }

    private var timerView: some View {
        CardSection(icon: "timer", color: AppColors.accent, title: "Timer") {
            Text("\(exercise.reps) remaining")
                .font(.system(.title2, design: .serif))
                .foregroundColor(AppColors.primaryText)
        }
    }
}
