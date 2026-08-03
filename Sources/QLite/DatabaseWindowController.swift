import AppKit
import SwiftUI
import QLiteKit
import UniformTypeIdentifiers

/// Hosts one database window and translates menu commands into model actions.
final class DatabaseWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: DatabaseModel
    var onClose: ((DatabaseWindowController) -> Void)?

    init(model: DatabaseModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = model.databaseName
        window.representedURL = model.url
        window.titlebarSeparatorStyle = .automatic
        window.setFrameAutosaveName("QLiteWindow")
        window.minSize = NSSize(width: 720, height: 420)
        window.contentView = NSHostingView(rootView: DatabaseView(model: model))
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    // MARK: - Menu actions

    @objc func refresh(_ sender: Any?) {
        model.reloadSchema()
    }

    @objc func newTable(_ sender: Any?) {
        model.activeSheet = .newTable
    }

    @objc func addColumn(_ sender: Any?) {
        guard let table = model.details?.object, table.kind == .table else { return }
        model.activeSheet = .addColumn(table.name)
    }

    @objc func createIndex(_ sender: Any?) {
        guard let table = model.details?.object, table.kind == .table else { return }
        model.activeSheet = .createIndex(table.name)
    }

    @objc func insertRow(_ sender: Any?) {
        guard model.canEditRows else { return }
        model.tab = .data
        model.activeSheet = .editRow(nil)
    }

    @objc func deleteSelectedRows(_ sender: Any?) {
        model.deleteSelectedRows()
    }

    @objc func runQuery(_ sender: Any?) {
        model.runQuery()
    }

    @objc func checkpointWAL(_ sender: Any?) {
        model.checkpointWAL()
    }

    @objc func vacuum(_ sender: Any?) {
        model.vacuum()
    }

    @objc func integrityCheck(_ sender: Any?) {
        model.integrityCheck()
    }

    @objc func focusFilter(_ sender: Any?) {
        model.tab = .data
        model.filterFieldFocused = true
    }

    @objc func showDataTab(_ sender: Any?) { model.tab = .data }
    @objc func showStructureTab(_ sender: Any?) { model.tab = .structure }
    @objc func showQueryTab(_ sender: Any?) { model.tab = .query }
    @objc func showInfoTab(_ sender: Any?) { model.tab = .info }

    @objc func exportResult(_ sender: Any?) {
        guard let (result, name) = model.exportableResult else {
            NSSound.beep()
            return
        }
        model.activeSheet = .export(result, name)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(insertRow(_:)), #selector(deleteSelectedRows(_:)):
            return model.canEditRows
        case #selector(addColumn(_:)), #selector(createIndex(_:)):
            return model.details?.object.kind == .table
        case #selector(exportResult(_:)):
            return model.exportableResult != nil
        default:
            return true
        }
    }
}

/// A small window shown at launch listing recent databases.
final class WelcomeWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = L("menu.welcome")
        window.contentView = NSHostingView(rootView: WelcomeView())
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
