// L10n.swift — in-app English / Chinese switching.
//
// Every visible string is written once with both languages side by side: L("English", "中文").
// Nothing can be "missing" from a catalog, and switching language inside the app takes effect
// immediately (RodentLimbApp rebuilds the view tree when the preference changes).
//
// Rule: exported files (CSV, methods text) and saved keys ALWAYS use English, independent of
// the interface language. Use `LText.en` for those, never `L(...)`.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zh
    var id: String { rawValue }
    static let storageKey = "rl.uiLanguage"

    var pickerLabel: String {
        switch self {
        case .system: return L("Follow system", "跟随系统")
        case .en: return "English"
        case .zh: return "中文"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "system") ?? .system
    }

    /// Locale used for system-provided formatting inside the app (dates, pickers).
    static func locale(for raw: String) -> Locale {
        switch AppLanguage(rawValue: raw) ?? .system {
        case .zh: return Locale(identifier: "zh-Hans")
        case .en: return Locale(identifier: "en")
        case .system: return Locale(identifier: Locale.preferredLanguages.first ?? "en")
        }
    }
}

enum Lang {
    // `L(...)` is called for every visible string, thousands of times per screen update (event
    // lists, charts). Reading UserDefaults and Locale.preferredLanguages each time showed up as
    // main-thread time while scrolling, so the answer is cached and recomputed only after a
    // defaults change (which includes the in-app language picker).
    private static let lock = NSLock()
    private static var cached: Bool?
    private static var generation = 0
    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in Lang.invalidate() }

    static func invalidate() {
        lock.lock()
        cached = nil
        generation += 1
        lock.unlock()
    }

    static var isChinese: Bool {
        _ = observer
        lock.lock()
        if let c = cached { lock.unlock(); return c }
        let gen = generation
        lock.unlock()
        let value = compute()
        lock.lock()
        if gen == generation { cached = value }
        lock.unlock()
        return value
    }

    private static func compute() -> Bool {
        switch AppLanguage.current {
        case .zh: return true
        case .en: return false
        case .system: return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
        }
    }
}

/// Interface string in the current app language.
@inline(__always) func L(_ en: String, _ zh: String) -> String {
    Lang.isChinese ? zh : en
}

/// A bilingual string that can be stored (metric labels, notes). `text` follows the interface
/// language; `en` is what goes into exports.
struct LText: Codable, Hashable {
    var en: String
    var zh: String
    init(_ en: String, _ zh: String) { self.en = en; self.zh = zh }
    var text: String { L(en, zh) }
}
