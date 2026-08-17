import Foundation

public struct QuotaAlert: Equatable, Sendable {
    public let kind: AlertKind
    public let titleKey: String
    public let messageKey: String
    public let values: [String: String]

    public init(kind: AlertKind, titleKey: String, messageKey: String, values: [String: String] = [:]) {
        self.kind = kind
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.values = values
    }
}

public struct AlertEvaluation: Equatable, Sendable {
    public let alerts: [QuotaAlert]
    public let updatedState: AlertState

    public init(alerts: [QuotaAlert], updatedState: AlertState) {
        self.alerts = alerts
        self.updatedState = updatedState
    }
}

public struct AlertEngine: Sendable {
    public init() {}

    public func evaluate(
        previous: QuotaSnapshot?,
        current: QuotaSnapshot,
        now: Date,
        settings: AlertSettings,
        state: AlertState
    ) -> AlertEvaluation {
        var nextState = state
        var cycleChanged = false

        if let currentCycleID = current.cycleID {
            let storedCycleID = QuotaMath.normalizedCycleID(nextState.cycleID)
            if let storedCycleID, storedCycleID != currentCycleID {
                nextState = AlertState(cycleID: currentCycleID)
                cycleChanged = true
            } else {
                nextState.cycleID = currentCycleID
            }
        }

        func emit(_ kind: AlertKind, state: inout AlertState) -> QuotaAlert? {
            let key = key(for: kind)
            guard !state.emittedKeys.contains(key) else { return nil }
            state.emittedKeys.insert(key)
            return makeAlert(for: kind)
        }

        if let remaining = current.remainingPercent,
           remaining <= 0,
           settings.exhaustedAlertsEnabled,
           let alert = emit(.exhausted, state: &nextState) {
            return AlertEvaluation(alerts: [alert], updatedState: nextState)
        }

        if cycleChanged,
           settings.resetAlertsEnabled,
           let alert = emit(.reset, state: &nextState) {
            return AlertEvaluation(alerts: [alert], updatedState: nextState)
        }

        if settings.countdownAlertsEnabled,
           let resetsAt = current.resetsAt,
           let countdownHours = countdownCandidate(resetsAt: resetsAt, now: now, settings: settings, state: nextState),
           let alert = emit(.countdown(hours: countdownHours), state: &nextState) {
            return AlertEvaluation(alerts: [alert], updatedState: nextState)
        }

        if let remaining = current.remainingPercent {
            let previousRemaining = previous?.remainingPercent
            if settings.criticalAlertsEnabled,
               remaining > 0,
               remaining <= settings.criticalStart,
               let critical = criticalCandidate(
                   previousRemaining: previousRemaining,
                   remaining: remaining,
                   settings: settings
               ),
               let alert = emit(.percentage(critical), state: &nextState) {
                return AlertEvaluation(alerts: [alert], updatedState: nextState)
            }

            if settings.percentageAlertsEnabled,
               let ordinary = ordinaryCandidate(
                   previousRemaining: previousRemaining,
                   remaining: remaining,
                   settings: settings
               ),
               let alert = emit(.percentage(ordinary), state: &nextState) {
                return AlertEvaluation(alerts: [alert], updatedState: nextState)
            }
        }

        return AlertEvaluation(alerts: [], updatedState: nextState)
    }

    private func ordinaryCandidate(previousRemaining: Int?, remaining: Int, settings: AlertSettings) -> Int? {
        let step = max(1, settings.ordinaryStep)
        let highestThreshold = 100 - step
        guard remaining <= highestThreshold else { return nil }
        let roundedUp = Int(ceil(Double(remaining) / Double(step))) * step
        guard roundedUp > settings.criticalStart,
              crossedThreshold(previous: previousRemaining, current: remaining, threshold: roundedUp) else {
            return nil
        }
        return roundedUp
    }

    private func criticalCandidate(previousRemaining: Int?, remaining: Int, settings: AlertSettings) -> Int? {
        let step = max(1, settings.criticalStep)
        let candidate = (remaining / step) * step
        guard candidate > 0,
              crossedThreshold(previous: previousRemaining, current: remaining, threshold: candidate) else {
            return nil
        }
        return candidate
    }

    private func crossedThreshold(previous: Int?, current: Int, threshold: Int) -> Bool {
        guard let previous else { return false }
        return previous > threshold && current <= threshold
    }

    private func countdownCandidate(
        resetsAt: Date,
        now: Date,
        settings: AlertSettings,
        state: AlertState
    ) -> Int? {
        let secondsRemaining = resetsAt.timeIntervalSince(now)
        guard secondsRemaining > 0 else { return nil }

        return settings.countdownHours
            .filter { $0 > 0 && secondsRemaining <= Double($0) * 60 * 60 }
            .sorted()
            .first(where: { !state.emittedKeys.contains(key(for: .countdown(hours: $0))) })
    }

    private func key(for kind: AlertKind) -> String {
        switch kind {
        case .percentage(let value):
            return "percentage:\(value)"
        case .countdown(let hours):
            return "countdown:\(hours)"
        case .reset:
            return "reset"
        case .exhausted:
            return "exhausted"
        }
    }

    private func makeAlert(for kind: AlertKind) -> QuotaAlert {
        switch kind {
        case .percentage(let value):
            return QuotaAlert(
                kind: kind,
                titleKey: "alert.percentage.title",
                messageKey: "alert.percentage.message",
                values: ["percent": String(value)]
            )
        case .countdown(let hours):
            let messageKey: String
            switch hours {
            case 48: messageKey = "alert.countdown.twoDays"
            case 24: messageKey = "alert.countdown.oneDay"
            case 5: messageKey = "alert.countdown.fiveHours"
            default: messageKey = "alert.countdown.generic"
            }
            return QuotaAlert(kind: kind, titleKey: "alert.countdown.title", messageKey: messageKey, values: ["hours": String(hours)])
        case .reset:
            return QuotaAlert(kind: kind, titleKey: "alert.reset.title", messageKey: "alert.reset", values: [:])
        case .exhausted:
            return QuotaAlert(kind: kind, titleKey: "alert.exhausted.title", messageKey: "alert.exhausted", values: [:])
        }
    }
}
