import Foundation
import Combine

/// Manages the state for a guided workout flow: exercise-by-exercise
/// with set tracking, rest timers, and completion summary.
@MainActor
class GuidedWorkoutViewModel: ObservableObject {

    // MARK: - Published State

    @Published var plan: RehabPlan
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1
    @Published var phase: WorkoutPhase = .exercise
    @Published var isTimerRunning: Bool = false
    @Published var timeRemaining: Int = 0
    @Published var totalElapsedTime: TimeInterval = 0
    @Published var completedExercises: [String] = []
    @Published var skippedExercises: [String] = []
    @Published var isPaused: Bool = false

    enum WorkoutPhase: Equatable {
        case exercise
        case rest
        case complete
    }

    // MARK: - Timer

    private var timerSubscription: AnyCancellable?
    private var elapsedSubscription: AnyCancellable?
    private let startTime = Date()

    // MARK: - Computed Properties

    var currentExercise: RehabExercise? {
        guard plan.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return plan.exercises[currentExerciseIndex]
    }

    var totalExercises: Int { plan.exercises.count }

    var progress: Double {
        guard totalExercises > 0 else { return 0 }
        return Double(currentExerciseIndex) / Double(totalExercises)
    }

    var exerciseProgress: String {
        "\(currentExerciseIndex + 1) of \(totalExercises)"
    }

    var formattedElapsedTime: String {
        let minutes = Int(totalElapsedTime) / 60
        let seconds = Int(totalElapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedTimeRemaining: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Init

    init(plan: RehabPlan) {
        self.plan = plan
        startElapsedTimer()
    }

    // MARK: - Actions

    /// Mark the current set as complete. If all sets done, start rest or move to next exercise.
    func completeSet() {
        guard let exercise = currentExercise else { return }

        SessionLogger.shared.logUserAction(.buttonTapped, action: "completeSet",
                                            metadata: ["exercise": exercise.name,
                                                        "set": "\(currentSet)/\(exercise.sets)"])

        if currentSet >= exercise.sets {
            // All sets done for this exercise
            completedExercises.append(exercise.name)

            if currentExerciseIndex < totalExercises - 1 {
                // Start rest before next exercise
                startRestTimer(seconds: exercise.restSeconds)
            } else {
                // Last exercise — workout complete
                finishWorkout()
            }
        } else {
            // More sets to do — brief inter-set rest
            currentSet += 1
            let interSetRest = min(exercise.restSeconds, 60)
            startRestTimer(seconds: interSetRest)
        }
    }

    /// Skip the current exercise entirely
    func skipExercise() {
        guard let exercise = currentExercise else { return }
        SessionLogger.shared.logUserAction(.buttonTapped, action: "skipExercise",
                                            metadata: ["exercise": exercise.name])
        skippedExercises.append(exercise.name)
        moveToNextExercise()
    }

    /// Skip the remaining rest time and go to next exercise
    func skipRest() {
        stopTimer()
        if phase == .rest {
            moveToNextExercise()
        }
    }

    /// Toggle pause state
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            timerSubscription?.cancel()
            timerSubscription = nil
            elapsedSubscription?.cancel()
            elapsedSubscription = nil
        } else {
            if phase == .rest && timeRemaining > 0 {
                resumeRestTimer()
            }
            startElapsedTimer()
        }
    }

    /// Build the final WorkoutSession from the guided workout data
    func buildSession(painLevel: Double, regionPainLevels: [String: Double]?, notes: String?) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            date: Date(),
            duration: totalElapsedTime,
            painLevel: painLevel,
            isCompleted: true,
            exercisesPerformed: completedExercises,
            notes: notes?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : notes,
            regionPainLevels: regionPainLevels?.isEmpty == true ? nil : regionPainLevels,
            planId: plan.id
        )
    }

    // MARK: - Private

    private func moveToNextExercise() {
        stopTimer()
        if currentExerciseIndex < totalExercises - 1 {
            currentExerciseIndex += 1
            currentSet = 1
            phase = .exercise
        } else {
            finishWorkout()
        }
    }

    private func finishWorkout() {
        stopTimer()
        elapsedSubscription?.cancel()
        elapsedSubscription = nil
        phase = .complete

        SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Guided workout completed",
                                  metadata: ["completed": "\(completedExercises.count)",
                                              "skipped": "\(skippedExercises.count)",
                                              "elapsed": formattedElapsedTime])
    }

    private func startRestTimer(seconds: Int) {
        phase = .rest
        timeRemaining = max(seconds, 5)
        isTimerRunning = true

        timerSubscription = Foundation.Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isPaused else { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.stopTimer()
                    self.moveToNextExercise()
                }
            }
    }

    private func resumeRestTimer() {
        guard timeRemaining > 0 else { return }
        isTimerRunning = true
        timerSubscription = Foundation.Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isPaused else { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.stopTimer()
                    self.moveToNextExercise()
                }
            }
    }

    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
        isTimerRunning = false
        timeRemaining = 0
    }

    private func startElapsedTimer() {
        elapsedSubscription = Foundation.Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isPaused else { return }
                self.totalElapsedTime = Date().timeIntervalSince(self.startTime)
            }
    }
}
