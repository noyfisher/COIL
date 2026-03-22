import SwiftUI

struct DashExercisePerformanceTable: View {
    let sessions: [WorkoutSession]

    private var exerciseStats: [(name: String, count: Int, lastDate: Date)] {
        var counts: [String: Int] = [:]
        var lastDates: [String: Date] = [:]

        for session in sessions {
            for exercise in session.exercisesPerformed {
                counts[exercise, default: 0] += 1
                if let existing = lastDates[exercise] {
                    if session.date > existing { lastDates[exercise] = session.date }
                } else {
                    lastDates[exercise] = session.date
                }
            }
        }

        return counts.map { (name: $0.key, count: $0.value, lastDate: lastDates[$0.key] ?? Date()) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Exercise History")

            if exerciseStats.isEmpty {
                Text("Complete workouts to see stats")
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.lg)
            } else {
                // Header row
                HStack {
                    Text("EXERCISE")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("DONE")
                        .frame(width: 44, alignment: .center)
                    Text("LAST")
                        .frame(width: 60, alignment: .trailing)
                }
                .font(AppFonts.dashLabel)
                .foregroundColor(AppColors.dashTextSecondary)
                .tracking(0.5)

                ForEach(exerciseStats.prefix(8), id: \.name) { stat in
                    HStack {
                        Text(stat.name)
                            .font(.caption)
                            .foregroundColor(AppColors.dashTextPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(stat.count)x")
                            .font(AppFonts.dataSmall)
                            .foregroundColor(AppColors.dashAccent)
                            .frame(width: 44, alignment: .center)

                        Text(stat.lastDate, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundColor(AppColors.dashTextSecondary)
                            .frame(width: 60, alignment: .trailing)
                    }

                    Divider().background(AppColors.dashBorder)
                }
            }
        }
        .dashWidget()
    }
}
