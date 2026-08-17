# Codex Quota Notch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and package a native macOS 13+ menu-bar app that reads local Codex session logs, displays the seven-day quota at the top-center/notch area, sends configurable alerts, and is ready for public GitHub release.

**Architecture:** A Swift Package executable target will host an AppKit application whose data, alert, and aggregation layers are pure Swift and testable without a window server. SwiftUI will render the main window and quota cards; AppKit will own the status item, global mouse trigger, non-activating top overlay, persistent overlay, and draggable/resizable floating panel. A build script will assemble the SwiftPM executable and resources into a `.app` bundle for direct GitHub distribution.

**Tech Stack:** Swift 6.3, SwiftPM, SwiftUI, AppKit, UserNotifications, ServiceManagement, XCTest, macOS 13 deployment target, no third-party dependencies.

## Global Constraints

- Target macOS 13 Ventura and newer.
- Read Codex data locally from `~/.codex/sessions` by default; allow a user-selected local directory.
- Select only the seven-day limit with `window_minutes == 10080` for weekly quota alerts.
- Display remaining percentage as `floor(clamp(100 - usedPercent, 0, 100))`.
- Do not upload or persist prompt text, response text, tool calls, API keys, or raw session contents.
- Default appearance follows macOS; manual light/dark modes remain available.
- Default display mode is top-center hover popup; also implement top-persistent and draggable/resizable floating modes.
- Default launch-at-login, overlay alerts, and system notifications are enabled; every channel is configurable.
- Default percentage alerts are 90% through 20% remaining in 10% steps, then 10% through 1% remaining in 1% steps; 0% uses the exhausted alert.
- Default reset alerts trigger at 48 hours, 24 hours, and 5 hours remaining.
- Default alert text must include the approved Chinese strings and English localizations.
- Keep sanitized fixtures only; never add real `.codex` files to the repository.
- Use MIT licensing and create the public repository `codex-quota-notch` only after local build and tests pass.

---

## File Map

Create these files and keep responsibilities separate:

- `Package.swift` — SwiftPM package, executable target, test target, resource declarations, macOS 13 platform.
- `.gitignore` — ignore `.superpowers/`, `.build/`, `DerivedData/`, app bundles, archives, and macOS metadata.
- `Sources/CodexQuotaNotch/Models/QuotaModels.swift` — value types for limits, snapshots, usage, source status, and cycles.
- `Sources/CodexQuotaNotch/Models/AlertModels.swift` — alert settings, alert state, alert kinds, and alert payloads.
- `Sources/CodexQuotaNotch/Data/JSONLSessionParser.swift` — line-oriented JSONL decoding of only the required event shapes.
- `Sources/CodexQuotaNotch/Data/LocalSessionLogDataSource.swift` — directory scan, latest valid rate limit selection, and daily token aggregation orchestration.
- `Sources/CodexQuotaNotch/Data/DailyUsageAggregator.swift` — deterministic cumulative-token delta calculation by local date.
- `Sources/CodexQuotaNotch/Monitoring/QuotaMonitor.swift` — file-system notifications, polling fallback, and snapshot delivery.
- `Sources/CodexQuotaNotch/Alerts/AlertEngine.swift` — pure threshold and reset evaluation with persisted-key output.
- `Sources/CodexQuotaNotch/Settings/SettingsStore.swift` — `UserDefaults`-backed settings and alert-state persistence.
- `Sources/CodexQuotaNotch/App/AppModel.swift` — main-actor observable state, monitor binding, and alert routing.
- `Sources/CodexQuotaNotch/App/AppDelegate.swift` — app lifecycle, launch-at-login, notifications, status item, and windows.
- `Sources/CodexQuotaNotch/UI/MenuBarController.swift` — status item title/color and menu actions.
- `Sources/CodexQuotaNotch/UI/TopTriggerMonitor.swift` — top-center hover detection for any screen.
- `Sources/CodexQuotaNotch/UI/OverlayPanelController.swift` — non-activating top/persistent/floating `NSPanel` management.
- `Sources/CodexQuotaNotch/UI/OverlayView.swift` — compact quota card used by all overlay modes.
- `Sources/CodexQuotaNotch/UI/MainWindowController.swift` — SwiftUI-hosted main window lifecycle and activation.
- `Sources/CodexQuotaNotch/UI/MainWindowView.swift` — overview, alerts, appearance, and privacy screens.
- `Sources/CodexQuotaNotch/UI/Localization.swift` — typed localization keys and date/number formatting.
- `Sources/CodexQuotaNotch/Resources/zh-Hans.lproj/Localizable.strings` — Simplified Chinese strings.
- `Sources/CodexQuotaNotch/Resources/en.lproj/Localizable.strings` — English strings.
- `Sources/CodexQuotaNotch/Resources/AppIcon.icns` — minimal app icon for the direct-distribution bundle.
- `Tests/CodexQuotaNotchTests/QuotaModelsTests.swift` — percentage and cycle model tests.
- `Tests/CodexQuotaNotchTests/JSONLSessionParserTests.swift` — parser fixtures and malformed-line tests.
- `Tests/CodexQuotaNotchTests/DailyUsageAggregatorTests.swift` — cross-day, duplicate, and reset behavior.
- `Tests/CodexQuotaNotchTests/AlertEngineTests.swift` — all alert thresholds, priority, and deduplication.
- `Tests/CodexQuotaNotchTests/SettingsStoreTests.swift` — defaults, persistence, and validation.
- `Tests/CodexQuotaNotchTests/LocalizationTests.swift` — approved Chinese/English alert strings and resource loading.
- `Tests/CodexQuotaNotchTests/Fixtures/session-standard.jsonl` — sanitized rate-limit and token-count fixture.
- `Tests/CodexQuotaNotchTests/Fixtures/session-missing-fields.jsonl` — missing weekly limit fixture.
- `Tests/CodexQuotaNotchTests/Fixtures/session-malformed.jsonl` — valid and invalid mixed lines.
- `scripts/build-app.sh` — release build, `.app` assembly, Info.plist, resource copying, and universal-arch option.
- `scripts/run-app.sh` — debug build and launch the local `.app`.
- `README.md` — bilingual install/build/privacy/known-limitations guide.
- `LICENSE` — MIT license.
- `.github/workflows/ci.yml` — Swift test and macOS build workflow.

## Task 1: Scaffold the SwiftPM macOS executable and test harness

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/CodexQuotaNotch/App/CodexQuotaNotchApp.swift`
- Create: `Tests/CodexQuotaNotchTests/PackageSmokeTests.swift`

**Interfaces:**
- Produces executable target `CodexQuotaNotch` and test target `CodexQuotaNotchTests`.
- The executable must compile on macOS 13 with `swift build` before any AppKit UI is added.

- [ ] **Step 1: Write the failing package smoke test**

Create a test that proves the package target is discoverable:

```swift
import XCTest
@testable import CodexQuotaNotch

final class PackageSmokeTests: XCTestCase {
    func testPackageModuleLoads() {
        XCTAssertEqual(CodexQuotaNotchApp.buildIdentifier, "codex-quota-notch")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter PackageSmokeTests/testPackageModuleLoads
```

Expected: FAIL because `Package.swift` and `CodexQuotaNotchApp.buildIdentifier` do not exist.

- [ ] **Step 3: Add the package manifest and minimal app symbol**

Use a macOS 13 executable target with processed resources and a test target:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuotaNotch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexQuotaNotch", targets: ["CodexQuotaNotch"])],
    targets: [
        .executableTarget(
            name: "CodexQuotaNotch",
            path: "Sources/CodexQuotaNotch",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CodexQuotaNotchTests",
            dependencies: ["CodexQuotaNotch"],
            path: "Tests/CodexQuotaNotchTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
```

Define `enum CodexQuotaNotchApp { static let buildIdentifier = "codex-quota-notch" }` in the executable target. Add a temporary `@main` entry point that creates no window and exits only through normal app lifecycle.

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
swift test --filter PackageSmokeTests/testPackageModuleLoads
```

Expected: PASS.

- [ ] **Step 5: Add repository ignores and commit the scaffold**

Ignore `.superpowers/`, `.build/`, `DerivedData/`, `*.app`, `*.zip`, `*.dSYM`, `.DS_Store`, and `build/`. Then run:

```bash
git add Package.swift .gitignore Sources/CodexQuotaNotch Tests/CodexQuotaNotchTests
git commit -m "build: scaffold macOS SwiftPM app"
```

## Task 2: Define pure quota, usage, and alert value types

**Files:**
- Create: `Sources/CodexQuotaNotch/Models/QuotaModels.swift`
- Create: `Sources/CodexQuotaNotch/Models/AlertModels.swift`
- Create: `Tests/CodexQuotaNotchTests/QuotaModelsTests.swift`
- Modify: `Tests/CodexQuotaNotchTests/PackageSmokeTests.swift`

**Interfaces:**
- `struct RateLimitSnapshot: Equatable, Sendable` with `windowMinutes: Int`, `usedPercent: Double`, `resetsAt: Date?`, `name: String?`.
- `struct UsageTotals: Equatable, Sendable` with `inputTokens`, `cachedInputTokens`, `cacheWriteInputTokens`, `outputTokens`, `reasoningOutputTokens`, `totalTokens` as `Int`.
- `struct QuotaSnapshot: Equatable, Sendable` with optional `weeklyLimit`, optional `secondaryLimit`, `remainingPercent: Int?`, `dailyTokens: Int`, `resetsAt: Date?`, `cycleID: String?`, `lastUpdatedAt: Date?`, and `sourceStatus: DataSourceStatus`.
- `enum DataSourceStatus: Equatable, Sendable` cases `.ready`, `.waitingForSession`, `.missingWeeklyLimit`, `.stale(lastUpdated: Date)`, `.unreadable(String)`.
- `struct AlertSettings: Codable, Equatable, Sendable` with ordinary step, critical start/step, countdown hours, and channel toggles.
- `enum AlertKind: Codable, Equatable, Hashable, Sendable` cases `.percentage(Int)`, `.countdown(hours: Int)`, `.reset`, `.exhausted`.

- [ ] **Step 1: Write failing model tests**

Cover clamping and flooring:

```swift
func testRemainingPercentClampsAndFloors() {
    XCTAssertEqual(QuotaMath.remainingPercent(fromUsedPercent: 10.1), 89)
    XCTAssertEqual(QuotaMath.remainingPercent(fromUsedPercent: -2), 100)
    XCTAssertEqual(QuotaMath.remainingPercent(fromUsedPercent: 120), 0)
}

func testCycleIDUsesResetDate() {
    let date = Date(timeIntervalSince1970: 1_735_689_600)
    XCTAssertEqual(QuotaMath.cycleID(for: date), "1735689600")
}
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run `swift test --filter QuotaModelsTests -v`. Expected: FAIL because `QuotaMath`, `QuotaSnapshot`, and alert types are not defined.

- [ ] **Step 3: Implement the value types and pure math**

Keep `QuotaMath` stateless:

```swift
enum QuotaMath {
    static func remainingPercent(fromUsedPercent value: Double) -> Int {
        Int(floor(min(100, max(0, 100 - value))))
    }

    static func cycleID(for resetDate: Date?) -> String? {
        resetDate.map { String(Int($0.timeIntervalSince1970)) }
    }
}
```

Use `Codable` only for settings and alert state; all snapshot types remain value types suitable for main-actor handoff.

- [ ] **Step 4: Run the model tests**

Run `swift test --filter QuotaModelsTests -v`. Expected: PASS.

- [ ] **Step 5: Commit the domain model**

```bash
git add Sources/CodexQuotaNotch/Models Tests/CodexQuotaNotchTests/QuotaModelsTests.swift
git commit -m "feat: define quota and alert domain models"
```

## Task 3: Parse Codex JSONL and aggregate daily tokens

**Files:**
- Create: `Sources/CodexQuotaNotch/Data/JSONLSessionParser.swift`
- Create: `Sources/CodexQuotaNotch/Data/DailyUsageAggregator.swift`
- Create: `Sources/CodexQuotaNotch/Data/LocalSessionLogDataSource.swift`
- Create: `Tests/CodexQuotaNotchTests/JSONLSessionParserTests.swift`
- Create: `Tests/CodexQuotaNotchTests/DailyUsageAggregatorTests.swift`
- Create: `Tests/CodexQuotaNotchTests/Fixtures/session-standard.jsonl`
- Create: `Tests/CodexQuotaNotchTests/Fixtures/session-missing-fields.jsonl`
- Create: `Tests/CodexQuotaNotchTests/Fixtures/session-malformed.jsonl`

**Interfaces:**
- `struct ParsedSessionEvent: Equatable, Sendable` with `timestamp: Date`, `kind: ParsedEventKind`, `rateLimits: [RateLimitSnapshot]`, `lastUsage: UsageTotals?`, `totalUsage: UsageTotals?`.
- `enum ParsedEventKind: Equatable, Sendable` cases `.tokenCount`, `.other`.
- `struct JSONLSessionParser: Sendable` with `func parseLine(_ data: Data) -> ParsedSessionEvent?`.
- `struct DailyUsageAggregator: Sendable` with `func totals(eventsByFile: [URL: [ParsedSessionEvent]], calendar: Calendar) -> [Date: Int]`.
- `struct LocalSessionLogDataSource: Sendable` with `init(rootDirectory: URL)` and `func readSnapshot(now: Date, calendar: Calendar) throws -> QuotaSnapshot`.

- [ ] **Step 1: Add sanitized fixtures and failing parser tests**

Fixtures must include only synthetic values. The standard fixture must contain an `event_msg`/`token_count` line with `payload.info.last_token_usage`, `payload.info.total_token_usage`, and a seven-day `payload.rate_limits.primary`. Tests must assert that the parser extracts fields but never expose or store arbitrary payload text.

Example assertion:

```swift
func testParsesSevenDayRateLimitAndTokenUsage() throws {
    let event = try XCTUnwrap(loadFixture("session-standard.jsonl").first)
    XCTAssertEqual(event.kind, .tokenCount)
    XCTAssertEqual(event.rateLimits.first?.windowMinutes, 10080)
    XCTAssertEqual(event.lastUsage?.totalTokens, 2_400)
}
```

- [ ] **Step 2: Run parser tests to confirm failure**

Run `swift test --filter JSONLSessionParserTests -v`. Expected: FAIL because parser and fixtures are not implemented.

- [ ] **Step 3: Implement safe line parsing**

Decode only a small `Codable` envelope with `timestamp`, `type`, and `payload`; decode `payload.type`, `payload.info`, and `payload.rate_limits`. Return `nil` for malformed or irrelevant lines. Do not retain the original JSON string or unknown payload keys.

- [ ] **Step 4: Implement daily aggregation tests before the aggregator**

Cover:

```swift
func testUsesPositiveCumulativeDeltasOnly() {
    let values = [1_000, 1_400, 1_400, 1_250, 1_900]
    XCTAssertEqual(DailyUsageAggregator.deltaTotal(values), 1_900)
}

func testSplitsTotalsByLocalDate() {
    let calendar = fixedCalendar(timeZone: "Asia/Shanghai")
    let totals = makeEventsAcrossMidnight()
    XCTAssertEqual(totals[date("2026-08-17")], 400)
    XCTAssertEqual(totals[date("2026-08-18")], 500)
}
```

- [ ] **Step 5: Implement aggregation and local data source**

For each file, order token-count events by timestamp, add only positive deltas of cumulative `total_token_usage.total_tokens`, attribute deltas to the event’s local calendar day, and use `last_token_usage` only when cumulative totals are absent. `LocalSessionLogDataSource` recursively scans JSONL files, keeps the newest valid rate-limit snapshot, selects `windowMinutes == 10080`, and returns `.missingWeeklyLimit` when no weekly entry exists.

- [ ] **Step 6: Run parser and aggregation tests**

Run `swift test --filter 'JSONLSessionParserTests|DailyUsageAggregatorTests' -v`. Expected: PASS.

- [ ] **Step 7: Commit the data layer**

```bash
git add Sources/CodexQuotaNotch/Data Tests/CodexQuotaNotchTests/JSONLSessionParserTests.swift Tests/CodexQuotaNotchTests/DailyUsageAggregatorTests.swift Tests/CodexQuotaNotchTests/Fixtures
git commit -m "feat: parse local Codex session usage"
```

## Task 4: Implement the alert state machine with exhaustive tests

**Files:**
- Create: `Sources/CodexQuotaNotch/Alerts/AlertEngine.swift`
- Modify: `Sources/CodexQuotaNotch/Models/AlertModels.swift`
- Create: `Tests/CodexQuotaNotchTests/AlertEngineTests.swift`

**Interfaces:**
- `struct AlertState: Codable, Equatable, Sendable` with `cycleID: String?` and `emittedKeys: Set<String>`.
- `struct QuotaAlert: Equatable, Sendable` with `kind: AlertKind`, `titleKey: String`, `messageKey: String`, and interpolation values.
- `struct AlertEvaluation: Equatable, Sendable` with `[QuotaAlert] alerts` and `AlertState updatedState`.
- `struct AlertEngine: Sendable` with `func evaluate(previous: QuotaSnapshot?, current: QuotaSnapshot, now: Date, settings: AlertSettings, state: AlertState) -> AlertEvaluation`.

- [ ] **Step 1: Write failing tests for all default threshold families**

Include tests for ordinary 90–20 thresholds, critical 10–1 thresholds, exhausted, 48/24/5-hour countdowns, reset, deduplication, priority, and the 100%-to-78% startup jump.

Example:

```swift
func testTenPercentCrossingEmitsOnlyCurrentThreshold() {
    let previous = snapshot(remaining: 100, reset: resetDate)
    let current = snapshot(remaining: 78, reset: resetDate)
    let result = engine.evaluate(previous: previous, current: current, now: now, settings: .defaults, state: .empty)
    XCTAssertEqual(result.alerts.map(\.kind), [.percentage(80)])
}
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run `swift test --filter AlertEngineTests -v`. Expected: FAIL because `AlertEngine` and alert state are not implemented.

- [ ] **Step 3: Implement deterministic evaluation and key generation**

Use `cycleID + kind + threshold` keys. For a startup jump, emit the greatest crossed ordinary threshold that is still at or above the current remaining integer; for critical levels emit the current critical integer only. Reset state when the cycle ID changes. Apply priority exhausted > reset > 5 hours > 1 day > 2 days > percentage, and return a new immutable state.

- [ ] **Step 4: Run alert tests and inspect all expected messages**

Run `swift test --filter AlertEngineTests -v`. Expected: PASS, with no duplicate keys in any evaluation.

- [ ] **Step 5: Commit the alert engine**

```bash
git add Sources/CodexQuotaNotch/Alerts Sources/CodexQuotaNotch/Models/AlertModels.swift Tests/CodexQuotaNotchTests/AlertEngineTests.swift
git commit -m "feat: add configurable quota alert engine"
```

## Task 5: Add settings persistence and quota monitoring

**Files:**
- Create: `Sources/CodexQuotaNotch/Settings/SettingsStore.swift`
- Create: `Sources/CodexQuotaNotch/Monitoring/QuotaMonitor.swift`
- Create: `Tests/CodexQuotaNotchTests/SettingsStoreTests.swift`

**Interfaces:**
- `enum DisplayMode: String, Codable, CaseIterable` cases `.topPopup`, `.topPersistent`, `.floating`.
- `enum AppearanceMode: String, Codable, CaseIterable` cases `.system`, `.light`, `.dark`.
- `struct AppSettings: Codable, Equatable, Sendable` with `appearance`, `displayMode`, `launchAtLogin`, `overlayAlertsEnabled`, `systemNotificationsEnabled`, `percentageAlertsEnabled`, `criticalAlertsEnabled`, `countdownAlertsEnabled`, `ordinaryStep`, `criticalStart`, `criticalStep`, `countdownHours`, `dataDirectoryBookmark`, and `floatingFrame`.
- `@MainActor final class SettingsStore: ObservableObject` with `@Published var settings`, `@Published var alertState`, `func save()`, `func resetFloatingFrame()`, `func chooseDataDirectory() async`.
- `final class QuotaMonitor` with `init(dataSource: LocalSessionLogDataSource, onSnapshot: @escaping @Sendable (QuotaSnapshot) -> Void)`, `func start()`, and `func stop()`.

- [ ] **Step 1: Write failing settings tests**

Assert defaults and round-trip persistence using an isolated `UserDefaults(suiteName:)`:

```swift
func testDefaultsMatchApprovedProductBehavior() {
    let settings = AppSettings.defaults
    XCTAssertEqual(settings.appearance, .system)
    XCTAssertEqual(settings.displayMode, .topPopup)
    XCTAssertTrue(settings.launchAtLogin)
    XCTAssertTrue(settings.systemNotificationsEnabled)
    XCTAssertEqual(settings.ordinaryStep, 10)
    XCTAssertEqual(settings.criticalStart, 10)
    XCTAssertEqual(settings.criticalStep, 1)
}
```

- [ ] **Step 2: Run settings tests and confirm failure**

Run `swift test --filter SettingsStoreTests -v`. Expected: FAIL because settings persistence is not implemented.

- [ ] **Step 3: Implement Codable settings and alert-state storage**

Store settings under `settings.v1`, alert state under `alert-state.v1`, and floating frame as a Codable rectangle. Validate ordinary/critical steps to positive values on load. Keep data-directory selection as a security-scoped bookmark only when the user explicitly chooses a path.

- [ ] **Step 4: Implement the monitor with immediate scan and 10-second fallback**

Use a serial background queue, a `DispatchSourceFileSystemObject` for the selected directory when possible, and a 10-second `DispatchSourceTimer` fallback. While the top overlay is visible, allow the app model to request a 2-second refresh interval. Delivery must be throttled to the main actor by snapshot equality.

- [ ] **Step 5: Run settings tests and a package build**

Run:

```bash
swift test --filter SettingsStoreTests -v
swift build
```

Expected: PASS and a successful executable build.

- [ ] **Step 6: Commit settings and monitoring**

```bash
git add Sources/CodexQuotaNotch/Settings Sources/CodexQuotaNotch/Monitoring Tests/CodexQuotaNotchTests/SettingsStoreTests.swift
git commit -m "feat: persist settings and monitor local Codex data"
```

## Task 6: Build the SwiftUI views and localization resources

**Files:**
- Create: `Sources/CodexQuotaNotch/UI/OverlayView.swift`
- Create: `Sources/CodexQuotaNotch/UI/MainWindowView.swift`
- Create: `Sources/CodexQuotaNotch/UI/Localization.swift`
- Create: `Sources/CodexQuotaNotch/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Sources/CodexQuotaNotch/Resources/en.lproj/Localizable.strings`

**Interfaces:**
- `struct OverlayView: View` accepts `QuotaSnapshot`, `displayMode`, and `onOpenMainWindow`.
- `struct MainWindowView: View` accepts an `@ObservedObject AppModel` and renders four sections: overview, alerts, appearance/display, data/privacy.
- `enum L10n` exposes typed keys for titles and all approved alert messages.

- [ ] **Step 1: Add localization tests for exact alert copy**

Add a small pure test that the localization key map contains the five approved Chinese strings as values in `zh-Hans.lproj/Localizable.strings`. Keep interpolation separate so `2`/`1`/`5` remain user-configurable text values.

- [ ] **Step 2: Run the localization test and confirm failure**

Run `swift test --filter LocalizationTests -v`. Expected: FAIL because resources and key map are absent.

- [ ] **Step 3: Implement localized strings and formatting**

Use `Date.FormatStyle` for reset date/time and `Duration`-style formatting for countdown. Include these exact Chinese values:

```text
"alert.countdown.twoDays" = "距离 Codex 周额度重置只剩下 2 天";
"alert.countdown.oneDay" = "距离 Codex 周额度重置只剩下一天";
"alert.countdown.fiveHours" = "距离 Codex 周额度将在 5 小时后重置";
"alert.reset" = "Codex 周额度已重置";
"alert.exhausted" = "Codex 周额度已用尽";
```

- [ ] **Step 4: Implement the overlay card**

Show title, integer remaining percentage, progress bar, reset date, countdown, daily token count, source state, and last update. Use `Color.accentColor`/semantic colors plus explicit low/critical state colors so system appearance remains legible.

- [ ] **Step 5: Implement the main window sections**

Use a sidebar or segmented navigation with `Overview`, `Alerts`, `Appearance`, and `Data & Privacy`. Bind all controls to `SettingsStore` through `AppModel`. Expose ordinary step, critical start/step, countdown toggles, both output channels, appearance, three display modes, launch-at-login, path selection, rescan, and simulation mode.

- [ ] **Step 6: Run build and resource tests**

Run `swift test --filter 'LocalizationTests|PackageSmokeTests' -v` and `swift build`. Expected: PASS.

- [ ] **Step 7: Commit views and localization**

```bash
git add Sources/CodexQuotaNotch/UI Sources/CodexQuotaNotch/Resources Tests/CodexQuotaNotchTests/LocalizationTests.swift
git commit -m "feat: add localized quota views and settings UI"
```

## Task 7: Integrate AppKit menu bar, hover trigger, panels, notifications, and launch-at-login

**Files:**
- Create: `Sources/CodexQuotaNotch/App/AppModel.swift`
- Create: `Sources/CodexQuotaNotch/App/AppDelegate.swift`
- Create: `Sources/CodexQuotaNotch/UI/MenuBarController.swift`
- Create: `Sources/CodexQuotaNotch/UI/TopTriggerMonitor.swift`
- Create: `Sources/CodexQuotaNotch/UI/OverlayPanelController.swift`
- Create: `Sources/CodexQuotaNotch/UI/MainWindowController.swift`
- Create: `Sources/CodexQuotaNotch/Alerts/NotificationClient.swift`
- Modify: `Sources/CodexQuotaNotch/App/CodexQuotaNotchApp.swift`

**Interfaces:**
- `@MainActor final class AppModel: ObservableObject` owns `snapshot`, `settingsStore`, `monitor`, `alertEngine`, and `handle(snapshot:)`.
- `@MainActor final class MenuBarController` owns `NSStatusItem`, updates title/color, and exposes `openMainWindow`, `setDisplayMode`, `refresh`, and `terminate` actions.
- `final class TopTriggerMonitor` exposes `start()`, `stop()`, and `onEnter`/`onExit` closures; it uses a 36pt high top-center region on the screen containing `NSEvent.mouseLocation`.
- `@MainActor final class OverlayPanelController` exposes `showTopPopup(on:)`, `showPersistent(on:)`, `showFloating()`, `hidePopup()`, and `resetFloatingFrame()`.
- `final class NotificationClient: NSObject, UNUserNotificationCenterDelegate` exposes `requestAuthorization()` and `send(_ alert: QuotaAlert)`.

- [ ] **Step 1: Write a pure integration test for alert routing**

Create an `AppModel` test seam that injects an in-memory notification client and overlay sink; assert that one `QuotaAlert` reaches both sinks when both settings are enabled and only the selected sink when one is disabled.

- [ ] **Step 2: Run the integration test and confirm failure**

Run `swift test --filter AppModelTests -v`. Expected: FAIL because the app model and sinks are absent.

- [ ] **Step 3: Implement the main-actor app model**

Initialize settings, data source, monitor, and alert state. On each new snapshot, call `AlertEngine.evaluate`, persist the returned state, update the status item, and route alert events through the enabled overlay and notification sinks. Add a simulation mode that produces a deterministic snapshot for UI/manual testing but is disabled by default.

- [ ] **Step 4: Implement the status item and main window**

Create an `NSStatusItem.variableLength` with the remaining percentage as its title. Apply semantic colors based on the snapshot state. Add menu items for opening the main window, switching display mode, refreshing, and quitting. Use an `NSHostingView` inside `MainWindowController` for `MainWindowView`; set accessory activation policy and temporarily activate the app when opening the window.

- [ ] **Step 5: Implement top-center mouse detection**

Register global and local `.mouseMoved` monitors. Find the screen whose frame contains the current mouse point, define the horizontal center region at `screen.frame.maxY - 36 ... screen.frame.maxY`, and fire `onEnter` once per entry. Fire `onExit` after the point leaves both the trigger region and overlay frame. Remove monitors on deinit.

- [ ] **Step 6: Implement all three panel modes**

Create a borderless, non-activating `NSPanel` at `.statusBar` level with `.canJoinAllSpaces` and `.fullScreenAuxiliary`. For popup and persistent modes, compute the frame from the selected screen’s horizontal center. For floating mode, add `.resizable`, apply the stored frame, allow drag/resize, and persist the frame on move/resize. Do not steal keyboard focus from Codex.

- [ ] **Step 7: Implement notifications and launch-at-login**

Request `UNAuthorizationOptions.alert`, `.sound`, and `.badge` on first run. Use the localized title/message for every alert. Register/unregister the main app with `SMAppService.mainApp` when the setting changes; surface failures as a non-blocking settings status.

- [ ] **Step 8: Run tests and build the integrated app**

Run:

```bash
swift test
swift build -c release
```

Expected: PASS and a Release executable.

- [ ] **Step 9: Commit AppKit integration**

```bash
git add Sources/CodexQuotaNotch/App Sources/CodexQuotaNotch/UI Sources/CodexQuotaNotch/Alerts Sources/CodexQuotaNotch/App/CodexQuotaNotchApp.swift Tests
git commit -m "feat: integrate menu bar overlays and system notifications"
```

## Task 8: Assemble a distributable `.app` and add documentation/CI

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/run-app.sh`
- Create: `Sources/CodexQuotaNotch/Resources/Info.plist`
- Create: `Sources/CodexQuotaNotch/Resources/AppIcon.icns`
- Create: `README.md`
- Create: `LICENSE`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- `scripts/build-app.sh [--universal] [--configuration debug|release]` outputs `build/CodexQuotaNotch.app`.
- `scripts/run-app.sh` builds debug and launches `build/CodexQuotaNotch.app`.

- [ ] **Step 1: Write a packaging smoke check**

Add a shell-level test command to the plan execution checklist:

```bash
./scripts/build-app.sh --configuration release
test -x build/CodexQuotaNotch.app/Contents/MacOS/CodexQuotaNotch
plutil -p build/CodexQuotaNotch.app/Contents/Info.plist | rg 'LSUIElement|CFBundleIdentifier|LSMinimumSystemVersion'
```

The expected pre-implementation result is failure because the scripts and bundle do not exist.

- [ ] **Step 2: Implement app assembly**

Build the executable with `swift build -c release`, create `Contents/MacOS`, `Contents/Resources`, copy the binary and processed resource bundle, copy `Info.plist`, and set `CFBundleIdentifier` to `com.codexquotanotch.app`, `CFBundleName` to `CodexQuotaNotch`, `LSMinimumSystemVersion` to `13.0`, and `LSUIElement` to `true`. The `--universal` option builds arm64 and x86_64 separately and combines them with `lipo`.

- [ ] **Step 3: Implement launch helper and run the packaging smoke check**

Run `./scripts/build-app.sh --configuration release` and the `test`/`plutil` commands above. Expected: the app bundle exists, the executable is runnable, and the plist contains the required keys.

- [ ] **Step 4: Write bilingual README and MIT license**

Document local-only data access, default path, supported macOS versions, three display modes, alert defaults, notification permissions, known dependency on Codex’s internal JSONL fields, build commands, test commands, and privacy boundaries. Explain that the app shows `—` instead of guessing when the weekly field is missing.

- [ ] **Step 5: Add CI**

Configure GitHub Actions on `macos-latest` to run `swift test` and `swift build -c release`, without accessing any real user data. Include a fixture-only test job.

- [ ] **Step 6: Commit packaging and docs**

```bash
git add scripts Sources/CodexQuotaNotch/Resources README.md LICENSE .github/workflows/ci.yml
git commit -m "chore: package app and document open-source release"
```

## Task 9: Full verification and GitHub publication

**Files:**
- Modify: `README.md` if verification exposes inaccurate commands or status text.
- Modify: `.github/workflows/ci.yml` if the clean runner exposes a reproducibility issue.

- [ ] **Step 1: Run the complete local verification set**

Run:

```bash
swift test
swift build -c release
./scripts/build-app.sh --configuration release
test -x build/CodexQuotaNotch.app/Contents/MacOS/CodexQuotaNotch
git diff --check
```

Expected: all tests pass, the release build succeeds, the app bundle contains the executable and plist, and whitespace validation is clean.

- [ ] **Step 2: Perform manual runtime checks on the current Mac**

Launch `./scripts/run-app.sh` and verify menu-bar residency, opening the main window, simulated quota display, automatic appearance, popup hover at the screen’s top center, persistent mode, floating drag/resize persistence, notification permission behavior, and reset/threshold simulation. Stop the app after the checks and do not commit generated runtime data.

- [ ] **Step 3: Review repository contents for secrets and local data**

Run:

```bash
git status --short
rg -n -i 'sk-[A-Za-z0-9]|api[_-]?key|token.*=' --glob '!docs/**' --glob '!Tests/**' . || true
find . -path './.git' -prune -o -path './.superpowers' -prune -o -type f -print
```

Remove only generated build artifacts and confirm no `.codex` session files are tracked.

- [ ] **Step 4: Create the public GitHub repository and push**

Use the connected GitHub integration to create the public repository `codex-quota-notch`, set the description to `A native macOS menu bar app that monitors Codex weekly quota locally`, push the `main` branch, and ensure the MIT license and README are visible. Do not upload the local `.superpowers/` directory or any generated `.app` unless a release artifact is deliberately requested.

- [ ] **Step 5: Verify the published repository**

Open the public repository through the GitHub integration and verify the default branch, README, license, source tree, CI workflow, and absence of local session data. Report the repository URL and the exact local build/test commands used.

## Plan Self-Review Checklist

- [ ] Every specification section maps to at least one task: data source and aggregation (Tasks 2–3), alerts (Task 4), settings/refresh (Task 5), UI/localization (Task 6), system integration (Task 7), packaging/open source (Tasks 8–9).
- [ ] No task depends on an undefined type or function; cross-task interfaces are listed before use.
- [ ] Tests are written before implementation in every testable task.
- [ ] No real Codex data is needed for tests or CI.
- [ ] The plan uses only SwiftPM and Apple frameworks, so a clean checkout has no external dependency installation step.
