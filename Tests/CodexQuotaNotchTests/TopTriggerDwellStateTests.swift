import Foundation
import XCTest
@testable import CodexQuotaNotch

final class TopTriggerDwellStateTests: XCTestCase {
    func testTriggerActivatesOnlyAfterThreeTenthsOfASecond() {
        var state = TopTriggerDwellState()
        let enteredAt = Date(timeIntervalSinceReferenceDate: 10)

        state.enter(at: enteredAt)

        XCTAssertFalse(state.activateIfReady(at: enteredAt.addingTimeInterval(0.299)))
        XCTAssertTrue(state.activateIfReady(at: enteredAt.addingTimeInterval(0.300)))
    }

    func testLeavingTriggerCancelsPendingActivation() {
        var state = TopTriggerDwellState()
        let enteredAt = Date(timeIntervalSinceReferenceDate: 10)

        state.enter(at: enteredAt)
        state.leave()

        XCTAssertFalse(state.activateIfReady(at: enteredAt.addingTimeInterval(1)))
    }
}
