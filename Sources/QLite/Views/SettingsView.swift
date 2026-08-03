import SwiftUI
import AppKit
import QLiteKit

/// The Settings window: language, file types and QuickLook registration.
struct SettingsView: View {
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        TabView {
            GeneralSettings(preferences: preferences)
                .tabItem { Label(L("settings.general"), systemImage: "gearshape") }
            FileTypeSettings(preferences: preferences)
                .tabItem { Label(L("settings.fileTypes"), systemImage: "doc.badge.gearshape") }
            QuickLookSettings(preferences: preferences)
                .tabItem { Label(L("settings.quickLook"), systemImage: "eye") }
        }
        .frame(width: 520, height: 420)
        .id(preferences.language)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Picker(L("settings.language"), selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Text(L("settings.language.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("settings.sidecars"), isOn: $preferences.readSidecars)
                Text(L("settings.sidecars.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FileTypeSettings: View {
    @ObservedObject var preferences: Preferences
    @State private var newExtension = ""
    @State private var message: String?

    /// Every extension we know about: the built-in list plus anything the user added.
    private var allExtensions: [String] {
        var seen = Set<String>()
        return (DatabaseFile.defaultExtensions + preferences.fileExtensions).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.extensions.title")).font(.headline)
            Text(L("settings.extensions.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(allExtensions, id: \.self) { ext in
                    Toggle(isOn: Binding(
                        get: { preferences.fileExtensions.contains(ext) },
                        set: { preferences.toggleExtension(ext, enabled: $0) })
                    ) {
                        HStack(spacing: 6) {
                            Text(".\(ext)").font(.system(.body, design: .monospaced))
                            if !DatabaseFileExtensions.declared.contains(ext) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                    .help(L("settings.extensions.declaredOnly",
                                            DatabaseFileExtensions.declared.map { ".\($0)" }.joined(separator: ", ")))
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField(L("settings.extensions.addPlaceholder"), text: $newExtension)
                    .onSubmit(addExtension)
                Button(L("settings.extensions.add"), action: addExtension)
                    .disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button(L("settings.extensions.setDefault")) {
                    let result = QuickLookRegistration.bindDefaultApplication(for: preferences.fileExtensions)
                    message = L("settings.extensions.bound", result.bound)
                }
                Spacer()
                Button(L("settings.extensions.reset")) {
                    preferences.fileExtensions = DatabaseFile.defaultExtensions
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func addExtension() {
        let value = newExtension.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        guard !value.isEmpty else { return }
        preferences.toggleExtension(value, enabled: true)
        newExtension = ""
    }
}

private struct QuickLookSettings: View {
    @ObservedObject var preferences: Preferences
    @State private var message: String?

    var body: some View {
        Form {
            Toggle(L("settings.quickLook.preview"), isOn: $preferences.previewExtensionEnabled)
            Toggle(L("settings.quickLook.thumbnail"), isOn: $preferences.thumbnailExtensionEnabled)

            Text(L("settings.quickLook.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(L("settings.quickLook.reregister")) {
                if let failure = QuickLookRegistration.refresh() {
                    message = L("settings.quickLook.failed", failure)
                } else {
                    message = L("settings.quickLook.done")
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Window controller for the Settings window.
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.title")
        window.contentView = NSHostingView(rootView: SettingsView())
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
