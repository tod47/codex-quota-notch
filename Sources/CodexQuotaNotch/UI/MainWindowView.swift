import SwiftUI

public struct MainWindowView: View {
    public let snapshot: QuotaSnapshot
    @ObservedObject public var settingsStore: SettingsStore
    public let onRescan: () -> Void
    public let onChooseDataDirectory: () -> Void

    @State private var selectedSection: MainSection = .appearance

    public init(
        snapshot: QuotaSnapshot,
        settingsStore: SettingsStore,
        onRescan: @escaping () -> Void = {},
        onChooseDataDirectory: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.settingsStore = settingsStore
        self.onRescan = onRescan
        self.onChooseDataDirectory = onChooseDataDirectory
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(MainSection.allCases, id: \.self) { section in
                    Label(L10n.text(section.localizationKey), systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .id(settingsStore.settings.language)
            .navigationTitle(L10n.text("app.title"))
            .frame(minWidth: 190)
        } detail: {
            Group {
                switch selectedSection {
                case .overview:
                    OverviewPage(snapshot: snapshot)
                case .alerts:
                    AlertsPage(settingsStore: settingsStore)
                case .appearance:
                    AppearancePage(settingsStore: settingsStore)
                case .data:
                    DataPrivacyPage(snapshot: snapshot, settingsStore: settingsStore, onRescan: onRescan, onChooseDataDirectory: onChooseDataDirectory)
                }
            }
            .frame(minWidth: 610, maxWidth: .infinity, maxHeight: .infinity)
            .id(settingsStore.settings.language)
        }
        .frame(minWidth: 820, minHeight: 560)
        .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: {
                settingsStore.settings[keyPath: keyPath] = $0
                settingsStore.save()
            }
        )
    }
}

private enum MainSection: String, CaseIterable, Hashable {
    case overview
    case alerts
    case appearance
    case data

    var localizationKey: String {
        switch self {
        case .overview: return "overview"
        case .alerts: return "alerts"
        case .appearance: return "appearance.display"
        case .data: return "data.privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .alerts: return "bell.badge"
        case .appearance: return "paintbrush"
        case .data: return "lock.shield"
        }
    }
}

private struct OverviewPage: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L10n.text("overview"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                HStack(alignment: .top, spacing: 18) {
                    OverlayView(snapshot: snapshot)
                    VStack(alignment: .leading, spacing: 12) {
                        MetricCard(title: L10n.text("weekly.remaining"), value: L10n.percentage(snapshot.remainingPercent), systemImage: "gauge.with.dots.needle.67percent")
                        MetricCard(title: L10n.text("today.usage"), value: L10n.number(snapshot.dailyTokens), systemImage: "number")
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("recent.seven.days"))
                        .font(.headline)
                    DailyUsageChart(dailyTotals: snapshot.dailyTotals)
                }
            }
            .padding(28)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DailyUsageChart: View {
    let dailyTotals: [Date: Int]

    var body: some View {
        let points = recentPoints
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(points, id: \.date) { point in
                VStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(height: barHeight(for: point.value))
                    Text(point.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 130, alignment: .bottom)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if points.allSatisfy({ $0.value == 0 }) {
                Text(L10n.text("no.history"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentPoints: [(date: Date, value: Int)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
            return (date, dailyTotals[date, default: 0])
        }
    }

    private func barHeight(for value: Int) -> CGFloat {
        let maximum = max(1, recentPoints.map(\.value).max() ?? 1)
        return max(5, CGFloat(value) / CGFloat(maximum) * 82)
    }
}

private struct AlertsPage: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section(L10n.text("alerts")) {
                Toggle(L10n.text("percentage.alerts"), isOn: binding(\.percentageAlertsEnabled))
                Toggle(L10n.text("critical.alerts"), isOn: binding(\.criticalAlertsEnabled))
                Toggle(L10n.text("countdown.alerts"), isOn: binding(\.countdownAlertsEnabled))
                Toggle(L10n.text("reset.alerts"), isOn: binding(\.resetAlertsEnabled))
                Toggle(L10n.text("exhausted.alerts"), isOn: binding(\.exhaustedAlertsEnabled))
            }

            Section(L10n.text("thresholds")) {
                Stepper(value: binding(\.ordinaryStep), in: 1...50) {
                    LabeledContent(L10n.text("ordinary.step"), value: "\(settingsStore.settings.ordinaryStep)%")
                }
                Stepper(value: binding(\.criticalStart), in: 1...50) {
                    LabeledContent(L10n.text("critical.start"), value: "\(settingsStore.settings.criticalStart)%")
                }
                Stepper(value: binding(\.criticalStep), in: 1...10) {
                    LabeledContent(L10n.text("critical.step"), value: "\(settingsStore.settings.criticalStep)%")
                }
            }

            Section(L10n.text("channels")) {
                Toggle(L10n.text("overlay.alerts"), isOn: binding(\.overlayAlertsEnabled))
                Toggle(L10n.text("system.notifications"), isOn: binding(\.systemNotificationsEnabled))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .id(settingsStore.settings.language)
        .navigationTitle(L10n.text("alerts"))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: {
                settingsStore.settings[keyPath: keyPath] = $0
                settingsStore.save()
            }
        )
    }
}

private struct AppearancePage: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section(L10n.text("appearance")) {
                Picker(L10n.text("language"), selection: binding(\.language)) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(L10n.text(language.localizationKey)).tag(language)
                    }
                }
                Picker(L10n.text("appearance"), selection: binding(\.appearance)) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(L10n.text(mode.localizationKey)).tag(mode)
                    }
                }
                Picker(L10n.text("display.mode"), selection: binding(\.displayMode)) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(L10n.text(mode.localizationKey)).tag(mode)
                    }
                }
                Toggle(L10n.text("launch.at.login"), isOn: binding(\.launchAtLogin))
            }

            Section(L10n.text("floating")) {
                LabeledContent(L10n.text("width"), value: "\(Int(settingsStore.settings.floatingFrame.width)) pt")
                LabeledContent(L10n.text("height"), value: "\(Int(settingsStore.settings.floatingFrame.height)) pt")
                Button(L10n.text("reset.floating.frame")) {
                    settingsStore.resetFloatingFrame()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .id(settingsStore.settings.language)
        .navigationTitle(L10n.text("appearance.display"))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: {
                settingsStore.settings[keyPath: keyPath] = $0
                settingsStore.save()
            }
        )
    }
}

private struct DataPrivacyPage: View {
    let snapshot: QuotaSnapshot
    @ObservedObject var settingsStore: SettingsStore
    let onRescan: () -> Void
    let onChooseDataDirectory: () -> Void

    var body: some View {
        Form {
            Section(L10n.text("data.source")) {
                LabeledContent(L10n.text("data.path")) {
                    Text(settingsStore.settings.dataDirectoryPath)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L10n.text("last.updated"), value: L10n.date(snapshot.lastUpdatedAt))
                LabeledContent(L10n.text("status"), value: sourceStatus)
                HStack {
                    Button(L10n.text("choose.folder"), action: onChooseDataDirectory)
                    Button(L10n.text("rescan"), action: onRescan)
                }
            }

            Section(L10n.text("simulation")) {
                Toggle(L10n.text("simulation"), isOn: binding(\.simulationMode))
                Text(L10n.text("simulation.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("data.privacy")) {
                Label(L10n.text("privacy.local.only"), systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .id(settingsStore.settings.language)
        .navigationTitle(L10n.text("data.privacy"))
    }

    private var sourceStatus: String {
        switch snapshot.sourceStatus {
        case .ready: return L10n.text("source.ready")
        case .waitingForSession: return L10n.text("source.waiting")
        case .missingWeeklyLimit: return L10n.text("source.missing.weekly")
        case .stale: return L10n.text("source.stale")
        case .unreadable: return L10n.text("source.unreadable")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: {
                settingsStore.settings[keyPath: keyPath] = $0
                settingsStore.save()
            }
        )
    }
}

private extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var localizationKey: String {
        switch self {
        case .system: return "system"
        case .light: return "light"
        case .dark: return "dark"
        }
    }
}

private extension AppLanguage {
    var localizationKey: String {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .chineseSimplified: return "language.chinese"
        }
    }
}

private extension DisplayMode {
    var localizationKey: String {
        switch self {
        case .topPopup: return "top.popup"
        case .topPersistent: return "top.persistent"
        case .floating: return "floating"
        }
    }
}
