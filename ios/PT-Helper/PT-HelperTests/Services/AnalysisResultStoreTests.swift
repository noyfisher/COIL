import XCTest
@testable import PT_Helper

@MainActor
final class AnalysisResultStoreTests: XCTestCase {
    private let testKey = "dashboardLastAnalysisResult"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testSave_thenLoad_restoresResult() {
        let store = AnalysisResultStore()
        let result = TestFixtures.makeAnalysisResult()

        store.save(result)

        let freshStore = AnalysisResultStore()
        XCTAssertNotNil(freshStore.lastResult, "Loading from a fresh store should restore the saved result")
        XCTAssertEqual(freshStore.lastResult?.id, result.id)
    }

    func testLoad_noData_lastResultIsNil() {
        UserDefaults.standard.removeObject(forKey: testKey)
        let store = AnalysisResultStore()
        XCTAssertNil(store.lastResult, "No stored data should produce nil lastResult")
    }

    func testClear_removesStoredResult() {
        let store = AnalysisResultStore()
        store.save(TestFixtures.makeAnalysisResult())
        XCTAssertNotNil(store.lastResult)

        store.clear()
        XCTAssertNil(store.lastResult)
        XCTAssertNil(UserDefaults.standard.data(forKey: testKey))
    }

    func testSave_overwritesPreviousResult() {
        let store = AnalysisResultStore()
        let first = TestFixtures.makeAnalysisResult()
        let second = TestFixtures.makeAnalysisResult()

        store.save(first)
        store.save(second)

        XCTAssertEqual(store.lastResult?.id, second.id, "Second save should overwrite first")
    }

    func testLoad_corruptData_gracefullyHandled() {
        // Write garbage bytes to the key
        UserDefaults.standard.set(Data([0xFF, 0xFE, 0x00]), forKey: testKey)
        let store = AnalysisResultStore()
        XCTAssertNil(store.lastResult, "Corrupt data should result in nil, not a crash")
    }
}
