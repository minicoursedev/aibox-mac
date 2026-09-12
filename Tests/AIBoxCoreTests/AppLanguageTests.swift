import XCTest
@testable import AIBoxCore

final class AppLanguageTests: XCTestCase {
    func testFirstLaunchChoosesAndSavesSystemLanguage() {
        let name = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppLanguage.loadSelection(defaults: defaults, preferredLanguages: ["zh-Hant-TW", "en"]), .traditionalChinese)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.preferenceKey), "zh-Hant")
        // Later system changes must not override the choice saved on first launch.
        XCTAssertEqual(AppLanguage.loadSelection(defaults: defaults, preferredLanguages: ["en-US"]), .traditionalChinese)
        defaults.set("en", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.loadSelection(defaults: defaults, preferredLanguages: ["zh-TW"]), .english)
    }

    func testSystemLanguagePriorityAndFallback() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["en-GB", "zh-Hant"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["ja-JP", "zh-TW", "en"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh_HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: []), .english)
    }
    func testNativeCatalogTranslationsAndInterpolation() {
        let chinese = AppLanguage.traditionalChinese.bundle
        let english = AppLanguage.english.bundle
        XCTAssertEqual(chinese.bundleURL.lastPathComponent.lowercased(), "zh-hant.lproj")
        XCTAssertEqual(english.bundleURL.lastPathComponent, "en.lproj")
        XCTAssertEqual(String(localized: "AIBox Settings", bundle: chinese), "AIBox 設定")
        XCTAssertEqual(String(localized: "AIBox Settings", bundle: english), "AIBox Settings")
        let days = 2, hours = 3
        XCTAssertEqual(String(localized: "In \(String(days))d \(String(hours))h", bundle: chinese), "2天3小時後")
        XCTAssertEqual(String(localized: "In \(String(days))d \(String(hours))h", bundle: english), "In 2d 3h")
    }

    @MainActor
    func testSwitchingLanguageRefreshesExistingStatusImmediately() {
        let previous = UserDefaults.standard.object(forKey: AppLanguage.preferenceKey)
        defer { UserDefaults.standard.set(previous, forKey: AppLanguage.preferenceKey) }
        AppLanguage.selected = .traditionalChinese
        let connection = RemoteNotificationConnection()
        var displayed = ""
        connection.onStatus = { displayed = $0 }
        connection.connect(host: "invalid host")
        XCTAssertEqual(displayed, "請輸入 SSH 主機別名，例如 srv；不含空白或連線參數。")
        AppLanguage.selected = .english
        connection.refreshLanguage()
        XCTAssertEqual(displayed, "Enter an SSH host alias, such as srv, without spaces or connection options.")
        XCTAssertEqual(String(localized: "AIBox Settings", bundle: AppLanguage.bundle), "AIBox Settings")
        XCTAssertFalse(connection.isEnabled)
        AppLanguage.selected = .traditionalChinese
        connection.refreshLanguage()
        XCTAssertEqual(displayed, "請輸入 SSH 主機別名，例如 srv；不含空白或連線參數。")
        XCTAssertEqual(String(localized: "AIBox Settings", bundle: AppLanguage.bundle), "AIBox 設定")
        XCTAssertFalse(connection.isEnabled)
    }

}
