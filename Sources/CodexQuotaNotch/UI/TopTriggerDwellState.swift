import Foundation

struct TopTriggerDwellState {
    static let defaultDwellTime: TimeInterval = 0.3

    let dwellTime: TimeInterval

    private var enteredAt: Date?
    private(set) var isActive = false

    init(dwellTime: TimeInterval = Self.defaultDwellTime) {
        self.dwellTime = max(0, dwellTime)
    }

    mutating func enter(at date: Date) {
        guard enteredAt == nil else { return }
        enteredAt = date
        isActive = false
    }

    mutating func leave() {
        enteredAt = nil
        isActive = false
    }

    mutating func activateIfReady(at date: Date) -> Bool {
        guard !isActive, let enteredAt else { return false }
        guard date.timeIntervalSince(enteredAt) >= dwellTime else { return false }
        isActive = true
        return true
    }
}
