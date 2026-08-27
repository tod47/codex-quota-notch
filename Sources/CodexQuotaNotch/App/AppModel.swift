import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var snapshot: QuotaSnapshot
    @Published public private(set) var lastAlert: QuotaAlert?

    public let settingsStore: SettingsStore

    private var dataSource: LocalSessionLogDataSource
    private var monitor: QuotaMonitor?
    private var simulationTimer: Timer?
    private var simulationResetDate: Date?
    private var simulationFiveHourResetDate: Date?
    private var simulationUsedPercent = 20.0
    private var previousSnapshot: QuotaSnapshot?
    private let alertEngine = AlertEngine()
    private let overlaySink: (QuotaAlert) -> Void
    private let notificationSink: (QuotaAlert) -> Void

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: LocalSessionLogDataSource? = nil,
        initialSnapshot: QuotaSnapshot? = nil,
        startMonitoring shouldStartMonitoring: Bool = true,
        overlaySink: @escaping (QuotaAlert) -> Void = { _ in },
        notificationSink: @escaping (QuotaAlert) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
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
        monitor?.refreshNow()
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
        let evaluation = alertEngine.evaluate(
            previous: previousSnapshot,
            current: snapshot,
            now: Date(),
            settings: settingsStore.settings.alertSettings,
            state: settingsStore.alertState
        )

        previousSnapshot = snapshot
        self.snapshot = snapshot
        settingsStore.updateAlertState(evaluation.updatedState)

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
}
