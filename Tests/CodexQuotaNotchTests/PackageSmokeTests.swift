import XCTest
@testable import CodexQuotaNotch

final class PackageSmokeTests: XCTestCase {
    func testPackageModuleLoads() {
        XCTAssertEqual(CodexQuotaNotchApp.buildIdentifier, "codex-quota-notch")
    }
}
