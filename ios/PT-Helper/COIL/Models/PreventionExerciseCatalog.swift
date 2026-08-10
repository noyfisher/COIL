import Foundation

/// One hand-authored catalog template plus the tags `PreventionRoutineEngine`
/// filters/selects on. Every `name` below is a real entry in
/// `Resources/exercise_image_mapping.json` (verified by inspection), so
/// `ExerciseImageView`/`ExerciseImageService` resolve real illustrations with
/// zero new image-resolution code.
struct PreventionCatalogEntry {
    let template: PreventionExercise
    /// Empty = suitable for any focus.
    let suitableFocuses: Set<PreventionFocus>
    /// Empty = suitable for any context.
    let suitableContexts: Set<DailyContext>
    /// Safe for recovery days / post-"too much" regression — gentle, low load.
    let isGentle: Bool
    /// Floor/lying/quadruped work — excluded when the day's context is `.commute`.
    let requiresSpace: Bool
}

enum PreventionExerciseCatalog {

    // MARK: - Essential pool

    static let allEntries: [PreventionCatalogEntry] = mobilityControlEntries
        + strengthCapacityEntries
        + balanceEntries
        + recoveryHabitEntries

    // MARK: - Micro-actions (separate small pool, ~1 minute, one per context)

    static let microActions: [PreventionCatalogEntry] = [
        entry(
            name: "Seated Posture Micro-Practice", catalogKey: "seated-posture-micro-practice-throughout-day-habit",
            targetArea: "Core", description: "A quick reset to undo desk slouch — a few seconds, done often.",
            durationSeconds: 45, difficulty: .beginner, icon: "figure.stand",
            tips: ["Set a recurring reminder for the rest of the day.", "Chin gently level, not tucked or tilted."],
            start: "Sit tall, feet flat on the floor.",
            movement: "Draw your shoulder blades back and down, lift through the crown of your head.",
            end: "Hold for a few breaths, then relax and repeat.",
            exerciseCategory: "mobility",
            category: .mobilityControl, isMicroAction: true,
            focuses: [.deskComfort], contexts: [.deskHeavy], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Standing Hip Flexor March", catalogKey: "standing-hip-flexor-march",
            targetArea: "Hip", description: "A brief dynamic warm-up to wake up the hips before training.",
            reps: "10 per side", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.run",
            tips: ["Keep your torso tall.", "Controlled tempo — this is a warm-up, not a max effort."],
            start: "Stand tall holding onto a wall or chair if needed.",
            movement: "March in place, driving each knee up toward hip height.",
            end: "Lower with control and repeat on the other side.",
            exerciseCategory: "mobility",
            category: .strengthCapacity, isMicroAction: true,
            focuses: [.workoutResilience], contexts: [.activeDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Deep Abdominal Breathing", catalogKey: "deep-abdominal-breathing-micro",
            targetArea: "Core", description: "Slow diaphragmatic breathing to downshift before or after activity.",
            durationSeconds: 60, difficulty: .beginner, icon: "wind",
            tips: ["Breathe in through the nose, out through the mouth.", "Let your belly rise, shoulders stay relaxed."],
            start: "Sit or lie comfortably with one hand on your belly.",
            movement: "Inhale slowly for 4 counts, feeling your belly rise; exhale for 6 counts.",
            end: "Repeat for about a minute, keeping the exhale longer than the inhale.",
            exerciseCategory: "mobility",
            category: .recoveryHabits, isMicroAction: true,
            focuses: [], contexts: [.recoveryDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Seated Shoulder Rolls", catalogKey: "seated-shoulder-rolls",
            targetArea: "Shoulder", description: "A quick reset for stiff shoulders on a long drive or commute.",
            reps: "10", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Move slowly and through a full circle.", "Keep breathing normally throughout."],
            start: "Sit tall, arms relaxed at your sides.",
            movement: "Roll both shoulders up, back, and down in a slow circle.",
            end: "Reverse direction for the second half of the reps.",
            exerciseCategory: "mobility",
            category: .mobilityControl, isMicroAction: true,
            focuses: [], contexts: [.commute], isGentle: true, requiresSpace: false
        )
    ]

    // MARK: - Mobility & Control

    private static let mobilityControlEntries: [PreventionCatalogEntry] = [
        entry(
            name: "Chin Tucks", catalogKey: "chin-tucks",
            targetArea: "Neck", description: "Restores neck alignment strained by forward head posture at a screen.",
            reps: "10", sets: 2, restSeconds: 20, difficulty: .beginner, icon: "figure.stand",
            tips: ["Keep eyes level — this is a glide, not a nod.", "Stop if you feel dizziness."],
            start: "Sit or stand tall, looking straight ahead.",
            movement: "Draw your chin straight back, creating a slight double chin, without tilting.",
            end: "Hold 2 seconds, then release back to neutral.",
            exerciseCategory: "strength",
            category: .mobilityControl,
            focuses: [.deskComfort, .mobility], contexts: [.deskHeavy, .commute], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Seated Cat-Cow Stretch", catalogKey: "seated-cat-cow-stretch",
            targetArea: "Back", description: "Loosens a stiff spine without needing to get on the floor.",
            reps: "8", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Move with your breath — arch on inhale, round on exhale.", "Keep the motion slow and controlled."],
            start: "Sit toward the front of a chair, hands on your knees.",
            movement: "Inhale, arch your back and lift your chest (cow); exhale, round your spine (cat).",
            end: "Return to neutral and repeat.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.deskComfort, .mobility], contexts: [.deskHeavy, .recoveryDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Doorway Pectoral Stretch", catalogKey: "doorway-pectoral-stretch",
            targetArea: "Shoulder", description: "Opens up chest and shoulders rounded forward from desk work.",
            durationSeconds: 30, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Stop short of any pinching in the shoulder.", "Keep your core gently braced."],
            start: "Stand in a doorway, forearm against the frame, elbow near shoulder height.",
            movement: "Step forward gently until you feel a stretch across your chest.",
            end: "Hold, breathing normally, then switch sides.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.deskComfort], contexts: [.deskHeavy], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Seated Thoracic Rotation", catalogKey: "seated-thoracic-rotation",
            targetArea: "Back", description: "Restores mid-back rotation that stiffens up during long sitting.",
            reps: "8 per side", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Rotate from your ribcage, not just your arms.", "Keep hips facing forward."],
            start: "Sit tall, arms crossed over your chest.",
            movement: "Rotate your upper back to one side as far as comfortable.",
            end: "Return to center and rotate to the other side.",
            exerciseCategory: "mobility",
            category: .mobilityControl,
            focuses: [.deskComfort, .mobility], contexts: [.deskHeavy, .commute], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Standing Hip Flexor Stretch", catalogKey: "standing-hip-flexor-stretch",
            targetArea: "Hip", description: "Releases tight hip flexors from hours of sitting.",
            durationSeconds: 30, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Keep your pelvis tucked slightly under.", "Hold onto a wall or chair for balance."],
            start: "Step one foot forward into a half-kneeling or split stance.",
            movement: "Shift your weight forward, keeping your torso upright, until you feel a stretch in the back hip.",
            end: "Hold, then switch sides.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.deskComfort, .mobility], contexts: [.deskHeavy, .activeDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Shoulder Rolls", catalogKey: "shoulder-rolls",
            targetArea: "Shoulder", description: "Simple mobility to loosen the shoulders before or after sitting or training.",
            reps: "10", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Full range — up, back, and down.", "Keep the movement slow."],
            start: "Stand or sit tall, arms relaxed.",
            movement: "Roll both shoulders in a slow, full circle.",
            end: "Reverse direction halfway through.",
            exerciseCategory: "mobility",
            category: .mobilityControl,
            focuses: [.deskComfort, .workoutResilience], contexts: [], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Gentle Neck Stretches", catalogKey: "gentle-neck-stretches",
            targetArea: "Neck", description: "Eases neck tension without aggressive stretching.",
            durationSeconds: 30, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Let gravity do the work — don't pull with your hand.", "Stop if you feel numbness or tingling."],
            start: "Sit tall, one hand resting gently on top of your head.",
            movement: "Let your ear drift toward your shoulder until you feel a light stretch.",
            end: "Hold, breathing normally, then switch sides.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.deskComfort], contexts: [.deskHeavy, .commute], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Seated Spinal Twist", catalogKey: "seated-spinal-twist",
            targetArea: "Spine", description: "A gentle rotational reset for a stiff low and mid back.",
            durationSeconds: 20, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Twist from your torso, not by yanking your knee.", "Keep your spine tall, not slumped."],
            start: "Sit tall on a chair or the floor.",
            movement: "Place one hand behind you and gently rotate your torso toward that side.",
            end: "Hold, then repeat on the other side.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.deskComfort, .mobility], contexts: [.deskHeavy, .commute], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Ankle Circles", catalogKey: "ankle-circles",
            targetArea: "Ankle", description: "Keeps ankle joints mobile — a foundation for balance and gait.",
            reps: "10 per side", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Move slowly through the full circle.", "Keep the rest of your leg still."],
            start: "Sit with one leg extended or crossed over the other knee.",
            movement: "Rotate your ankle in a slow circle.",
            end: "Reverse direction, then switch feet.",
            exerciseCategory: "mobility",
            category: .mobilityControl,
            focuses: [.mobility, .balance, .returnToActivity], contexts: [], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Wrist Extension Stretch", catalogKey: "wrist-extension-stretch",
            targetArea: "Wrist", description: "Relieves wrist tightness from typing and mousing.",
            durationSeconds: 20, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Keep your elbow straight but not locked.", "Ease off if you feel sharp pain."],
            start: "Extend one arm forward, palm up.",
            movement: "Use your other hand to gently pull the fingers back toward you.",
            end: "Hold, then switch hands.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.deskComfort], contexts: [.deskHeavy], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Child's Pose", catalogKey: "childs-pose",
            targetArea: "Lower Back", description: "A gentle full-body decompression stretch — a good recovery-day default.",
            durationSeconds: 45, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Breathe into your lower back as you relax forward.", "Widen your knees if it's more comfortable."],
            start: "Kneel on the floor, big toes touching, knees apart.",
            movement: "Sit back toward your heels and reach your arms forward, lowering your chest.",
            end: "Hold, breathing slowly, then rise back up.",
            exerciseCategory: "stretch",
            category: .mobilityControl,
            focuses: [.mobility, .returnToActivity], contexts: [.recoveryDay], isGentle: true, requiresSpace: true
        )
    ]

    // MARK: - Strength & Capacity

    private static let strengthCapacityEntries: [PreventionCatalogEntry] = [
        entry(
            name: "Glute Bridge", catalogKey: "glute-bridge",
            targetArea: "Hip", description: "Builds hip and low-back capacity to buffer sitting and training load.",
            reps: "12", sets: 2, restSeconds: 30, difficulty: .beginner, icon: "figure.core.training",
            tips: ["Squeeze your glutes at the top.", "Avoid over-arching your lower back."],
            start: "Lie on your back, knees bent, feet flat on the floor.",
            movement: "Press through your heels and lift your hips until your body forms a straight line.",
            end: "Lower with control and repeat.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.healthyAging, .workoutResilience, .returnToActivity], contexts: [.activeDay], isGentle: false, requiresSpace: true
        ),
        entry(
            name: "Wall Sits", catalogKey: "wall-sits",
            targetArea: "Knee", description: "Builds quad and knee capacity that protects the joint during activity.",
            durationSeconds: 30, difficulty: .intermediate, icon: "figure.strengthtraining.traditional",
            tips: ["Keep knees tracking over your toes, not caving in.", "Ease up if you feel sharp knee pain."],
            start: "Stand with your back against a wall, feet shoulder-width apart.",
            movement: "Slide down until your knees are bent to a comfortable angle.",
            end: "Hold, then slide back up to stand.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.healthyAging, .workoutResilience], contexts: [.activeDay], isGentle: false, requiresSpace: false
        ),
        entry(
            name: "Clamshells", catalogKey: "clamshells",
            targetArea: "Hip", description: "Strengthens the hip stabilizers that protect the knee and low back.",
            reps: "12 per side", sets: 2, restSeconds: 20, difficulty: .beginner, icon: "figure.core.training",
            tips: ["Keep your hips stacked — don't roll backward.", "Move slowly, no momentum."],
            start: "Lie on your side, knees bent, hips stacked, feet together.",
            movement: "Keeping feet touching, lift your top knee like an opening clamshell.",
            end: "Lower with control and repeat, then switch sides.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.healthyAging, .returnToActivity], contexts: [.activeDay, .recoveryDay], isGentle: true, requiresSpace: true
        ),
        entry(
            name: "Quad Sets", catalogKey: "quad-sets",
            targetArea: "Knee", description: "A gentle isometric to keep the quad active without loading the knee joint.",
            reps: "10", sets: 2, restSeconds: 15, difficulty: .beginner, icon: "figure.core.training",
            tips: ["This is a squeeze, not a big movement.", "Breathe normally throughout the hold."],
            start: "Sit or lie with your leg out straight.",
            movement: "Tighten the muscle on top of your thigh, pressing the back of your knee down.",
            end: "Hold 5 seconds, then release and repeat.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.returnToActivity, .healthyAging], contexts: [.recoveryDay, .activeDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Bird Dog", catalogKey: "bird-dog",
            targetArea: "Core/Back", description: "Trains core stability and coordination that supports the whole kinetic chain.",
            reps: "8 per side", sets: 2, restSeconds: 20, difficulty: .beginner, icon: "figure.core.training",
            tips: ["Keep your hips level — avoid rotating.", "Move slowly and with control."],
            start: "Start on hands and knees, spine neutral.",
            movement: "Extend one arm and the opposite leg until they're in line with your torso.",
            end: "Hold briefly, return with control, then switch sides.",
            exerciseCategory: "core",
            category: .strengthCapacity,
            focuses: [.healthyAging, .balance, .workoutResilience], contexts: [.activeDay], isGentle: false, requiresSpace: true
        ),
        entry(
            name: "Shoulder Blade Squeeze", catalogKey: "shoulder-blade-squeeze",
            targetArea: "Shoulder", description: "Counters rounded-forward posture by strengthening the upper back.",
            reps: "12", sets: 2, restSeconds: 15, difficulty: .beginner, icon: "figure.strengthtraining.traditional",
            tips: ["Squeeze your shoulder blades together and down.", "Keep your shoulders away from your ears."],
            start: "Sit or stand tall, arms relaxed at your sides.",
            movement: "Squeeze your shoulder blades toward each other.",
            end: "Hold 2 seconds, then release and repeat.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.deskComfort, .workoutResilience], contexts: [.deskHeavy, .activeDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Calf Raises", catalogKey: "calf-raises",
            targetArea: "Ankle", description: "Builds calf and ankle capacity that supports balance and gait.",
            reps: "15", sets: 2, restSeconds: 20, difficulty: .beginner, icon: "figure.strengthtraining.traditional",
            tips: ["Rise up under control — don't bounce.", "Hold a wall or chair if you need support."],
            start: "Stand with feet hip-width apart, near a wall or chair for support.",
            movement: "Rise up onto your toes as high as comfortable.",
            end: "Lower with control and repeat.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.healthyAging, .balance, .workoutResilience], contexts: [.activeDay], isGentle: false, requiresSpace: false
        ),
        entry(
            name: "Side Plank", catalogKey: "side-plank",
            targetArea: "Core/Obliques", description: "Builds lateral core strength that supports the spine under load.",
            durationSeconds: 20, difficulty: .intermediate, icon: "figure.core.training",
            tips: ["Keep your body in one straight line.", "Drop to your knee for an easier version."],
            start: "Lie on your side, propped on your forearm, legs stacked.",
            movement: "Lift your hips until your body forms a straight line.",
            end: "Hold, then lower with control and switch sides.",
            exerciseCategory: "core",
            category: .strengthCapacity,
            focuses: [.workoutResilience, .healthyAging], contexts: [.activeDay], isGentle: false, requiresSpace: true
        ),
        entry(
            name: "Prone Cobra", catalogKey: "prone-cobra",
            targetArea: "Back", description: "Strengthens the upper back muscles that counteract a forward-slumped posture.",
            reps: "10", sets: 2, restSeconds: 20, difficulty: .beginner, icon: "figure.core.training",
            tips: ["Lead with your chest, not your chin.", "Keep the lift small and controlled."],
            start: "Lie face down, arms at your sides, palms down.",
            movement: "Lift your chest and arms slightly off the floor, squeezing your shoulder blades together.",
            end: "Lower with control and repeat.",
            exerciseCategory: "strength",
            category: .strengthCapacity,
            focuses: [.deskComfort, .workoutResilience], contexts: [.activeDay], isGentle: true, requiresSpace: true
        )
    ]

    // MARK: - Balance

    private static let balanceEntries: [PreventionCatalogEntry] = [
        entry(
            name: "Single Leg Balance", catalogKey: "single-leg-balance",
            targetArea: "Ankle/Knee", description: "Trains the small stabilizing muscles that prevent stumbles.",
            durationSeconds: 20, difficulty: .beginner, icon: "figure.stand",
            tips: ["Stand near a wall or counter for support if needed.", "Keep a soft bend in your standing knee."],
            start: "Stand tall next to a wall or sturdy chair.",
            movement: "Lift one foot slightly off the floor and hold your balance.",
            end: "Lower with control, then switch legs.",
            exerciseCategory: "balance",
            category: .balance,
            focuses: [.balance, .healthyAging], contexts: [], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Heel-Toe Taps", catalogKey: "heel-toe-taps",
            targetArea: "Ankle", description: "Builds ankle control and coordination for steadier footing.",
            reps: "10 per side", sets: 1, restSeconds: 0, difficulty: .beginner, icon: "figure.stand",
            tips: ["Move with control, not speed.", "Hold onto support if you feel unsteady."],
            start: "Stand tall, hands free or lightly resting on a chair.",
            movement: "Tap your heel forward, then your toe backward, shifting weight through your standing leg.",
            end: "Repeat, then switch feet.",
            exerciseCategory: "balance",
            category: .balance,
            focuses: [.balance, .healthyAging], contexts: [.deskHeavy, .activeDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Marching in Place", catalogKey: "marching-in-place",
            targetArea: "Full Body", description: "A gentle full-body warm-up that also builds balance and coordination.",
            durationSeconds: 30, difficulty: .beginner, icon: "figure.walk",
            tips: ["Keep a steady, comfortable pace.", "Swing your arms naturally."],
            start: "Stand tall with good posture.",
            movement: "March in place, lifting your knees to a comfortable height.",
            end: "Continue at a steady pace, then slow to a stop.",
            exerciseCategory: "cardio",
            category: .balance,
            focuses: [.balance, .workoutResilience, .healthyAging], contexts: [.activeDay], isGentle: true, requiresSpace: false
        )
    ]

    // MARK: - Recovery Habits

    private static let recoveryHabitEntries: [PreventionCatalogEntry] = [
        entry(
            name: "Deep Abdominal Breathing", catalogKey: "deep-abdominal-breathing",
            targetArea: "Core", description: "Downshifts the nervous system and supports recovery between hard days.",
            durationSeconds: 90, difficulty: .beginner, icon: "wind",
            tips: ["Longer exhale than inhale helps you relax.", "Let your shoulders stay soft and low."],
            start: "Lie on your back or sit comfortably, one hand on your belly.",
            movement: "Inhale slowly through your nose for 4 counts, feeling your belly rise.",
            end: "Exhale slowly for 6 counts, and repeat.",
            exerciseCategory: "mobility",
            category: .recoveryHabits,
            focuses: [], contexts: [.recoveryDay], isGentle: true, requiresSpace: false
        ),
        entry(
            name: "Supported Child's Pose", catalogKey: "supported-childs-pose",
            targetArea: "Back", description: "A restful, fully supported stretch for a low-key recovery day.",
            durationSeconds: 60, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Use a pillow under your chest or hips if that's more comfortable.", "Breathe slowly and let go of tension."],
            start: "Kneel on the floor, big toes touching, knees apart.",
            movement: "Sit back toward your heels and rest your chest down, arms relaxed forward or at your sides.",
            end: "Stay here, breathing slowly, then rise gently.",
            exerciseCategory: "stretch",
            category: .recoveryHabits,
            focuses: [.returnToActivity], contexts: [.recoveryDay], isGentle: true, requiresSpace: true
        ),
        entry(
            name: "Hamstring Stretch", catalogKey: "hamstring-stretch",
            targetArea: "Hamstrings", description: "Gentle hamstring release — easy on the joints, good for an off day.",
            durationSeconds: 30, difficulty: .beginner, icon: "figure.flexibility",
            tips: ["Keep a slight bend in your knee, don't lock it.", "Stretch to mild tension, never pain."],
            start: "Sit on the edge of a chair, one leg extended with heel on the floor.",
            movement: "Hinge forward gently from your hips, keeping your back flat.",
            end: "Hold, then switch legs.",
            exerciseCategory: "stretch",
            category: .recoveryHabits,
            focuses: [.returnToActivity, .mobility], contexts: [.recoveryDay], isGentle: true, requiresSpace: false
        )
    ]

    // MARK: - Factory

    private static func entry(
        name: String, catalogKey: String, targetArea: String, description: String,
        reps: String = "1", sets: Int = 1, restSeconds: Int = 0,
        durationSeconds: Int? = nil,
        difficulty: RehabExercise.Difficulty, icon: String,
        tips: [String], start: String, movement: String, end: String,
        exerciseCategory: String,
        category: PreventionCategory, isMicroAction: Bool = false,
        focuses: Set<PreventionFocus>, contexts: Set<DailyContext>,
        isGentle: Bool, requiresSpace: Bool
    ) -> PreventionCatalogEntry {
        let exercise = RehabExercise(
            id: UUID(),
            name: name,
            targetArea: targetArea,
            description: description,
            sets: sets,
            reps: durationSeconds != nil ? "\(durationSeconds!) sec hold" : reps,
            restSeconds: restSeconds,
            difficulty: difficulty,
            demonstrationIcon: icon,
            tips: tips,
            contraindications: ["Stop if you feel sharp or worsening pain."],
            startPosition: start,
            movement: movement,
            endPosition: end,
            exerciseCategory: exerciseCategory
        )
        let prevention = PreventionExercise(
            exercise: exercise, category: category, isMicroAction: isMicroAction,
            durationSeconds: durationSeconds, catalogKey: catalogKey
        )
        return PreventionCatalogEntry(
            template: prevention, suitableFocuses: focuses, suitableContexts: contexts,
            isGentle: isGentle, requiresSpace: requiresSpace
        )
    }
}
