import Foundation

public enum AppLanguage: String, CaseIterable {
    case traditionalChinese = "zh-Hant"
    case english = "en"

    public static let preferenceKey = "aibox.language"

    public static var selected: AppLanguage {
        get { loadSelection(defaults: .standard, preferredLanguages: Locale.preferredLanguages) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey) }
    }

    static func loadSelection(defaults: UserDefaults, preferredLanguages: [String]) -> AppLanguage {
        if let rawValue = defaults.string(forKey: preferenceKey),
           let saved = AppLanguage(rawValue: rawValue) { return saved }
        let initial = resolve(preferredLanguages: preferredLanguages)
        defaults.set(initial.rawValue, forKey: preferenceKey)
        return initial
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for language in preferredLanguages {
            let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
            if code == "zh" || code.hasPrefix("zh-") { return .traditionalChinese }
            if code == "en" || code.hasPrefix("en-") { return .english }
        }
        return .english
    }

    // Select a standard localization bundle explicitly for in-app language changes.
    // Prefer the installed app's resources over SwiftPM's development build path.
    public static var bundle: Bundle { selected.bundle }

    public var bundle: Bundle {
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("AIBoxMac_AIBoxCore.bundle")
        let resources = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
        // Avoid Bundle's preferred-language filtering when choosing an explicit
        // language. SwiftPM normalizes localization directory names to lowercase.
        for identifier in [rawValue, rawValue.lowercased()] {
            let url = resources.bundleURL.appendingPathComponent(identifier + ".lproj")
            if let localized = Bundle(url: url) { return localized }
        }
        return resources
    }
}
