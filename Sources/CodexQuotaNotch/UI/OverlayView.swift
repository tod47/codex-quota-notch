import SwiftUI

public struct OverlayView: View {
    public let snapshot: QuotaSnapshot
    public let alert: QuotaAlert?
    public let onOpenMainWindow: (() -> Void)?
    public let onRefresh: (() -> Void)?
    public let showFiveHourQuota: Bool

    public init(
        snapshot: QuotaSnapshot,
        alert: QuotaAlert? = nil,
        onOpenMainWindow: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        showFiveHourQuota: Bool = true
    ) {
        self.snapshot = snapshot
        self.alert = alert
        self.onOpenMainWindow = onOpenMainWindow
        self.onRefresh = onRefresh
        self.showFiveHourQuota = showFiveHourQuota
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let alert {
                AlertBanner(alert: alert, color: alertColor(for: alert))
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("app.title"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.text("app.quota"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(L10n.percentage(snapshot.remainingPercent))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(L10n.text("remaining"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(snapshot.remainingPercent ?? 0), total: 100)
                .tint(statusColor)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: L10n.text("resets"), value: L10n.date(snapshot.resetsAt))
                InfoRow(label: L10n.text("reset.countdown"), value: L10n.countdown(until: snapshot.resetsAt))

                if shouldShowFiveHourQuota, let fiveHourLimit = snapshot.fiveHourLimit {
                    Divider()
                        .padding(.vertical, 2)
                    FiveHourQuotaSection(
                        limit: fiveHourLimit,
                        remainingPercent: snapshot.fiveHourRemainingPercent
                    )
                }

                InfoRow(label: L10n.text("today.tokens"), value: L10n.number(snapshot.dailyTokens))
            }

            Divider()

            HStack {
                Text(statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("refresh"))
                }
                if let onOpenMainWindow {
                    Button(action: onOpenMainWindow) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("open.main.window"))
                }
            }
        }
        .padding(18)
        .frame(width: 286)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var statusColor: Color {
        quotaStatusColor(for: snapshot.remainingPercent)
    }

    private var accessibilitySummary: String {
        var values = [
            "\(L10n.text("quota.weekly")), \(L10n.percentage(snapshot.remainingPercent))"
        ]
        if shouldShowFiveHourQuota {
            values.append(
                "\(L10n.text("quota.five.hour")), \(L10n.percentage(snapshot.fiveHourRemainingPercent))"
            )
        }
        return values.joined(separator: ", ")
    }

    var shouldShowFiveHourQuota: Bool {
        showFiveHourQuota && snapshot.fiveHourLimit != nil
    }

    private var statusText: String {
        switch snapshot.sourceStatus {
        case .ready:
            return L10n.text("source.ready")
        case .waitingForSession:
            return L10n.text("source.waiting")
        case .missingWeeklyLimit:
            return L10n.text("source.missing.weekly")
        case .stale:
            return L10n.text("source.stale")
        case .unreadable:
            return L10n.text("source.unreadable")
        }
    }

    private func alertColor(for alert: QuotaAlert) -> Color {
        switch alert.kind {
        case .exhausted:
            return .red
        case .percentage(let value) where value <= 10:
            return .red
        case .percentage:
            return .orange
        case .countdown, .reset:
            return .blue
        }
    }
}

private struct FiveHourQuotaSection: View {
    let limit: RateLimitSnapshot
    let remainingPercent: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(L10n.text("quota.five.hour"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                Text(L10n.percentage(remainingPercent))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: Double(remainingPercent ?? 0), total: 100)
                .tint(quotaStatusColor(for: remainingPercent))

            VStack(alignment: .leading, spacing: 5) {
                InfoRow(label: L10n.text("resets"), value: L10n.date(limit.resetsAt))
                InfoRow(
                    label: L10n.text("reset.countdown"),
                    value: L10n.countdown(until: limit.resetsAt)
                )
            }
        }
        .padding(10)
        .background(
            .primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private func quotaStatusColor(for remaining: Int?) -> Color {
    guard let remaining else { return .secondary }
    if remaining <= 10 { return .red }
    if remaining <= 30 { return .orange }
    return .mint
}

private struct AlertBanner: View {
    let alert: QuotaAlert
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(alert.titleKey))
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.alertMessage(alert))
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        }
    }

    private var iconName: String {
        switch alert.kind {
        case .percentage(let value):
            return value <= 10 ? "exclamationmark.triangle.fill" : "chart.bar"
        case .countdown:
            return "clock.badge.exclamationmark"
        case .reset:
            return "arrow.clockwise.circle.fill"
        case .exhausted:
            return "xmark.octagon.fill"
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
    }
}
