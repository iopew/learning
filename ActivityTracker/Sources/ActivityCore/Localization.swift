import Foundation

/// The language setting as the user picks it.
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ru, en

    public var id: String { rawValue }
}

/// Two-language strings kept side by side in the code: `L.tr("Сегодня", "Today")`.
/// Simple on purpose: one place to read both texts, no string files to keep in sync, switchable at runtime.
public enum L {
    public enum Lang: Equatable {
        case ru, en
    }

    /// Set by the app from the user's setting. The core and the tests default to Russian.
    public static var current: Lang = .ru

    public static func tr(_ ru: String, _ en: String) -> String {
        current == .en ? en : ru
    }

    /// "Как в системе" → Russian if the Mac's preferred language is Russian, English otherwise.
    public static func resolve(_ setting: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> Lang {
        switch setting {
        case .ru: return .ru
        case .en: return .en
        case .system: return (preferred.first ?? "").hasPrefix("ru") ? .ru : .en
        }
    }

    public static var locale: Locale {
        Locale(identifier: current == .en ? "en_US" : "ru_RU")
    }
}
