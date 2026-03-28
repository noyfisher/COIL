import SwiftUI

struct TimerView: View {
    @ObservedObject var viewModel: TimerViewModel
    var accentColor: Color = AppColors.accent

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            // Circular progress ring with time display
            ZStack {
                // Background ring
                Circle()
                    .stroke(accentColor.opacity(0.12), lineWidth: 10)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(AppAnimations.smooth, value: progress)

                // Time display
                VStack(spacing: AppSpacing.xs) {
                    Text(viewModel.timeString)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)

                    Text(statusText)
                        .font(AppFonts.badge)
                        .foregroundColor(statusColor)
                        .textCase(.uppercase)
                }
            }
            .frame(width: 180, height: 180)

            // Control buttons
            HStack(spacing: AppSpacing.xxl) {
                // Reset button
                controlButton(
                    icon: "arrow.counterclockwise",
                    color: AppColors.secondaryText,
                    action: { viewModel.reset() },
                    disabled: !viewModel.timer.isRunning && viewModel.timer.timeRemaining == viewModel.timer.duration
                )

                // Play/Pause button (larger)
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    if viewModel.timer.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }) {
                    Image(systemName: viewModel.timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            Circle()
                                .fill(accentColor)
                        )
                        .shadow(color: accentColor.opacity(0.3), radius: 8, y: 4)
                }
                .scaleEffect(viewModel.timer.isRunning ? 1.0 : 1.05)
                .animation(AppAnimations.springy, value: viewModel.timer.isRunning)

                // Stop button
                controlButton(
                    icon: "stop.fill",
                    color: AppColors.danger,
                    action: {
                        viewModel.stop()
                        viewModel.reset()
                    },
                    disabled: !viewModel.timer.isRunning && viewModel.timer.timeRemaining == viewModel.timer.duration
                )
            }
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Computed

    private var progress: CGFloat {
        guard viewModel.timer.duration > 0 else { return 0 }
        return CGFloat(viewModel.timer.duration - viewModel.timer.timeRemaining) / CGFloat(viewModel.timer.duration)
    }

    private var ringGradient: LinearGradient {
        if viewModel.timer.isRunning {
            return LinearGradient(
                colors: [accentColor, accentColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if viewModel.timer.timeRemaining < viewModel.timer.duration {
            // Paused
            return LinearGradient(
                colors: [AppColors.success, AppColors.success.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Reset/idle
            return LinearGradient(
                colors: [AppColors.mutedText, AppColors.mutedText.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var statusText: String {
        if viewModel.timer.isRunning {
            return "Running"
        } else if viewModel.timer.timeRemaining < viewModel.timer.duration {
            return "Paused"
        } else if viewModel.timer.timeRemaining == 0 {
            return "Done"
        } else {
            return "Ready"
        }
    }

    private var statusColor: Color {
        if viewModel.timer.isRunning {
            return accentColor
        } else if viewModel.timer.timeRemaining < viewModel.timer.duration {
            return AppColors.success
        } else {
            return AppColors.secondaryText
        }
    }

    private func controlButton(icon: String, color: Color, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(disabled ? AppColors.mutedText.opacity(0.4) : color)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(disabled ? AppColors.mutedText.opacity(0.08) : color.opacity(0.12))
                )
        }
        .disabled(disabled)
        .scaleEffect(disabled ? 0.95 : 1.0)
        .animation(AppAnimations.smooth, value: disabled)
    }
}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        TimerView(viewModel: TimerViewModel())
    }
}
