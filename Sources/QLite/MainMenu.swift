import AppKit

/// Builds the application menu bar programmatically so the project stays nib-free.
///
/// The whole menu is rebuilt when the user switches language, so every title goes through
/// `L(_:)` rather than being set once at launch.
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(databaseMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        return mainMenu
    }

    private static func item(_ title: String,
                             _ action: Selector?,
                             _ key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command,
                             target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }

    private static func applicationMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "QLite")
        menu.addItem(item(L("menu.about"), #selector(AppDelegate.showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.settings"), #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenuItem(title: L("menu.services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: L("menu.services"))
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item(L("menu.hide"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(L("menu.hideOthers"), #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        menu.addItem(item(L("menu.showAll"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.quit"), #selector(NSApplication.terminate(_:)), "q"))

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("menu.file"))
        menu.addItem(item(L("menu.newDatabase"), #selector(AppDelegate.newDocument(_:)), "n"))
        menu.addItem(item(L("menu.open"), #selector(AppDelegate.openDocument(_:)), "o"))

        let recent = NSMenuItem(title: L("menu.openRecent"), action: nil, keyEquivalent: "")
        recent.submenu = RecentDatabasesMenu(title: L("menu.openRecent"))
        menu.addItem(recent)

        menu.addItem(.separator())
        menu.addItem(item(L("menu.closeWindow"), #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item(L("menu.exportResult"), #selector(DatabaseWindowController.exportResult(_:)), "e"))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.welcome"), #selector(AppDelegate.showWelcomeWindow)))

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("menu.edit"))
        menu.addItem(item(L("menu.undo"), Selector(("undo:")), "z"))
        menu.addItem(item(L("menu.redo"), Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.cut"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(L("menu.copy"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(L("menu.paste"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(L("menu.selectAll"), #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.find"), #selector(DatabaseWindowController.focusFilter(_:)), "f"))

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func databaseMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("menu.database"))
        menu.addItem(item(L("menu.newTable"), #selector(DatabaseWindowController.newTable(_:)), "t"))
        menu.addItem(item(L("menu.addColumn"), #selector(DatabaseWindowController.addColumn(_:))))
        menu.addItem(item(L("menu.createIndex"), #selector(DatabaseWindowController.createIndex(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.insertRow"), #selector(DatabaseWindowController.insertRow(_:)), "i"))
        menu.addItem(item(L("menu.deleteRows"), #selector(DatabaseWindowController.deleteSelectedRows(_:)), "\u{8}"))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.runQuery"), #selector(DatabaseWindowController.runQuery(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.refresh"), #selector(DatabaseWindowController.refresh(_:)), "\u{21A9}"))
        menu.addItem(item(L("menu.checkpointWAL"), #selector(DatabaseWindowController.checkpointWAL(_:))))
        menu.addItem(item(L("menu.vacuum"), #selector(DatabaseWindowController.vacuum(_:))))
        menu.addItem(item(L("menu.integrityCheck"), #selector(DatabaseWindowController.integrityCheck(_:))))

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("menu.view"))
        menu.addItem(item(L("tab.data"), #selector(DatabaseWindowController.showDataTab(_:)), "1"))
        menu.addItem(item(L("tab.structure"), #selector(DatabaseWindowController.showStructureTab(_:)), "2"))
        menu.addItem(item(L("tab.query"), #selector(DatabaseWindowController.showQueryTab(_:)), "3"))
        menu.addItem(item(L("tab.info"), #selector(DatabaseWindowController.showInfoTab(_:)), "4"))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.toggleSidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), "s", modifiers: [.command, .control]))

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("menu.window"))
        menu.addItem(item(L("menu.minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(L("menu.zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.bringAllToFront"), #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = menu

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: L("menu.help"))
        menu.addItem(item(L("menu.qliteHelp"), #selector(AppDelegate.showHelp(_:)), "?"))
        NSApp.helpMenu = menu

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }
}

/// Rebuilds itself from `RecentDatabases` each time it is opened.
final class RecentDatabasesMenu: NSMenu, NSMenuDelegate {
    override init(title: String) {
        super.init(title: title)
        delegate = self
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = RecentDatabases.shared.urls
        if urls.isEmpty {
            let empty = NSMenuItem(title: L("menu.noRecent"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(AppDelegate.openRecentDatabase(_:)),
                                  keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("menu.clearMenu"),
                                action: #selector(AppDelegate.clearRecentDatabases(_:)),
                                keyEquivalent: ""))
    }
}
