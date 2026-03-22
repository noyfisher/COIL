import Foundation
import Combine

/// Manages the state for a guided workout flow: exercise-by-exercise
/// with set tracking, rest timers, and completion summary.
@MainActor
class GuidedWorkoutViewModel: ObservableObject {

    // MARK: - Checkpoint Keys

    private static let checkpointKey = "GuidedWorkoutCheckpoint"

    struct WorkoutCheckpoint: Codable {
        let planId: String
        let currentExerciseIndex: Int
        let currentSet: Int
        let completedExercises: [String]
        let skippedExercises: [String]
        let substitutedExercises: [String: String]
        let accumulatedTime: TimeInterval
        let savedAt: Date
    }

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
    @Published var substitutedExercises: [String: String] = [:] // original name → new name

    enum WorkoutPhase: Equatable {
        case exercise
        case rest
        case complete
    }

    // MARK: - Timer

    private var timerSubscription: AnyCancellable?
    private var elapsedSubscription: AnyCancellable?
    /// Accumulated elapsed time from completed (pre-pause) segments.
    private var accumulatedTime: TimeInterval = 0
    /// Reference point for the current active segment (reset on each resume).
    private var lastResumeTime = Date()

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
            saveCheckpoint()

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
            saveCheckpoint()
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
        saveCheckpoint()
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
            // Save elapsed time from the current active segment before pausing
            accumulatedTime += Date().timeIntervalSince(lastResumeTime)
            timerSubscription?.cancel()
            timerSubscription = nil
            elapsedSubscription?.cancel()
            elapsedSubscription = nil
        } else {
            // Reset reference point so the next segment starts fresh
            lastResumeTime = Date()
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

    /// End the workout early, marking remaining exercises as skipped.
    func endWorkoutEarly() {
        // Mark all remaining exercises (including current) as skipped
        for i in currentExerciseIndex..<totalExercises {
            let name = plan.exercises[i].name
            if !completedExercises.contains(name) && !skippedExercises.contains(name) {
                skippedExercises.append(name)
            }
        }
        SessionLogger.shared.logUserAction(.buttonTapped, action: "endWorkoutEarly",
                                            metadata: ["completed": "\(completedExercises.count)",
                                                        "skipped": "\(skippedExercises.count)"])
        finishWorkout()
    }

    /// Replace the current exercise with a substitute, updating the plan in-place.
    func swapCurrentExercise(with substitute: RehabExercise, updatedPlan: RehabPlan) {
        let originalName = currentExercise?.name ?? "Unknown"
        self.plan = updatedPlan
        substitutedExercises[originalName] = substitute.name
        // Reset set counter since this is a new exercise
        currentSet = 1
    }

    // MARK: - Checkpointing

    /// Save current workout state so it can be resumed after a crash or interruption.
    func saveCheckpoint() {
        let checkpoint = WorkoutCheckpoint(
            planId: plan.id.uuidString,
            currentExerciseIndex: currentExerciseIndex,
            currentSet: currentSet,
            completedExercises: completedExercises,
            skippedExercises: skippedExercises,
            substitutedExercises: substitutedExercises,
            accumulatedTime: isPaused ? accumulatedTime : accumulatedTime + Date().timeIntervalSince(lastResumeTime),
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(checkpoint) {
            UserDefaults.standard.set(data, forKey: Self.checkpointKey)
        }
    }

    /// Clear saved checkpoint (called on workout completion or discard).
    func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey)
    }

    /// Check if a saved checkpoint exists for the given plan.
    static func savedCheckpoint(forPlanId planId: String) -> WorkoutCheckpoint? {
        guard let data = UserDefaults.standard.data(forKey: checkpointKey),
              let checkpoint = try? JSONDecoder().decode(WorkoutCheckpoint.self, from: data),
              checkpoint.planId == planId,
              // Discard checkpoints older than 24 hours
              Date().timeIntervalSince(checkpoint.savedAt) < 86400 else {
            return nil
        }
        return checkpoint
    }

    /// Restore state from a checkpoint.
    func restoreFromCheckpoint(_ checkpoint: WorkoutCheckpoint) {
        currentExerciseIndex = min(checkpoint.currentExerciseIndex, totalExercises - 1)
        currentSet = checkpoint.currentSet
        completedExercises = checkpoint.completedExercises
        skippedExercises = checkpoint.skippedExercises
        substitutedExercises = checkpoint.substitutedExercises
        accumulatedTime = checkpoint.accumulatedTime
        totalElapsedTime = accumulatedTime
        lastResumeTime = Date()
        phase = .exercise
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
        // Capture final elapsed time before stopping timers
        if !isPaused {
            accumulatedTime += Date().timeIntervalSince(lastResumeTime)
        }
        totalElapsedTime = accumulatedTime
        stopTimer()
        elapsedSubscription?.cancel()
        elapsedSubscription = nil
        clearCheckpoint()
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
                self.totalElapsedTime = self.accumulatedTime + Date().timeIntervalSince(self.lastResumeTime)
            }
    }
}
