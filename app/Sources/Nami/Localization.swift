import Foundation

/// Interface language, chosen in Settings (French by default).
enum AppLanguage: String, CaseIterable, Identifiable {
    case fr, en
    var id: String { rawValue }
    var label: String { self == .fr ? "Français" : "English" }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .fr
    }
}

/// Which AniList title variant to show.
enum TitleLanguage: String, CaseIterable, Identifiable {
    case romaji, english, native
    var id: String { rawValue }

    var label: String {
        switch self {
        case .romaji: "Romaji"
        case .english: t("Anglais", "English")
        case .native: t("Japonais", "Japanese")
        }
    }

    static var current: TitleLanguage {
        TitleLanguage(rawValue: UserDefaults.standard.string(forKey: "titleLanguage") ?? "") ?? .romaji
    }
}

/// Returns the string for the current interface language.
func t(_ fr: String, _ en: String) -> String {
    AppLanguage.current == .en ? en : fr
}
