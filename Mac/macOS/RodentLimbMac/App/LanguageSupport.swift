// LanguageSupport.swift — switching between English and Simplified Chinese inside the app.
//
// Every RodentLimb string is written in both languages (L("English", "中文")) and follows the choice
// at once: the window and the Settings window are rebuilt when it changes, nothing is lost (the
// library state lives in the store, the page in AppModel).
// Menus and dialogs that macOS itself provides (Edit, Window, Open / Save panels, Quit …) follow the
// app's language list (AppleLanguages in this app's defaults — the same setting as System Settings ›
// General › Language & Region › Applications). That list is read when the app starts, so the app
// offers to relaunch after a change; the running batch is stopped and saved first and continues
// after the relaunch.
//
// Exported files stay in English whatever the interface language.

import SwiftUI
import AppKit

enum LanguageSwitch {
    static let appleLanguagesKey = "AppleLanguages"

    static var current: AppLanguage { AppLanguage.current }

    /// Chooses the interface language. Returns true when the system menus need a relaunch to follow.
    @discardableResult
    static func set(_ lang: AppLanguage) -> Bool {
        let d = UserDefaults.standard
        d.set(lang.rawValue, forKey: AppLanguage.storageKey)
        switch lang {
        case .system: d.removeObject(forKey: appleLanguagesKey)
        case .zh: d.set(["zh-Hans", "en"], forKey: appleLanguagesKey)
        case .en: d.set(["en", "zh-Hans"], forKey: appleLanguagesKey)
        }
        Lang.invalidate()
        return systemMenusChinese != wantsChineseSystemMenus(lang)
    }

    /// Language the system menus were built with at launch.
    private static let launchedChinese: Bool = {
        (Bundle.main.preferredLocalizations.first ?? "en").lowercased().hasPrefix("zh")
    }()

    static var systemMenusChinese: Bool { launchedChinese }

    private static func wantsChineseSystemMenus(_ lang: AppLanguage) -> Bool {
        switch lang {
        case .zh: return true
        case .en: return false
        case .system:
            // With this app's override removed, the standard defaults return the system-wide list.
            let first = UserDefaults.standard.stringArray(forKey: appleLanguagesKey)?.first
            return (first ?? Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
        }
    }

    /// Quits and opens the app again (after the batch was stopped and the library saved).
    @MainActor
    static func relaunch(_ app: AppModel) async {
        await app.prepareForQuit()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if error == nil { NSApp.terminate(nil) } else { app.relaunchFailed() }
                }
            }
        }
    }
}

/// "Language · 语言" picker used in the menu bar, the sidebar and the welcome page. The label is
/// always shown in both languages so it can be found whatever language is on screen.
struct LanguagePicker: View {
    let app: AppModel
    var compact = false
    /// Called when the system menus need a relaunch to follow (default: ask in the main window).
    var onRelaunchSuggested: (() -> Void)?
    @AppStorage(AppLanguage.storageKey) private var language = "system"

    var body: some View {
        if compact {
            // Sidebar footer: a small bordered button ("EN" / "中文") that opens the three choices.
            Menu {
                picker.pickerStyle(.inline)
            } label: {
                Text(L("EN", "中文"))
            }
            .menuStyle(.button)
            .controlSize(.small)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Language · 语言")
            .accessibilityLabel("Language · 语言")
        } else {
            picker
                .help("Language · 语言")
        }
    }

    private var picker: some View {
        Picker(selection: Binding(get: { language }, set: { choose($0) })) {
            Text("Follow System · 跟随系统").tag(AppLanguage.system.rawValue)
            Text("English").tag(AppLanguage.en.rawValue)
            Text("简体中文").tag(AppLanguage.zh.rawValue)
        } label: {
            Text("Language · 语言")
        }
    }

    private func choose(_ raw: String) {
        let lang = AppLanguage(rawValue: raw) ?? .system
        guard raw != language else { return }
        guard LanguageSwitch.set(lang) else { return }
        if let onRelaunchSuggested { onRelaunchSuggested() } else { app.languageRelaunchSuggested = true }
    }
}
