import Foundation

public enum OpenClawPushEventKind: Equatable, Sendable {
    case status(fingerprint: String)
    case fiveHourReset(cycleID: String, fingerprint: String)
    case alert(QuotaAlert)
    case test
}

public struct OpenClawPushEvent: Equatable, Sendable {
    public let key: String
    public let kind: OpenClawPushEventKind

    public init(key: String, kind: OpenClawPushEventKind) {
        self.key = key
        self.kind = kind
    }
}

public struct OpenClawPushEvaluation: Equatable, Sendable {
    public let events: [OpenClawPushEvent]
    public let state: OpenClawPushState

    public init(events: [OpenClawPushEvent], state: OpenClawPushState) {
        self.events = events
        self.state = state
    }
}

public struct OpenClawPushPlanner: Sendable {
    public init() {}

    public func evaluate(
        previous: QuotaSnapshot?,
        current: QuotaSnapshot,
        alerts: [QuotaAlert],
        settings: OpenClawPushSettings,
        state: OpenClawPushState
    ) -> OpenClawPushEvaluation {
        guard settings.enabled, settings.isAddressed else {
            return OpenClawPushEvaluation(events: [], state: state)
        }

        var nextState = state
        var events: [OpenClawPushEvent] = []
        let currentFiveHourCycleID = QuotaMath.cycleID(for: current.fiveHourLimit?.resetsAt)

        if let currentFiveHourCycleID {
            if let observedFiveHourCycleID = nextState.observedFiveHourCycleID,
               observedFiveHourCycleID != currentFiveHourCycleID {
                nextState.pendingFiveHourCycleID = currentFiveHourCycleID
            }
            nextState.observedFiveHourCycleID = currentFiveHourCycleID
        }

        if settings.statusUpdatesEnabled,
           let fingerprint = statusFingerprint(for: current) {
            let resetIsPending = nextState.pendingFiveHourCycleID != nil
                && nextState.pendingFiveHourCycleID != nextState.lastDeliveredFiveHourCycleID
            if !resetIsPending, nextState.lastDeliveredStatusFingerprint != fingerprint {
                events.append(
                    OpenClawPushEvent(
                        key: "status:\(fingerprint)",
                        kind: .status(fingerprint: fingerprint)
                    )
                )
            }
        }

        if settings.statusUpdatesEnabled,
           let pendingFiveHourCycleID = nextState.pendingFiveHourCycleID,
           pendingFiveHourCycleID != nextState.lastDeliveredFiveHourCycleID,
           let fingerprint = statusFingerprint(for: current) {
            events.insert(
                OpenClawPushEvent(
                    key: "five-hour-reset:\(pendingFiveHourCycleID)",
                    kind: .fiveHourReset(
                        cycleID: pendingFiveHourCycleID,
                        fingerprint: fingerprint
                    )
                ),
                at: 0
            )
        }

        if settings.alertsEnabled {
            events.append(contentsOf: alerts.map { alert in
                OpenClawPushEvent(
                    key: alertKey(for: alert, cycleID: current.cycleID),
                    kind: .alert(alert)
                )
            })
        }

        // The previous snapshot remains part of the interface so callers can use
        // the same planner for future event types without changing its contract.
        _ = previous
        return OpenClawPushEvaluation(events: events, state: nextState)
    }

    public func markDelivered(
        _ event: OpenClawPushEvent,
        state: OpenClawPushState
    ) -> OpenClawPushState {
        var nextState = state
        switch event.kind {
        case .status(let fingerprint):
            nextState.lastDeliveredStatusFingerprint = fingerprint
        case .fiveHourReset(let cycleID, let fingerprint):
            nextState.lastDeliveredStatusFingerprint = fingerprint
            nextState.lastDeliveredFiveHourCycleID = cycleID
            if nextState.pendingFiveHourCycleID == cycleID {
                nextState.pendingFiveHourCycleID = nil
            }
        case .alert, .test:
            break
        }
        return nextState
    }

    public func alertKey(for alert: QuotaAlert, cycleID: String?) -> String {
        "alert:\(cycleID ?? "unknown"):\(alertKindKey(alert.kind))"
    }

    private func statusFingerprint(for snapshot: QuotaSnapshot) -> String? {
        guard snapshot.weeklyLimit != nil || snapshot.fiveHourLimit != nil else {
            return nil
        }

        let weekly = "\(snapshot.remainingPercent.map(String.init) ?? "-"):\(QuotaMath.cycleID(for: snapshot.weeklyLimit?.resetsAt) ?? "-")"
        let fiveHour = "\(snapshot.fiveHourRemainingPercent.map(String.init) ?? "-"):\(QuotaMath.cycleID(for: snapshot.fiveHourLimit?.resetsAt) ?? "-")"
        return "weekly:\(weekly)|five-hour:\(fiveHour)"
    }

    private func alertKindKey(_ kind: AlertKind) -> String {
        switch kind {
        case .percentage(let value): return "percentage:\(value)"
        case .countdown(let hours): return "countdown:\(hours)"
        case .reset: return "reset"
        case .exhausted: return "exhausted"
        }
    }
}
