import SwiftUI

public struct OverlayView: View {
    public let snapshot: QuotaSnapshot
    public let alert: QuotaAlert?
    public let onOpenMainWindow: (() -> Void)?

    public init(
        snapshot: QuotaSnapshot,
        alert: QuotaAlert? = nil,
        onOpenMainWindow: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.alert = alert
        self.onOpenMainWindow = onOpenMainWindow
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
                    Text(L10n.text("app.weekly.quota"))
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
                InfoRow(label: L10n.text("today.tokens"), value: L10n.number(snapshot.dailyTokens))
            }

            Divider()

            HStack {
                Text(statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
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
        .accessibilityLabel("\(L10n.text("app.weekly.quota")), \(L10n.percentage(snapshot.remainingPercent))")
    }

    private var statusColor: Color {
        guard let remaining = snapshot.remainingPercent else { return .secondary }
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .mint
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
