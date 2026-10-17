import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ApplicationServices   // AXIsProcessTrusted

struct ContentView: View {
    @ObservedObject var store: Store
    @State private var tab = 0
    @State private var selection: AppBinding.ID?
    @State private var clash: AppBinding.ID?   // row to flash red on duplicate
    @State private var trusted = AXIsProcessTrusted()
    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !trusted { permissionBanner }

            Toggle("Make CapsLock Hyperkey (⌃⌥⌘⇧)", isOn: $store.hyperEnabled)

            Picker("", selection: $tab) {
                Text("Apps").tag(0)
                Text("Scripts").tag(1)
                Text("Lang Switcher").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .flexibleControl() // macOS 26: segmented pickers hug content unless flexible

            if tab == 2 {
                langSwitcher
            } else {
                list(kind: tab == 0 ? .app : .script)
            }

            Divider()
            Toggle("Launch at Login", isOn: $store.launchAtLogin)
            Toggle("Hide Menu Bar Icon", isOn: $store.hideMenuBarIcon)
            supportLink
        }
        .padding(20)
        .frame(minWidth: 423, maxWidth: 423, minHeight: 516, maxHeight: .infinity)
        .onReceive(trustTimer) { _ in trusted = AXIsProcessTrusted() }
    }

    private var supportLink: some View {
        HStack(spacing: 4) {
            Text("Support me:").foregroundStyle(.secondary)
            Link("ko-fi.com/sugrarin", destination: URL(string: "https://ko-fi.com/sugrarin")!)
        }
        .font(.caption)
    }

    // Shown until Accessibility access is granted; the button opens the right Settings pane.
    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Access Needed").fontWeight(.semibold)
                Text("Hyperkey needs it to capture keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant Access") {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
    }

    private static let modKeys: [(UInt16, String)] =
        [(55, "Left ⌘"), (54, "Right ⌘"), (58, "Left ⌥"), (61, "Right ⌥"), (59, "Left ⌃"), (62, "Right ⌃")]
    private var layouts: [(id: String, name: String)] { Store.enabledLayouts() }

    // Lang Switcher tab: fills the same flexible area the app/script list does.
    private var langSwitcher: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Lang Switcher", isOn: $store.layoutTap.enabled)
            Text("Tap a left or right modifier on its own to switch keyboard layout.")
                .font(.caption).foregroundStyle(.secondary)
            if store.layoutTap.enabled {
                ForEach(layouts, id: \.id) { l in
                    HStack(spacing: 6) {
                        Text("Use")
                        Picker("", selection: key(for: l.id)) {
                            Text("—").tag(UInt16?.none)
                            ForEach(Self.modKeys, id: \.0) { Text($0.1).tag(UInt16?.some($0.0)) }
                        }.labelsHidden().fixedSize()
                        Text("for \(l.name)")
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // The modifier key assigned to a layout (nil = unassigned), as a Picker binding.
    private func key(for id: String) -> Binding<UInt16?> {
        Binding(
            get: { store.layoutTap.keys[id] },
            set: { v in
                if let v { store.layoutTap.keys[id] = v }
                else { store.layoutTap.keys.removeValue(forKey: id) }
            })
    }

    private func list(kind: Kind) -> some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($store.bindings) { $b in
                    if b.kind == kind {
                        HStack(spacing: 0) {
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: b.path))
                                    .resizable().frame(width: 22, height: 22)
                                Text(displayName(b.path))
                                Spacer(minLength: 0)
                            }
                            .background {
                                if kind == .script {
                                    RowClicks(
                                        onSingle: { selection = b.id },
                                        onDouble: { editScript(b.path) },
                                        onOpen:   { open(b.path) },
                                        onReveal: { revealInFinder(b.path) })
                                }
                            }
                            HotkeyField(item: $b, store: store, onClash: flash)
                        }
                        .tag(b.id)
                        .listRowBackground(b.id == clash ? Color.red.opacity(0.25) : Color.clear)
                    }
                }
            }
            .border(Color(nsColor: .separatorColor))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { handleDrop(url, kind: kind) }
                    }
                }
                return true
            }

            HStack(spacing: 8) {
                Button { kind == .app ? addApp() : addScript() } label: {
                    Image(systemName: "plus").frame(width: 14, height: 14)
                }
                .frame(width: 40)
                .flexibleControl()
                Button { removeSelected() } label: {
                    Image(systemName: "minus").frame(width: 14, height: 14)
                }
                .frame(width: 40)
                .flexibleControl()
                .disabled(selection == nil)
                Spacer()
                if kind == .script {
                    Button("Open Folder") { NSWorkspace.shared.open(Store.scriptsDir) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.vertical, 8)
        }
    }

    private func handleDrop(_ url: URL, kind: Kind) {
        if kind == .app {
            store.bindings.append(AppBinding(path: url.path))
        } else if url.pathExtension == "sh" {
            let dst = Store.scriptsDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.createDirectory(at: Store.scriptsDir, withIntermediateDirectories: true)
            if url != dst { try? FileManager.default.copyItem(at: url, to: dst) }
            store.syncScripts()
        }
    }

    private func addApp() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        if p.runModal() == .OK, let url = p.url {
            store.bindings.append(AppBinding(path: url.path))
        }
    }

    private func addScript() {
        try? FileManager.default.createDirectory(at: Store.scriptsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Store.scriptsDir) // drop a .sh here; it's picked up on focus
    }

    private func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func editScript(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", path] // open in default text editor, never execute
        try? p.run()
    }

    private func removeSelected() {
        if let b = store.bindings.first(where: { $0.id == selection }), b.kind == .script {
            // Move to Trash (recoverable), never hard-delete the user's script.
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: b.path), resultingItemURL: nil)
        }
        store.bindings.removeAll { $0.id == selection }
        selection = nil
    }

    private func displayName(_ path: String) -> String {
        let n = FileManager.default.displayName(atPath: path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    private func flash(_ id: AppBinding.ID) {
        clash = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if clash == id { clash = nil } }
    }
}

// Click to record a hotkey. While recording, launches are paused and a combo
// already used by another row is rejected with a beep + flash.
struct HotkeyField: View {
    @Binding var item: AppBinding
    let store: Store
    let onClash: (AppBinding.ID) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(title) { toggle() }   // hugs its content, sits flush right after the Spacer
    }

    private var title: String {
        if recording { return "Press Keys…" }
        return item.keyLabel.isEmpty ? "Set Hotkey" : item.mods.display + item.keyLabel
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        store.isRecording = true
        let b = $item
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }   // Esc = cancel
            let kc = e.keyCode, m = Mods(ns: e.modifierFlags)
            if m.isEmpty { NSSound.beep(); return nil }  // require a modifier, no bare keys
            if let dup = store.bindings.first(where: { $0.id != item.id && $0.keyCode == kc && $0.mods == m }) {
                NSSound.beep()
                onClash(dup.id)
            } else {
                b.wrappedValue.keyCode = kc
                b.wrappedValue.mods = m
                b.wrappedValue.keyLabel = label(for: kc)
            }
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        store.isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    // English label regardless of active layout (matching is by keyCode anyway).
    private func label(for keyCode: UInt16) -> String {
        usKeyLabels[keyCode] ?? "key\(keyCode)"
    }
}

// AppKit click handler: single-click selects immediately, double-click acts —
// no SwiftUI tap-disambiguation delay (Finder-like). Right-click shows the menu.
struct RowClicks: NSViewRepresentable {
    var onSingle: () -> Void
    var onDouble: () -> Void
    var onOpen: () -> Void
    var onReveal: () -> Void

    func makeNSView(context: Context) -> NSView { ClickView().applying(self) }
    func updateNSView(_ v: NSView, context: Context) { _ = (v as? ClickView)?.applying(self) }

    final class ClickView: NSView {
        private var onSingle: () -> Void = {}
        private var onDouble: () -> Void = {}
        private var onOpen: () -> Void = {}
        private var onReveal: () -> Void = {}

        @discardableResult func applying(_ r: RowClicks) -> ClickView {
            onSingle = r.onSingle; onDouble = r.onDouble; onOpen = r.onOpen; onReveal = r.onReveal
            return self
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with e: NSEvent) { e.clickCount >= 2 ? onDouble() : onSingle() }
        override func menu(for event: NSEvent) -> NSMenu? {
            onSingle()
            let m = NSMenu()
            for (title, sel) in [("Open", #selector(openItem)), ("Show in Finder", #selector(revealItem))] {
                let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self
                m.addItem(i)
            }
            return m
        }
        @objc private func openItem() { onOpen() }
        @objc private func revealItem() { onReveal() }
    }
}

// macOS 26: button-like controls (Picker, Button) fit-to-content unless told to fill.
private extension View {
    @ViewBuilder func flexibleControl() -> some View {
        if #available(macOS 26, *) { buttonSizing(.flexible) } else { self }
    }
}

// US-QWERTY virtual keycode -> label.
private let usKeyLabels: [UInt16: String] = [
    0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",
    14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",
    26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",
    39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`",
    49:"Space",36:"↩",48:"⇥",53:"⎋",51:"⌫",117:"⌦",
    123:"←",124:"→",125:"↓",126:"↑",
    122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",
]
