import SwiftUI

struct DashSessionHistoryList: View {
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @State private var sessionToDelete: WorkoutSession?
    @State private var showDeleteConfirmation = false

    private var recentSessions: [WorkoutSession] {
        Array(workoutVM.sessions.suffix(10).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Recent Sessions")

            if workoutVM.sessions.isEmpty {
                Text("No sessions yet")
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.lg)
            } else {
                ForEach(recentSessions, id: \.id) { session in
                    HStack(spacing: AppSpacing.md) {
                        sessionRow(session)

                        Button {
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.dashDanger.opacity(0.7))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .dashWidget()
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    withAnimation {
                        workoutVM.deleteSession(session)
                    }
                    sessionToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this workout session? This cannot be undone.")
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(painColor(session.painLevel).opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Text("\(Int(session.painLevel))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(painColor(session.painLevel))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.date, style: .date)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.dashTextPrimary)
                Text("\(Int(session.duration / 60)) min")
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
            }

            Spacer()

            if !session.exercisesPerformed.isEmpty {
                Text("\(session.exercisesPerformed.count) exercises")
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
            }
        }
    }

    private func painColor(_ level: Double) -> Color {
        switch Int(level) {
        case 0...3: return AppColors.dashSuccess
        case 4...6: return AppColors.dashWarning
        default: return AppColors.dashDanger
        }
    }
}
