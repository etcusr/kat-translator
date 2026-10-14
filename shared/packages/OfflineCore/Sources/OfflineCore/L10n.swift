import Foundation
import Observation

/// Shared observation updates existing views without recreating their state or reloading models.
@Observable public final class AppInterfaceLanguage: @unchecked Sendable {
    public static let shared = AppInterfaceLanguage()
    @ObservationIgnored private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var preference: String {
        get {
            access(keyPath: \.preference)
            let saved = defaults.string(forKey: "appInterfaceLanguage") ?? "system"
            return L10n.supportedLanguages.contains(saved) ? saved : "system"
        }
        set {
            withMutation(keyPath: \.preference) {
                defaults.set(L10n.supportedLanguages.contains(newValue) ? newValue : "system", forKey: "appInterfaceLanguage")
            }
        }
    }
}

/// UI strings live in the app's catalog. Model prompts and user text never pass through here.
public enum L10n {
    public static let supportedLanguages = ["ru", "en", "es", "tr"]
    public static func language(for preferences: [String]) -> String {
        for preference in preferences {
            let base = preference.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if supportedLanguages.contains(base) { return base }
        }
        return "en"
    }
    public static var language: String {
        let preference = AppInterfaceLanguage.shared.preference
        return preference == "system" ? language(for: Locale.preferredLanguages) : preference
    }
    public static var locale: Locale { Locale(identifier: language) }
    private static func localizedBundle(_ bundle: Bundle, language: String) -> Bundle {
        guard let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) else { return bundle }
        return localized
    }
    public static func text(_ value: Message, bundle: Bundle = .main, language: String? = nil) -> String {
        let language = language ?? self.language
        let template = localizedBundle(bundle, language: language).localizedString(forKey: value.key, value: value.key, table: "Localizable")
        if value.arguments.isEmpty { return template.replacingOccurrences(of: "%%", with: "%") }
        return String(format: template, locale: Locale(identifier: language), arguments: value.arguments)
    }
    /// Download sizes in decimal units of the app language (ByteCountFormatter follows the system
    /// language, so an English interface showed «ГБ»). Precision matches ByteCountFormatter:
    /// whole KB, one decimal for MB, two for GB.
    public static func bytes(_ value: Int64, language: String? = nil) -> String {
        let selected = language ?? self.language
        let russian = selected == "ru"
        let units = russian ? ["байт", "КБ", "МБ", "ГБ", "ТБ"] : ["bytes", "KB", "MB", "GB", "TB"]
        var amount = Double(max(0, value)), index = 0
        while amount >= 1000 && index < units.count - 1 { amount /= 1000; index += 1 }
        let format = NumberFormatter()
        format.locale = Locale(identifier: selected == "en" ? "en_US" : selected)
        format.numberStyle = .decimal
        let digits = index <= 1 ? 0 : index == 2 ? 1 : 2
        format.minimumFractionDigits = digits; format.maximumFractionDigits = digits
        return (format.string(from: NSNumber(value: amount)) ?? String(amount)) + "\u{00A0}" + units[index]
    }
    public static func retentionDays(_ count: Int, bundle: Bundle = .main, language: String? = nil) -> String {
        let language = language ?? self.language
        return String(localized: "Удалять через \(count) дней", bundle: localizedBundle(bundle, language: language), locale: Locale(identifier: language))
    }
    public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        fileprivate var key: String
        fileprivate var arguments: [String]
        public init(stringLiteral value: String) { key = value.replacingOccurrences(of: "%", with: "%%"); arguments = [] }
        public init(stringInterpolation value: StringInterpolation) { key = value.key; arguments = value.arguments }
        public struct StringInterpolation: StringInterpolationProtocol {
            fileprivate var key = ""
            fileprivate var arguments: [String] = []
            public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
            public mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
            public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
        }
    }
}
