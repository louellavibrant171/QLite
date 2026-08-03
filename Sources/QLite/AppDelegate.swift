import AppKit
import QLiteKit
import UniformTypeIdentifiers

/// Owns the open database windows and the app-wide menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [DatabaseWindowController] = []
    private var welcomeController: WelcomeWindowController?
    private var settingsController: SettingsWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.update(language: Preferences.shared.language)
        NSApp.mainMenu = MainMenu.build()
        if windowControllers.isEmpty {
            showWelcomeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && windowControllers.isEmpty { showWelcomeWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url: url) }
    }

    // MARK: - Opening databases

    /// Presents an open panel and opens the chosen database.
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("panel.openMessage")
        panel.prompt = L("panel.open")
        panel.allowedContentTypes = Preferences.shared.openPanelContentTypes
        // Sidecars and unknown extensions are still openable: QLite sniffs the file header.
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    /// Creates an empty database file and opens it.
    @objc func newDocument(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "database.sqlite"
        panel.message = L("panel.newMessage")
        panel.prompt = L("panel.create")
        panel.nameFieldLabel = L("panel.saveAsLabel")
        panel.allowedContentTypes = Preferences.shared.openPanelContentTypes
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            let database = try Database(url: url)
            database.close()
            open(url: url)
        } catch {
            presentError(error)
        }
    }

    func open(url: URL) {
        // Opening foo.db-wal (or -shm / -journal) means opening foo.db.
        let url = DatabaseFile.primaryURL(for: url)
        if let existing = windowControllers.first(where: { $0.model.url == url }) {
            existing.showWindow(nil)
            return
        }
        do {
            let model = try DatabaseModel(url: url)
            let controller = DatabaseWindowController(model: model)
            controller.onClose = { [weak self] closed in
                self?.windowControllers.removeAll { $0 === closed }
            }
            windowControllers.append(controller)
            controller.showWindow(nil)
            RecentDatabases.shared.remember(url: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            welcomeController?.close()
        } catch {
            presentError(error)
        }
    }

    @objc func showWelcomeWindow() {
        if welcomeController == nil {
            welcomeController = WelcomeWindowController()
        }
        welcomeController?.showWindow(nil)
    }

    @objc func openRecentDatabase(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url: url)
    }

    @objc func clearRecentDatabases(_ sender: Any?) {
        RecentDatabases.shared.clear()
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showHelp(_ sender: Any?) {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    static let repositoryURL = URL(string: "https://github.com/Clizo1209/QLite")!

    /// The standard About panel, with the repository as a clickable link in the credits area.
    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        credits.append(NSAttributedString(
            string: L("welcome.subtitle") + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: paragraph]))
        credits.append(NSAttributedString(
            string: Self.repositoryURL.absoluteString,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .link: Self.repositoryURL,
                         .paragraphStyle: paragraph]))

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = L("op.openDatabase")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
