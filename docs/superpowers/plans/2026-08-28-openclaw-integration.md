# OpenClaw 微信额度推送 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将周额度和 Plus 5 小时额度的本地状态安全、去重地推送到本机 OpenClaw Gateway，再由已配置的微信通道发送到手机。

**Architecture:** 在现有 `AppModel` 快照流旁增加纯 Swift 的事件规划器和异步 Hook 客户端。设置页保存非敏感的 Gateway/通道/Target 配置，Hook Token 通过 macOS Keychain 保存；应用只向 loopback Gateway 发送格式化额度摘要，不接触微信协议。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Foundation URLSession、Security Keychain、XCTest、现有 Swift Package executable。

**Spec:** `docs/superpowers/specs/2026-08-28-openclaw-integration-design.md`

## Global Constraints

- 支持平台保持 macOS 13 Ventura 及以上。
- 现有周额度选择 `window_minutes = 10080`，5 小时额度选择 `window_minutes = 300`。
- Token 不得写入 `UserDefaults`、Git、日志或 HTTP URL 查询参数。
- 默认 OpenClaw 推送关闭；现有额度显示、浮窗、系统通知行为不变。
- Gateway 默认只使用 `http://127.0.0.1:18789`，请求使用 `Authorization: Bearer <token>`。
- 不发送 prompt、回复、工具调用、API key 或原始 JSONL；只发送格式化数字和日期摘要。
- 每个新生产行为都必须先写一个能失败的测试，确认失败后再写实现。

### Task 1: Add models, secure secret storage, and persistence

**Files:**
- Create: `Sources/CodexQuotaNotch/OpenClaw/OpenClawModels.swift`
- Create: `Sources/CodexQuotaNotch/OpenClaw/SecretStore.swift`
- Create: `Sources/CodexQuotaNotch/OpenClaw/KeychainSecretStore.swift`
- Modify: `Sources/CodexQuotaNotch/Settings/SettingsStore.swift`
- Test: `Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift`
- Test: `Tests/CodexQuotaNotchTests/SettingsStoreTests.swift`

**Interfaces:**
- `OpenClawPushSettings`: Codable delivery configuration with `defaults`, `isAddressed`, and `deliveryFingerprint`.
- `OpenClawPushState`: Codable last-delivered status fingerprint and five-hour cycle bookkeeping.
- `OpenClawDeliveryStatus`: non-persisted UI status enum.
- `SecretStore`: synchronous `read(key:)`, `write(_:key:)`, and `delete(key:)` interface.
- `KeychainSecretStore`: macOS Security implementation using service `com.codexquotanotch.openclaw`.
- `AppSettings.openClaw`, `SettingsStore.openClawPushState`, `SettingsStore.openClawToken`, and `SettingsStore.saveOpenClawToken(_:)`.

- [x] **Step 1: Write the failing persistence and Keychain tests.**

  Add tests proving that defaults are disabled, old settings without `openClaw` decode to defaults, state round-trips through `UserDefaults`, an in-memory secret store saves/reads/deletes a token, and a token is not present in encoded `AppSettings` JSON.

- [x] **Step 2: Run the focused tests to verify the expected red failure.**

  Run `swift test --filter 'OpenClawIntegrationTests|SettingsStoreTests'`. Expected failure: the new types and settings members do not exist.

- [x] **Step 3: Implement the model and secret-store interfaces.**

  Add Codable defaults and migration-safe `decodeIfPresent` handling. Keep the token outside `AppSettings` and make Keychain failures return a typed error; use an in-memory implementation only in tests.

- [x] **Step 4: Run the focused tests to verify green.**

  Run `swift test --filter 'OpenClawIntegrationTests|SettingsStoreTests'`. Expected output: all selected tests pass with zero failures.

- [x] **Step 5: Commit the model and persistence slice.**

  Run `git add Sources/CodexQuotaNotch/OpenClaw Sources/CodexQuotaNotch/Settings/SettingsStore.swift Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift Tests/CodexQuotaNotchTests/SettingsStoreTests.swift && git commit -m "feat: add secure OpenClaw push settings"`.

### Task 2: Add deterministic event planning and message formatting

**Files:**
- Create: `Sources/CodexQuotaNotch/OpenClaw/OpenClawPushPlanner.swift`
- Create: `Sources/CodexQuotaNotch/OpenClaw/OpenClawMessageFormatter.swift`
- Modify: `Sources/CodexQuotaNotch/Localization.swift`
- Modify: `Sources/CodexQuotaNotch/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/CodexQuotaNotch/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift`

**Interfaces:**
- `OpenClawPushEventKind`: `.status(fingerprint:)`, `.fiveHourReset(cycleID:)`, `.alert(QuotaAlert)`, `.test`.
- `OpenClawPushEvent`: stable `key` plus kind.
- `OpenClawPushEvaluation`: events and observed state.
- `OpenClawPushPlanner.evaluate(previous:current:alerts:settings:state:)` and `markDelivered(_:state:)`.
- `OpenClawMessageFormatter.message(for:snapshot:)` and `statusMessage(for:)`.

- [x] **Step 1: Write failing planner and formatter tests.**

  Cover: initial status event, no event for an unchanged snapshot after delivery, one five-hour reset event when the 300-minute cycle changes, status suppression while a reset is pending, weekly alert passthrough, Chinese and English summaries containing both quota percentages/reset values/today token, and no event when OpenClaw is disabled.

- [x] **Step 2: Run the focused tests to verify red.**

  Run `swift test --filter OpenClawIntegrationTests`. Expected failure: planner, formatter, or localization keys are absent.

- [x] **Step 3: Implement pure event planning and localized formatting.**

  Use `QuotaMath.cycleID` for five-hour reset identity, a stable fingerprint composed only of remaining percentages and reset cycle IDs, and the existing `QuotaAlert` values for weekly alerts. Do not include raw JSONL content.

- [x] **Step 4: Run focused tests to verify green.**

  Run `swift test --filter OpenClawIntegrationTests`. Expected output: all planner/formatter tests pass.

- [x] **Step 5: Commit the planning slice.**

  Run `git add Sources/CodexQuotaNotch/OpenClaw Sources/CodexQuotaNotch/Localization.swift Sources/CodexQuotaNotch/Resources Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift && git commit -m "feat: plan localized OpenClaw quota events"`.

### Task 3: Add the authenticated Hook client with retry

**Files:**
- Create: `Sources/CodexQuotaNotch/OpenClaw/OpenClawHookClient.swift`
- Test: `Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift`

**Interfaces:**
- `OpenClawHookPayload: Codable, Equatable, Sendable`.
- `OpenClawHTTPResponse` and `OpenClawTransport`.
- `URLSessionOpenClawTransport`.
- `OpenClawRetryPolicy`.
- `OpenClawHookClient.send(message:configuration:token:) async throws`.

- [x] **Step 1: Write failing HTTP-client tests.**

  Use an actor-backed recording transport to assert the `/hooks/agent` path, JSON fields, `Content-Type`, Bearer header, no request for invalid configuration, non-2xx errors, and retry up to three attempts.

- [x] **Step 2: Run the focused tests to verify red.**

  Run `swift test --filter OpenClawIntegrationTests`. Expected failure: the client and transport interfaces are absent.

- [x] **Step 3: Implement request construction and bounded retry.**

  Validate URL scheme/host/token/channel/target before transport; append `hooks/agent`; omit empty optional `accountId`; retry only transport and HTTP failures with injectable zero-delay policy in tests.

- [x] **Step 4: Run focused tests to verify green.**

  Run `swift test --filter OpenClawIntegrationTests`. Expected output: all HTTP and retry tests pass.

- [x] **Step 5: Commit the client slice.**

  Run `git add Sources/CodexQuotaNotch/OpenClaw/OpenClawHookClient.swift Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift && git commit -m "feat: send quota events to OpenClaw hooks"`.

### Task 4: Connect AppModel to OpenClaw events and retries

**Files:**
- Modify: `Sources/CodexQuotaNotch/App/AppModel.swift`
- Modify: `Sources/CodexQuotaNotch/Settings/SettingsStore.swift`
- Test: `Tests/CodexQuotaNotchTests/AppModelTests.swift`
- Test: `Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift`

**Interfaces:**
- `AppModel` accepts an injectable `OpenClawHookClient`.
- `AppModel.testOpenClaw()` sends a non-persistent test event.
- `AppModel` owns only in-flight event keys and failed alert events; persisted state is updated after successful delivery.

- [x] **Step 1: Write failing AppModel integration tests.**

  Prove a configured model sends one initial status, does not send a duplicate on the same snapshot, emits a five-hour reset event on cycle change, queues a failed alert for the next snapshot, and never calls the transport when disabled or incomplete.

- [x] **Step 2: Run focused tests to verify red.**

  Run `swift test --filter 'AppModelTests|OpenClawIntegrationTests'`. Expected failure: AppModel has no OpenClaw client or event dispatch path.

- [x] **Step 3: Implement MainActor dispatch, state marking, and retry queue.**

  Capture only immutable message/config/token values inside detached async work, update settings-store delivery state on the MainActor after success, remove in-flight keys in both success and failure paths, and keep failed alerts for a later snapshot without affecting existing overlay/system notification sinks.

- [x] **Step 4: Run focused tests to verify green.**

  Run `swift test --filter 'AppModelTests|OpenClawIntegrationTests'`. Expected output: all integration tests pass.

- [x] **Step 5: Commit the AppModel slice.**

  Run `git add Sources/CodexQuotaNotch/App/AppModel.swift Sources/CodexQuotaNotch/Settings/SettingsStore.swift Tests/CodexQuotaNotchTests/AppModelTests.swift Tests/CodexQuotaNotchTests/OpenClawIntegrationTests.swift && git commit -m "feat: dispatch quota events through OpenClaw"`.

### Task 5: Add localized settings UI and app wiring

**Files:**
- Modify: `Sources/CodexQuotaNotch/UI/MainWindowView.swift`
- Modify: `Sources/CodexQuotaNotch/UI/MainWindowController.swift`
- Modify: `Sources/CodexQuotaNotch/App/CodexQuotaNotchApp.swift`
- Modify: `Sources/CodexQuotaNotch/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/CodexQuotaNotch/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/CodexQuotaNotchTests/LocalizationTests.swift`

**Interfaces:**
- Add `MainSection.openClaw` and `OpenClawPage`.
- `MainWindowView` accepts `onTestOpenClaw` and observes `SettingsStore` delivery status.
- `MainWindowController` forwards the test callback.
- `AppDelegate` owns one `KeychainSecretStore`, injects one `OpenClawHookClient`, and wires `AppModel.testOpenClaw()`.

- [x] **Step 1: Write failing localization/settings UI tests.**

  Assert both languages include the page title, connection labels, Keychain explanation, status text, test action, and status/alert toggle labels.

- [x] **Step 2: Run focused tests to verify red.**

  Run `swift test --filter LocalizationTests`. Expected failure: the new localization keys do not exist.

- [x] **Step 3: Implement the page and dependency wiring.**

  Use `SecureField` for a local token draft, explicit Save/Clear actions, bindings for non-secret settings, a test button, and no token value in accessibility text. Add the OpenClaw page to the existing navigation and keep the current appearance page unchanged.

- [x] **Step 4: Run focused tests and compile the app target.**

  Run `swift test --filter LocalizationTests` and `swift build`. Expected output: tests pass and the executable builds for macOS 13.

- [x] **Step 5: Commit the UI and wiring slice.**

  Run `git add Sources/CodexQuotaNotch/UI Sources/CodexQuotaNotch/App/CodexQuotaNotchApp.swift Sources/CodexQuotaNotch/Resources Tests/CodexQuotaNotchTests/LocalizationTests.swift && git commit -m "feat: configure OpenClaw push from settings"`.

### Task 6: Document, package, and verify delivery

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-28-openclaw-integration-design.md` only if verification finds an inaccurate statement
- Modify: `docs/superpowers/plans/2026-08-28-openclaw-integration.md` by checking completed steps

- [x] **Step 1: Add README setup and privacy instructions.**

  Document OpenClaw Hook configuration, `openclaw-weixin` channel/Target requirement, loopback security, Keychain storage, event deduplication, and a curl test with placeholders only.

- [x] **Step 2: Run the full test suite and static checks.**

  Run `swift test`, `git diff --check`, and inspect `git status --short`. Expected output: zero test failures, no whitespace errors, and only intended files changed.

- [x] **Step 3: Build the macOS app bundle.**

  Run `./scripts/build-app.sh`; verify `Resources/Info.plist` still reports `LSMinimumSystemVersion` `13.0` and the bundle contains the SwiftPM resource bundle.

- [ ] **Step 4: Manually verify the settings flow without transmitting credentials.**

  The automated Computer Use check could not run because the macOS session was locked. No credentials were entered or transmitted; the target compiled successfully and the UI initializer/localization tests passed.

  Open the built app, navigate to OpenClaw settings, verify Chinese/English labels, verify the Token field is secure, toggle push/status/alert settings, and leave the actual Token/Target unchanged unless the user later supplies them locally.

- [x] **Step 5: Request an independent code review and inspect the final diff.**

  An independent reviewer was dispatched but timed out without returning a report. The final diff was then inspected locally against this checklist, including a generation-safe in-flight fix and a regression test for incomplete weekly snapshots.

  Review the final commits against this plan, fix Critical/Important findings, then rerun the full test and build commands.

- [x] **Step 6: Commit documentation and package changes.**

  Run `git add README.md docs/superpowers/specs/2026-08-28-openclaw-integration-design.md docs/superpowers/plans/2026-08-28-openclaw-integration.md && git commit -m "docs: document OpenClaw quota notifications"`.
