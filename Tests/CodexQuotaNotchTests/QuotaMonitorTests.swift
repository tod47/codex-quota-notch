import XCTest
@testable import CodexQuotaNotch

final class QuotaMonitorTests: XCTestCase {
    func testRefreshGateCoalescesRequestsUntilTheRefreshCompletes() {
        var gate = RefreshGate()

        XCTAssertTrue(gate.request())
        XCTAssertFalse(gate.request())

        gate.complete()

        XCTAssertTrue(gate.request())
    }
}
