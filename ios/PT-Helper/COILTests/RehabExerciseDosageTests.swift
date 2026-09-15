import XCTest
@testable import COIL

final class RehabExerciseDosageTests: XCTestCase {

    private func exercise(sets: Int, reps: String) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: "Wall Sits", targetArea: "Knee", description: "d",
            sets: sets, reps: reps, restSeconds: 30, difficulty: .beginner,
            demonstrationIcon: "figure.cooldown", tips: [], contraindications: []
        )
    }

    func testRepsText_integerReps_appendsReps() {
        XCTAssertEqual(exercise(sets: 3, reps: "12").repsText, "12 reps")
    }

    func testRepsText_singleRep_singular() {
        XCTAssertEqual(exercise(sets: 3, reps: "1").repsText, "1 rep")
    }

    func testRepsText_timedReps_verbatim() {
        XCTAssertEqual(exercise(sets: 3, reps: "30 seconds").repsText, "30 seconds")
    }

    func testRepsText_freeText_verbatim() {
        XCTAssertEqual(exercise(sets: 2, reps: "10 each side").repsText, "10 each side")
    }

    func testRepsText_paddedInteger_trimmed() {
        XCTAssertEqual(exercise(sets: 3, reps: " 15 ").repsText, "15 reps")
    }

    func testDosageText_numeric() {
        XCTAssertEqual(exercise(sets: 3, reps: "12").dosageText, "3 sets \u{00D7} 12 reps")
    }

    func testDosageText_timed() {
        XCTAssertEqual(exercise(sets: 3, reps: "30 seconds").dosageText, "3 sets \u{00D7} 30 seconds")
    }

    func testDosageText_singleSet_singular() {
        XCTAssertEqual(exercise(sets: 1, reps: "12").dosageText, "1 set \u{00D7} 12 reps")
    }

    func testRepsText_rangeReps_appendsReps() {
        XCTAssertEqual(exercise(sets: 3, reps: "10-12").repsText, "10-12 reps")
    }

    func testRepsText_enDashRange_appendsReps() {
        XCTAssertEqual(exercise(sets: 3, reps: "10–12").repsText, "10–12 reps")
    }

    func testRepsText_wordRange_appendsReps() {
        XCTAssertEqual(exercise(sets: 3, reps: "8 to 10").repsText, "8 to 10 reps")
    }

    func testRepsText_negativeInteger_verbatim() {
        XCTAssertEqual(exercise(sets: 3, reps: "-3").repsText, "-3")
    }

    func testDosageText_range() {
        XCTAssertEqual(exercise(sets: 3, reps: "10-12").dosageText, "3 sets \u{00D7} 10-12 reps")
    }
}
