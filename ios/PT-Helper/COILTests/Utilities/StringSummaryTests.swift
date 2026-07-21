import XCTest
@testable import COIL

final class StringSummaryTests: XCTestCase {

    func testEmptyString() {
        let result = "".sentencePreview()
        XCTAssertEqual(result.preview, "")
        XCTAssertFalse(result.isTruncated)
    }

    func testWhitespaceOnly() {
        let result = "   \n  \t  ".sentencePreview()
        XCTAssertEqual(result.preview, "")
        XCTAssertFalse(result.isTruncated)
    }

    func testSingleSentence() {
        let input = "This is a single sentence."
        let result = input.sentencePreview()
        XCTAssertEqual(result.preview, input)
        XCTAssertFalse(result.isTruncated)
    }

    func testThreeSentencesNotTruncated() {
        let input = "First sentence. Second sentence. Third sentence."
        let result = input.sentencePreview(maxSentences: 3)
        XCTAssertEqual(result.preview, input)
        XCTAssertFalse(result.isTruncated)
    }

    func testMoreThanMaxSentencesIsTruncated() {
        let input = "One. Two. Three. Four. Five."
        let result = input.sentencePreview(maxSentences: 3)
        XCTAssertTrue(result.isTruncated)
        XCTAssertTrue(result.preview.contains("One"))
        XCTAssertTrue(result.preview.contains("Two"))
        XCTAssertTrue(result.preview.contains("Three"))
        XCTAssertFalse(result.preview.contains("Four"))
    }

    func testCharacterCapForcesFewerSentences() {
        let long = "The patient reports significant pain in the lower back region that radiates down into the left leg and worsens with prolonged sitting or standing for any length of time"
        let input = "\(long). \(long). \(long). Extra sentence here."
        let result = input.sentencePreview(maxSentences: 3, maxCharacters: 300)
        XCTAssertTrue(result.isTruncated)
        XCTAssertLessThanOrEqual(result.preview.count, 300)
    }

    func testNoTerminator() {
        let input = "This text has no terminator at all"
        let result = input.sentencePreview()
        XCTAssertEqual(result.preview, input)
        XCTAssertFalse(result.isTruncated)
    }

    func testAbbreviationsDoNotSplitPrematurely() {
        let input = "Dr. Smith examined the patient. The patient reported pain. Treatment will continue. Follow-up scheduled. Recovery expected."
        let result = input.sentencePreview(maxSentences: 3)
        XCTAssertTrue(result.preview.contains("Dr. Smith"), "Foundation sentence segmenter should keep 'Dr.' attached to its sentence")
        XCTAssertTrue(result.isTruncated)
    }

    func testWhitespaceNormalization() {
        let input = "   First sentence.   Second  sentence.\n\n  Third sentence.  "
        let result = input.sentencePreview(maxSentences: 3)
        XCTAssertFalse(result.preview.hasPrefix(" "))
        XCTAssertFalse(result.preview.hasSuffix(" "))
        XCTAssertFalse(result.preview.contains("  "))
        XCTAssertFalse(result.isTruncated)
    }

    func testMaxSentencesParameterOne() {
        let input = "First. Second. Third."
        let result = input.sentencePreview(maxSentences: 1)
        XCTAssertTrue(result.isTruncated)
        XCTAssertTrue(result.preview.contains("First"))
        XCTAssertFalse(result.preview.contains("Second"))
    }
}
