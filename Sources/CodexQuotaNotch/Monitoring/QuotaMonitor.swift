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
            self.refresh()
            self.installDirectoryWatcher()
            self.installTimer()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.directorySource?.cancel()
            self.directorySource = nil
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
            self.installTimer()
        }
    }

    private func refresh() {
        guard let snapshot = try? dataSource.readSnapshot(now: now(), calendar: calendar) else { return }
        onSnapshot(snapshot)
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
            self?.refresh()
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
