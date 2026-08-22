import Darwin
import Foundation

public final class QuotaMonitor: @unchecked Sendable {
    private let dataSource: LocalSessionLogDataSource
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let onSnapshot: @Sendable (QuotaSnapshot) -> Void
    private let queue = DispatchQueue(label: "com.codexquotanotch.monitor", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private var interval: TimeInterval = 10
    private var refreshGate = RefreshGate()
    private var isRunning = false

    public init(
        dataSource: LocalSessionLogDataSource,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        onSnapshot: @escaping @Sendable (QuotaSnapshot) -> Void
    ) {
        self.dataSource = dataSource
        self.calendar = calendar
        self.now = now
        self.onSnapshot = onSnapshot
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunning else { return }
            self.isRunning = true
            self.installDirectoryWatcher()
            self.installTimer()
            self.requestRefresh()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.directorySource?.cancel()
            self.directorySource = nil
            self.refreshGate.reset()
            if self.directoryDescriptor >= 0 {
                close(self.directoryDescriptor)
                self.directoryDescriptor = -1
            }
        }
    }

    public func setFastRefresh(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.interval = enabled ? 2 : 10
            guard self.isRunning else { return }
            self.installTimer()
        }
    }

    public func refreshNow() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.requestRefresh()
        }
    }

    private func requestRefresh(after delay: TimeInterval = 0) {
        guard isRunning, refreshGate.request() else { return }

        let refreshWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isRunning else {
                self.refreshGate.complete()
                return
            }

            self.refreshGate.complete()
            self.refresh()
        }

        if delay > 0 {
            queue.asyncAfter(deadline: .now() + delay, execute: refreshWork)
        } else {
            queue.async(execute: refreshWork)
        }
    }

    private func refresh() {
        do {
            onSnapshot(try dataSource.readSnapshot(now: now(), calendar: calendar))
        } catch let error as LocalSessionDataError {
            switch error {
            case .rootDirectoryUnavailable:
                onSnapshot(QuotaSnapshot(
                    weeklyLimit: nil,
                    secondaryLimit: nil,
                    dailyTokens: 0,
                    dailyTotals: [:],
                    lastUpdatedAt: nil,
                    sourceStatus: .unreadable(error.localizedDescription)
                ))
            }
        } catch {
            onSnapshot(QuotaSnapshot(
                weeklyLimit: nil,
                secondaryLimit: nil,
                dailyTokens: 0,
                dailyTotals: [:],
                lastUpdatedAt: nil,
                sourceStatus: .unreadable(error.localizedDescription)
            ))
        }
    }

    private func installTimer() {
        timer?.cancel()
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + interval, repeating: interval)
        newTimer.setEventHandler { [weak self] in
            self?.refresh()
        }
        newTimer.resume()
        timer = newTimer
    }

    private func installDirectoryWatcher() {
        guard directorySource == nil else { return }
        let descriptor = open(dataSource.rootDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        directoryDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.requestRefresh(after: 0.25)
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.directoryDescriptor >= 0 else { return }
            close(self.directoryDescriptor)
            self.directoryDescriptor = -1
        }
        source.resume()
        directorySource = source
    }
}

struct RefreshGate {
    private(set) var isPending = false

    mutating func request() -> Bool {
        guard !isPending else { return false }
        isPending = true
        return true
    }

    mutating func complete() {
        isPending = false
    }

    mutating func reset() {
        isPending = false
    }
}
