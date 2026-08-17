import AppKit

@MainActor
final class TopTriggerMonitor {
    var onLocationChanged: ((NSPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            _ = event
            self?.onLocationChanged?(NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.onLocationChanged?(NSEvent.mouseLocation)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    static func triggerRect(for screen: NSScreen, width: CGFloat = 240, height: CGFloat = 44) -> NSRect {
        NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
