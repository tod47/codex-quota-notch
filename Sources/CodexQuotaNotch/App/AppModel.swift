import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var snapshot: QuotaSnapshot
    @Published public private(set) var lastAlert: QuotaAlert?
    @Published public private(set) var isRefreshing = false

    public let settingsStore: SettingsStore

    private var dataSource: LocalSessionLogDataSource
    private var monitor: QuotaMonitor?
    private var simulationTimer: Timer?
    private var simulationResetDate: Date?
    private var simulationFiveHourResetDate: Date?
    private var simulationUsedPercent = 20.0
    private var previousSnapshot: QuotaSnapshot?
    private let openClawClient: OpenClawHookClient
    private let openClawPlanner = OpenClawPushPlanner()
    private var openClawInFlightKeys: [String: UUID] = [:]
    private var pendingOpenClawAlerts: [String: QuotaAlert] = [:]
    private var pendingOpenClawCycleID: String?
    private var openClawDeliveryGeneration = UUID()
    private var openClawSettingsFingerprint: String
    private let alertEngine = AlertEngine()
    private let overlaySink: (QuotaAlert) -> Void
    private let notificationSink: (QuotaAlert) -> Void

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: LocalSessionLogDataSource? = nil,
        initialSnapshot: QuotaSnapshot? = nil,
        startMonitoring shouldStartMonitoring: Bool = true,
        overlaySink: @escaping (QuotaAlert) -> Void = { _ in },
        notificationSink: @escaping (QuotaAlert) -> Void = { _ in },
        openClawClient: OpenClawHookClient = OpenClawHookClient()
    ) {
        self.settingsStore = settingsStore
        self.openClawClient = openClawClient
        self.openClawSettingsFingerprint = settingsStore.settings.openClaw.deliveryFingerprint
        self.dataSource = dataSource ?? LocalSessionLogDataSource(
            rootDirectory: URL(fileURLWithPath: settingsStore.settings.dataDirectoryPath, isDirectory: true)
        )
        self.snapshot = initialSnapshot ?? QuotaSnapshot(
            weeklyLimit: nil,
            secondaryLimit: nil,
            dailyTokens: 0,
            dailyTotals: [:],
            lastUpdatedAt: nil,
            sourceStatus: .waitingForSession
        )
        self.overlaySink = overlaySink
        self.notificationSink = notificationSink

        if shouldStartMonitoring {
            if settingsStore.settings.simulationMode {
                startSimulation()
            } else {
                startMonitoring()
            }
        }
    }

    public func startMonitoring() {
        guard monitor == nil, simulationTimer == nil else { return }

        let monitor = QuotaMonitor(dataSource: dataSource) { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.handle(snapshot: snapshot)
            }
        }
        self.monitor = monitor
        monitor.start()
    }

    public func stopMonitoring() {
        monitor?.stop()
        monitor = nil
    }

    public func applySettings(_ settings: AppSettings) {
        if settings.openClaw.deliveryFingerprint != openClawSettingsFingerprint {
            openClawSettingsFingerprint = settings.openClaw.deliveryFingerprint
            openClawDeliveryGeneration = UUID()
            openClawInFlightKeys.removeAll()
            pendingOpenClawAlerts.removeAll()
            pendingOpenClawCycleID = nil
            settingsStore.resetOpenClawPushState()
        }

        if settings.simulationMode {
            startSimulation()
        } else if simulationTimer != nil {
            stopSimulation()
            settingsStore.updateAlertState(.empty)
            startMonitoring()
        }
    }

    public func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        simulationResetDate = nil
        simulationFiveHourResetDate = nil
    }

    public func rescan() {
        guard let monitor else {
            isRefreshing = false
            return
        }
        isRefreshing = true
        monitor.refreshNow { [weak self] in
            Task { @MainActor [weak self] in
                self?.isRefreshing = false
            }
        }
    }

    public func setFastRefresh(_ enabled: Bool) {
        monitor?.setFastRefresh(enabled)
    }

    public func updateDataDirectory(_ url: URL) {
        dataSource = LocalSessionLogDataSource(rootDirectory: url)
        guard monitor != nil else { return }
        stopMonitoring()
        startMonitoring()
    }

    public func handle(snapshot: QuotaSnapshot) {
        let previousSnapshot = self.previousSnapshot
        let evaluation = alertEngine.evaluate(
            previous: previousSnapshot,
            current: snapshot,
            now: Date(),
            settings: settingsStore.settings.alertSettings,
            state: settingsStore.alertState
        )

        self.previousSnapshot = snapshot
        self.snapshot = snapshot
        self.isRefreshing = false
        settingsStore.updateAlertState(evaluation.updatedState)
        dispatchOpenClaw(
            previous: previousSnapshot,
            current: snapshot,
            alerts: evaluation.alerts
        )

        guard !evaluation.alerts.isEmpty else { return }
        lastAlert = evaluation.alerts.last

        for alert in evaluation.alerts {
            if settingsStore.settings.overlayAlertsEnabled {
                overlaySink(alert)
            }
            if settingsStore.settings.systemNotificationsEnabled {
                notificationSink(alert)
            }
        }

    }

    public func testOpenClaw() {
        let settings = settingsStore.settings.openClaw
        guard settings.enabled, settings.isAddressed,
              let token = settingsStore.openClawToken,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            settingsStore.updateOpenClawDeliveryStatus(.notConfigured)
            return
        }

        let event = OpenClawPushEvent(key: "test", kind: .test)
        dispatchOpenClawEvent(
            event,
            snapshot: snapshot,
            configuration: settings,
            token: token
        )
    }

    private func startSimulation() {
        guard simulationTimer == nil else { return }
        stopMonitoring()
        simulationUsedPercent = 20
        simulationResetDate = Date().addingTimeInterval(3 * 86_400)
        simulationFiveHourResetDate = Date().addingTimeInterval(5 * 3_600)
        emitSimulationSnapshot()

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceSimulation()
            }
        }
        simulationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceSimulation() {
        if simulationUsedPercent >= 100 {
            simulationUsedPercent = 20
            simulationResetDate = Date().addingTimeInterval(3 * 86_400)
        } else {
            simulationUsedPercent += 10
        }
        if let resetDate = simulationFiveHourResetDate, resetDate <= Date() {
            simulationFiveHourResetDate = Date().addingTimeInterval(5 * 3_600)
        }
        emitSimulationSnapshot()
    }

    private func emitSimulationSnapshot() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        handle(snapshot: QuotaSnapshot(
            weeklyLimit: RateLimitSnapshot(
                windowMinutes: 10_080,
                usedPercent: simulationUsedPercent,
                resetsAt: simulationResetDate,
                name: "simulation"
            ),
            secondaryLimit: RateLimitSnapshot(
                windowMinutes: 300,
                usedPercent: min(100, simulationUsedPercent * 1.25),
                resetsAt: simulationFiveHourResetDate,
                name: "simulation"
            ),
            dailyTokens: 24_000,
            dailyTotals: [today: 24_000],
            lastUpdatedAt: Date(),
            sourceStatus: .ready
        ))
    }

    private func dispatchOpenClaw(
        previous: QuotaSnapshot?,
        current: QuotaSnapshot,
        alerts: [QuotaAlert]
    ) {
        let settings = settingsStore.settings.openClaw
        guard settings.enabled else { return }

        if let currentCycleID = current.cycleID,
           pendingOpenClawCycleID != currentCycleID {
            pendingOpenClawAlerts.removeAll()
            pendingOpenClawCycleID = currentCycleID
        }
        if settings.alertsEnabled {
            for alert in alerts {
                let key = openClawPlanner.alertKey(for: alert, cycleID: current.cycleID)
                pendingOpenClawAlerts[key] = alert
            }
        }

        let pendingAlerts: [QuotaAlert]
        if current.cycleID == nil {
            // Keep failed weekly alerts queued, but wait for a snapshot with a
            // valid weekly cycle before retrying them with a complete summary.
            pendingAlerts = []
        } else {
            pendingAlerts = pendingOpenClawAlerts.values.sorted { lhs, rhs in
                openClawPlanner.alertKey(for: lhs, cycleID: current.cycleID)
                    < openClawPlanner.alertKey(for: rhs, cycleID: current.cycleID)
            }
        }
        let previousOpenClawState = settingsStore.openClawPushState
        let plan = openClawPlanner.evaluate(
            previous: previous,
            current: current,
            alerts: pendingAlerts,
            settings: settings,
            state: previousOpenClawState
        )
        if plan.state != previousOpenClawState {
            settingsStore.updateOpenClawPushState(plan.state)
        }

        guard let token = settingsStore.openClawToken,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !plan.events.isEmpty {
                settingsStore.updateOpenClawDeliveryStatus(.notConfigured)
            }
            return
        }

        for event in plan.events {
            dispatchOpenClawEvent(
                event,
                snapshot: current,
                configuration: settings,
                token: token
            )
        }
    }

    private func dispatchOpenClawEvent(
        _ event: OpenClawPushEvent,
        snapshot: QuotaSnapshot,
        configuration: OpenClawPushSettings,
        token: String
    ) {
        guard openClawInFlightKeys[event.key] == nil else { return }

        let message = OpenClawMessageFormatter.message(for: event, snapshot: snapshot)
        let generation = openClawDeliveryGeneration
        openClawInFlightKeys[event.key] = generation
        settingsStore.updateOpenClawDeliveryStatus(.sending)

        let client = openClawClient
        Task { [weak self] in
            do {
                try await client.send(
                    message: message,
                    configuration: configuration,
                    token: token
                )
                await MainActor.run { [weak self] in
                    self?.finishOpenClawEvent(event, generation: generation, succeeded: true)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.finishOpenClawEvent(event, generation: generation, succeeded: false)
                }
            }
        }
    }

    private func finishOpenClawEvent(
        _ event: OpenClawPushEvent,
        generation: UUID,
        succeeded: Bool
    ) {
        guard openClawInFlightKeys[event.key] == generation else { return }
        openClawInFlightKeys.removeValue(forKey: event.key)
        guard generation == openClawDeliveryGeneration else { return }

        if succeeded {
            let nextState = openClawPlanner.markDelivered(
                event,
                state: settingsStore.openClawPushState
            )
            settingsStore.updateOpenClawPushState(nextState)
            if case .alert = event.kind {
                pendingOpenClawAlerts.removeValue(forKey: event.key)
            }
            settingsStore.updateOpenClawDeliveryStatus(.delivered)
        } else {
            settingsStore.updateOpenClawDeliveryStatus(.failed)
        }
    }
}
