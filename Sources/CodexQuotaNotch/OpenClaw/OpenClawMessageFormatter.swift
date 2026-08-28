import Foundation

@MainActor
public enum OpenClawMessageFormatter {
    public static func message(
        for event: OpenClawPushEvent,
        snapshot: QuotaSnapshot
    ) -> String {
        switch event.kind {
        case .status:
            return statusMessage(for: snapshot)
        case .fiveHourReset:
            return [
                L10n.text("openclaw.message.five.hour.reset"),
                "",
                statusMessage(for: snapshot)
            ].joined(separator: "\n")
        case .alert(let alert):
            return [
                L10n.text(alert.titleKey),
                L10n.alertMessage(alert),
                "",
                statusMessage(for: snapshot)
            ].joined(separator: "\n")
        case .test:
            return L10n.text("openclaw.message.test")
        }
    }

    public static func statusMessage(for snapshot: QuotaSnapshot) -> String {
        var lines = [L10n.text("openclaw.message.status.title")]

        if snapshot.weeklyLimit != nil {
            lines.append(
                labeledLine(
                    L10n.text("quota.weekly"),
                    L10n.percentage(snapshot.remainingPercent)
                )
            )
            lines.append(
                labeledLine(
                    L10n.text("openclaw.message.resets"),
                    L10n.date(snapshot.resetsAt)
                )
            )
            lines.append(
                labeledLine(
                    L10n.text("openclaw.message.until.reset"),
                    L10n.countdown(until: snapshot.resetsAt)
                )
            )
        }

        if let fiveHourLimit = snapshot.fiveHourLimit {
            lines.append(
                labeledLine(
                    L10n.text("quota.five.hour"),
                    L10n.percentage(snapshot.fiveHourRemainingPercent)
                )
            )
            lines.append(
                labeledLine(
                    L10n.text("openclaw.message.resets"),
                    L10n.date(fiveHourLimit.resetsAt)
                )
            )
            lines.append(
                labeledLine(
                    L10n.text("openclaw.message.until.reset"),
                    L10n.countdown(until: fiveHourLimit.resetsAt)
                )
            )
        }

        lines.append(
            labeledLine(
                L10n.text("today.tokens"),
                L10n.number(snapshot.dailyTokens)
            )
        )
        return lines.joined(separator: "\n")
    }

    private static func labeledLine(_ label: String, _ value: String) -> String {
        "\(label)\(L10n.text("openclaw.separator"))\(value)"
    }
}
