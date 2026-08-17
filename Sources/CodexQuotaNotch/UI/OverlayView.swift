import SwiftUI

public struct OverlayView: View {
    public let snapshot: QuotaSnapshot
    public let onOpenMainWindow: (() -> Void)?

    public init(snapshot: QuotaSnapshot, onOpenMainWindow: (() -> Void)? = nil) {
        self.snapshot = snapshot
        self.onOpenMainWindow = onOpenMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .shadow(color: .black.opacity(0.25), radius: 28, y: 12)
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
