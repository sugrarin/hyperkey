import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store()
    let hyper = HyperManager()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private static let configType =
        UTType("ee.timur.hyperkey.config") ?? UTType(filenameExtension: "hyperkey") ?? .json

    func applicationDidFinishLaunching(_ note: Notification) {
        hyper.lookup = { [store] in store.action(for: $0, mods: $1) }
        hyper.isRecording = { [store] in store.isRecording }
        hyper.layoutFor = { [store] in store.layoutID(forKeyCode: $0) }

        let apply: () -> Void = { [hyper, store] in
            hyper.apply(hyperOn: store.hyperEnabled, layoutOn: store.layoutTap.enabled)
        }
        store.onHyperChange = { _ in apply() }
        store.onLayoutChange = apply

        hyper.start()   // ContentView shows an in-window banner if access isn't granted
        apply()
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "menu-icon", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 14.4, height: 14.4) // 10% smaller than the stock 16pt
            img.isTemplate = true // recolored for light/dark menu bar
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "✦"
        }
        let menu = NSMenu()
        menu.addItem(item("Settings…", #selector(showWindow), ","))
        menu.addItem(.separator())
        menu.addItem(item("Export Config…", #selector(exportConfig)))
        menu.addItem(item("Import Config…", #selector(importConfig)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hyperkey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        store.onHideMenuChange = { [statusItem] in statusItem?.isVisible = !$0 }
        statusItem.isVisible = !store.hideMenuBarIcon

        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Hyperkey"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        window.contentMinSize = NSSize(width: 423, height: 516)
        window.contentMaxSize = NSSize(width: 423, height: 100_000) // height only
        window.setContentSize(NSSize(width: 423, height: 516))
        window.center()
        showWindow()
    }

    // Relaunch from Launchpad/Finder while already running -> reopen Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc private func showWindow() {
        NSApp.setActivationPolicy(.regular) // real window: shows in Dock & ⌘-Tab while open
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // File / ✦ menu: dump hotkeys, scripts, and layout settings into a .hyperkey file.
    @objc private func exportConfig() {
        front {
            let p = NSSavePanel()
            p.title = "Export Config"
            p.nameFieldStringValue = "Hyperkey.hyperkey"
            p.allowedContentTypes = [Self.configType, .json]
            p.canCreateDirectories = true
            p.isExtensionHidden = false
            guard p.runModal() == .OK, let url = p.url else { return }
            do {
                try store.exportConfig().write(to: url, options: .atomic)
            } catch {
                alert("Couldn't Export Config", error.localizedDescription)
            }
        }
    }

    // File / ✦ menu: replace current config with the file (other Mac → this Mac).
    @objc private func importConfig() {
        front {
            let p = NSOpenPanel()
            p.title = "Import Config"
            p.allowedContentTypes = [Self.configType, .json]
            p.canChooseFiles = true
            p.allowsMultipleSelection = false
            guard p.runModal() == .OK, let url = p.url else { return }

            let confirm = NSAlert()
            confirm.messageText = "Replace current config?"
            confirm.informativeText = "Hotkeys, scripts, and layout settings will be replaced with the imported file."
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Import")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }

            do {
                let result = try store.importConfig(Data(contentsOf: url))
                showWindow()
                let done = NSAlert()
                done.messageText = "Config Imported"
                var info = "Hotkeys, scripts, and layout settings were applied."
                if !result.missingApps.isEmpty {
                    info += "\n\nNot found on this Mac:\n"
                        + result.missingApps.map { "• \($0)" }.joined(separator: "\n")
                        + "\n\nInstall them, then import again — or pick the app in Settings."
                }
                done.informativeText = info
                done.runModal()
            } catch {
                alert("Couldn't Import Config", error.localizedDescription)
            }
        }
    }

    // App menu + File menu (visible while Settings is open, when we're a regular app).
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Hyperkey",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showWindow), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Hyperkey", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hyperkey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let exp = item("Export Config…", #selector(exportConfig), "e")
        exp.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exp)
        let imp = item("Import Config…", #selector(importConfig), "i")
        imp.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(imp)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    // Save/open panels from a menu-bar extra need to be a real app, or they hide behind others.
    private func front(_ work: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        work()
        if !window.isVisible { NSApp.setActivationPolicy(.accessory) }
    }

    private func alert(_ title: String, _ info: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.alertStyle = .warning
        a.runModal()
    }

    func windowWillClose(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory) // back to background-only when closed
    }

    func windowDidBecomeKey(_ note: Notification) {
        store.syncScripts() // pick up scripts added in Finder while we were away
    }

    func applicationWillTerminate(_ note: Notification) {
        hyper.apply(hyperOn: false, layoutOn: false) // restore normal CapsLock on quit
    }
}
