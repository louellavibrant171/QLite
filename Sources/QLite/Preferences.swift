import AppKit
import Combine
import QLiteKit
import UniformTypeIdentifiers

/// User settings, persisted in `UserDefaults` and observable by the SwiftUI views.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let language = "language"
        static let fileExtensions = "databaseFileExtensions"
        static let previewEnabled = "quickLookPreviewEnabled"
        static let thumbnailEnabled = "quickLookThumbnailEnabled"
        static let readSidecars = "readWALSidecars"
    }

    private let defaults = UserDefaults.standard

    private init() {
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        fileExtensions = defaults.stringArray(forKey: Key.fileExtensions) ?? DatabaseFile.defaultExtensions
        readSidecars = defaults.object(forKey: Key.readSidecars) as? Bool ?? true
        previewExtensionEnabled = defaults.object(forKey: Key.previewEnabled) as? Bool ?? true
        thumbnailExtensionEnabled = defaults.object(forKey: Key.thumbnailEnabled) as? Bool ?? true
    }

    // MARK: - Language

    /// Changing this updates the bundle used by `L(_:)` and rebuilds the menu bar, so the UI
    /// switches language without a relaunch. `AppleLanguages` is also written so that system
    /// controls (panels, alerts) follow on the next launch.
    @Published var language: AppLanguage = .system {
        didSet {
            guard oldValue != language else { return }
            defaults.set(language.rawValue, forKey: Key.language)
            L10n.update(language: language)
            switch language {
            case .system:
                defaults.removeObject(forKey: "AppleLanguages")
            case .english, .simplifiedChinese:
                defaults.set([language.localeIdentifier], forKey: "AppleLanguages")
            }
            NSApp.mainMenu = MainMenu.build()
        }
    }

    // MARK: - File types

    /// Extensions treated as databases in the Open panel and when deciding whether a dropped
    /// file should be opened.
    @Published var fileExtensions: [String] {
        didSet { defaults.set(fileExtensions, forKey: Key.fileExtensions) }
    }

    /// Read `-wal` / `-journal` sidecars so uncommitted data is visible.
    @Published var readSidecars: Bool {
        didSet { defaults.set(readSidecars, forKey: Key.readSidecars) }
    }

    func toggleExtension(_ ext: String, enabled: Bool) {
        let normalized = ext.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return }
        if enabled {
            if !fileExtensions.contains(normalized) { fileExtensions.append(normalized) }
        } else {
            fileExtensions.removeAll { $0 == normalized }
        }
    }

    /// Content types offered by the Open panel, derived from the enabled extensions.
    var openPanelContentTypes: [UTType] {
        var types: [UTType] = []
        for identifier in ["org.sqlite.v3", "public.database"] {
            if let type = UTType(identifier) { types.append(type) }
        }
        for ext in fileExtensions {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return Array(Set(types))
    }

    // MARK: - QuickLook

    @Published var previewExtensionEnabled: Bool {
        didSet {
            defaults.set(previewExtensionEnabled, forKey: Key.previewEnabled)
            QuickLookRegistration.setEnabled(previewExtensionEnabled, for: .preview)
        }
    }

    @Published var thumbnailExtensionEnabled: Bool {
        didSet {
            defaults.set(thumbnailExtensionEnabled, forKey: Key.thumbnailEnabled)
            QuickLookRegistration.setEnabled(thumbnailExtensionEnabled, for: .thumbnail)
        }
    }
}

/// The languages QLite ships translations for.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    /// The `.lproj` / locale identifier this language maps to.
    var localeIdentifier: String {
        switch self {
        case .system: return Locale.preferredLanguages.first ?? "en"
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }

    /// Shown in the language picker, always in the language itself.
    var displayName: String {
        switch self {
        case .system: return L("settings.language.system")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}
