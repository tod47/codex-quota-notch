import AppKit
import XCTest
@testable import CodexQuotaNotch

final class MenuBarInteractionTests: XCTestCase {
    func testPrimaryClickOpensSettings() {
        XCTAssertEqual(MenuBarClickPolicy.action(for: .leftMouseUp), .openSettings)
    }

    func testSecondaryClickShowsContextMenu() {
        XCTAssertEqual(MenuBarClickPolicy.action(for: .rightMouseUp), .showMenu)
    }
}
