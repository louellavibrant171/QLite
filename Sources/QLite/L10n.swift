import Foundation

/// Localized string lookup.
///
/// This is a thin wrapper over `Bundle.localizedString` that can point at a specific
/// `.lproj` bundle, so switching language in Settings takes effect immediately instead of
/// on the next launch. Keys live in `Resources/Localization/<lang>.lproj/Localizable.strings`.
enum L10n {
    private(set) static var bundle: Bundle = .main

    static func update(language: AppLanguage) {
        switch language {
        case .system:
            bundle = .main
        case .english, .simplifiedChinese:
            bundle = Bundle.main.path(forResource: language.localeIdentifier, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? .main
        }
    }

    static func string(_ key: String) -> String {
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        // Fall back to the main bundle so a key missing from one translation still resolves.
        if value == key, bundle != .main {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return value
    }
}

/// Shorthand for a localized string: `L("menu.file")`.
func L(_ key: String) -> String {
    L10n.string(key)
}

/// Shorthand for a localized format string: `L("data.rows_of", 1, 50, 900)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L10n.string(key), arguments: arguments)
}
