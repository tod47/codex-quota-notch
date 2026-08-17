import Foundation

public enum L10n {
    public static func stringsURL(forLanguage language: String) -> URL? {
        let directory = "\(language.lowercased()).lproj"
        return Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: directory)
    }

    public static func text(_ key: String, values: [String: String] = [:]) -> String {
        var value = NSLocalizedString(key, tableName: "Localizable", bundle: .module, value: key, comment: "")
        for (name, replacement) in values {
            value = value.replacingOccurrences(of: "{{\(name)}}", with: replacement)
        }
        return value
    }

    public static func number(_ value: Int) -> String {
        value.formatted(.number)
    }

    public static func percentage(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)%"
    }

    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func countdown(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func alertMessage(_ alert: QuotaAlert) -> String {
        text(alert.messageKey, values: alert.values)
    }
}
