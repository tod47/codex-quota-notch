import XCTest
@testable import CodexQuotaNotch

final class OverlayPanelControllerTests: XCTestCase {
    func testVisibleFloatingPanelIsNotRepositionedForFrameOnlySettingsUpdate() {
        XCTAssertFalse(
            OverlayPanelUpdatePolicy.shouldShowFloating(
                previousMode: .floating,
                panelIsVisible: true
            )
        )
        XCTAssertTrue(
            OverlayPanelUpdatePolicy.shouldShowFloating(
                previousMode: .floating,
                panelIsVisible: false
            )
        )
        XCTAssertTrue(
            OverlayPanelUpdatePolicy.shouldShowFloating(
                previousMode: .topPopup,
                panelIsVisible: true
            )
        )
    }
}
