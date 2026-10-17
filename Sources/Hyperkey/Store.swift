import AppKit
import ServiceManagement
import Carbon          // TIS, to list enabled keyboard layouts

struct Mods: OptionSet, Codable, Equatable {
    let rawValue: Int
    static let control = Mods(rawValue: 1 << 0)
    static let option  = Mods(rawValue: 1 << 1)
    static let command = Mods(rawValue: 1 << 2)
    static let shift   = Mods(rawValue: 1 << 3)
    static let hyper: Mods = [.control, .option, .command, .shift]

    init(rawValue: Int) { self.rawValue = rawValue }
    init(ns f: NSEvent.ModifierFlags) {
        self = []
        if f.contains(.control) { insert(.control) }
        if f.contains(.option)  { insert(.option) }
        if f.contains(.command) { insert(.command) }
        if f.contains(.shift)   { insert(.shift) }
    }
    init(cg f: CGEventFlags) {
        self = []
        if f.contains(.maskControl)   { insert(.control) }
        if f.contains(.maskAlternate) { insert(.option) }
        if f.contains(.maskCommand)   { insert(.command) }
        if f.contains(.maskShift)     { insert(.shift) }
    }
    var display: String {
        if self == .hyper { return "✦ " }
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.command) { s += "⌘" }
        if contains(.shift)   { s += "⇧" }
        return s
    }
}

enum Kind: String, Codable { case app, script }

struct AppBinding: Codable, Identifiable {
    var id = UUID()
    var keyCode: UInt16?     // nil = hotkey not set yet
    var mods = Mods()        // required modifiers
    var keyLabel = ""        // for display, e.g. "O"
    var path: String         // app/folder to open, or .sh to run
    var kind: Kind = .app

    init(path: String, kind: Kind = .app) { self.path = path; self.kind = kind }

    // Tolerant decode so adding fields doesn't wipe saved bindings.
    enum CodingKeys: String, CodingKey { case id, keyCode, mods, keyLabel, path, kind }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        id       = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        keyCode  = try? c.decode(UInt16.self, forKey: .keyCode)
        mods     = (try? c.decode(Mods.self, forKey: .mods)) ?? Mods()
        keyLabel = (try? c.decode(String.self, forKey: .keyLabel)) ?? ""
        path     = try c.decode(String.self, forKey: .path)
        kind     = (try? c.decode(Kind.self, forKey: .kind)) ?? .app
    }
}

// Tap a modifier alone -> switch input source. Keycodes: L/R ⌘ 55/54, ⌥ 58/61, ⌃ 59/62.
struct LayoutTap: Codable {
    var enabled = false
    var keys: [String: UInt16] = [                 // input-source id -> modifier keycode
        "com.apple.keylayout.US": 55,              // Left ⌘
        "com.apple.keylayout.RussianWin": 54,      // Right ⌘
    ]
}

// Portable snapshot written by File → Export Config. Paths are rewritten on import
// (scripts land in ~/.hyperkey/scripts; apps are resolved by bundle ID).
enum ConfigError: LocalizedError {
    case notAConfig
    var errorDescription: String? {
        switch self {
        case .notAConfig: return "This file isn't a Hyperkey config."
        }
    }
}

struct PortableConfig: Codable {
    var format = "hyperkey"
    var version = 1
    var hyperEnabled: Bool
    var hideMenuBarIcon: Bool
    var launchAtLogin: Bool
    var layoutTap: LayoutTap
    var bindings: [PortableBinding]
    var scripts: [String: String]                  // filename -> UTF-8 contents

    enum CodingKeys: String, CodingKey {
        case format, version, hyperEnabled, hideMenuBarIcon, launchAtLogin, layoutTap, bindings, scripts
    }
    init(version: Int = 1, hyperEnabled: Bool, hideMenuBarIcon: Bool, launchAtLogin: Bool,
         layoutTap: LayoutTap, bindings: [PortableBinding], scripts: [String: String]) {
        self.format = "hyperkey"; self.version = version; self.hyperEnabled = hyperEnabled
        self.hideMenuBarIcon = hideMenuBarIcon; self.launchAtLogin = launchAtLogin
        self.layoutTap = layoutTap; self.bindings = bindings; self.scripts = scripts
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        let format = (try? c.decode(String.self, forKey: .format)) ?? ""
        guard format == "hyperkey" else { throw ConfigError.notAConfig }
        self.format      = format
        version          = (try? c.decode(Int.self, forKey: .version)) ?? 1
        hyperEnabled     = (try? c.decode(Bool.self, forKey: .hyperEnabled)) ?? false
        hideMenuBarIcon  = (try? c.decode(Bool.self, forKey: .hideMenuBarIcon)) ?? false
        launchAtLogin    = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        layoutTap        = (try? c.decode(LayoutTap.self, forKey: .layoutTap)) ?? LayoutTap()
        bindings         = (try? c.decode([PortableBinding].self, forKey: .bindings)) ?? []
        scripts          = (try? c.decode([String: String].self, forKey: .scripts)) ?? [:]
    }
}

struct PortableBinding: Codable {
    var id: UUID
    var keyCode: UInt16?
    var mods: Mods
    var keyLabel: String
    var kind: Kind
    var path: String?                              // original app/folder path
    var bundleID: String?                          // apps: find it on the other Mac
    var scriptName: String?                        // scripts: filename in ~/.hyperkey/scripts

    init(id: UUID, keyCode: UInt16?, mods: Mods, keyLabel: String, kind: Kind,
         path: String?, bundleID: String?, scriptName: String?) {
        self.id = id; self.keyCode = keyCode; self.mods = mods; self.keyLabel = keyLabel
        self.kind = kind; self.path = path; self.bundleID = bundleID; self.scriptName = scriptName
    }

    enum CodingKeys: String, CodingKey {
        case id, keyCode, mods, keyLabel, kind, path, bundleID, scriptName
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        id         = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        keyCode    = try? c.decode(UInt16.self, forKey: .keyCode)
        mods       = (try? c.decode(Mods.self, forKey: .mods)) ?? Mods()
        keyLabel   = (try? c.decode(String.self, forKey: .keyLabel)) ?? ""
        kind       = (try? c.decode(Kind.self, forKey: .kind)) ?? .app
        path       = try? c.decode(String.self, forKey: .path)
        bundleID   = try? c.decode(String.self, forKey: .bundleID)
        scriptName = try? c.decode(String.self, forKey: .scriptName)
    }
}

struct ImportResult {
    var missingApps: [String]                      // display names we couldn't find
}

final class Store: ObservableObject {
    @Published var bindings: [AppBinding] { didSet { saveBindings() } }
    @Published var hyperEnabled: Bool { didSet {
        UserDefaults.standard.set(hyperEnabled, forKey: "hyperEnabled")
        onHyperChange?(hyperEnabled)
    }}
    @Published var launchAtLogin: Bool { didSet { setLogin(launchAtLogin) } }
    @Published var hideMenuBarIcon: Bool { didSet {
        UserDefaults.standard.set(hideMenuBarIcon, forKey: "hideMenuBarIcon")
        onHideMenuChange?(hideMenuBarIcon)
    }}
    @Published var layoutTap: LayoutTap { didSet {
        UserDefaults.standard.set(try? JSONEncoder().encode(layoutTap), forKey: "layoutTap")
        onLayoutChange?()
    }}

    var onHyperChange: ((Bool) -> Void)?
    var onHideMenuChange: ((Bool) -> Void)?
    var onLayoutChange: (() -> Void)?
    var isRecording = false   // true while a hotkey is being captured: pause launches

    static let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hyperkey/scripts")

    init() {
        let d = UserDefaults.standard
        hyperEnabled = d.bool(forKey: "hyperEnabled")
        hideMenuBarIcon = d.bool(forKey: "hideMenuBarIcon")
        bindings = (try? JSONDecoder().decode([AppBinding].self,
            from: d.data(forKey: "bindings") ?? Data())) ?? []
        layoutTap = (try? JSONDecoder().decode(LayoutTap.self,
            from: d.data(forKey: "layoutTap") ?? Data())) ?? LayoutTap()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        syncScripts()
    }

    // matched binding for a key+mods press
    func action(for keyCode: UInt16, mods: Mods) -> (path: String, isScript: Bool)? {
        guard let b = bindings.first(where: { $0.keyCode == keyCode && $0.mods == mods }) else { return nil }
        return (b.path, b.kind == .script)
    }

    // Input-source id for a tapped modifier keycode, or nil if the feature/key isn't configured.
    // ponytail: first match wins if two layouts share a key — picker lets you, don't.
    func layoutID(forKeyCode code: UInt16) -> String? {
        guard layoutTap.enabled else { return nil }
        return layoutTap.keys.first(where: { $0.value == code })?.key
    }

    // Enabled keyboard layouts (id + localized name) to populate the layout pickers.
    static func enabledLayouts() -> [(id: String, name: String)] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        return list.compactMap { src in
            func prop(_ key: CFString) -> String? {
                guard let p = TISGetInputSourceProperty(src, key) else { return nil }
                return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            }
            guard prop(kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String),
                  let id = prop(kTISPropertyInputSourceID),
                  let name = prop(kTISPropertyLocalizedName) else { return nil }
            return (id, name)
        }
    }

    // Make sure every .sh in the scripts folder has a row (keeps existing hotkeys).
    func syncScripts() {
        try? FileManager.default.createDirectory(at: Self.scriptsDir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.scriptsDir,
            includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "sh" {
            if !bindings.contains(where: { $0.path == url.path }) {
                bindings.append(AppBinding(path: url.path, kind: .script))
            }
        }
    }

    func exportConfig() throws -> Data {
        var scripts: [String: String] = [:]
        let items: [PortableBinding] = bindings.map { b in
            var item = PortableBinding(id: b.id, keyCode: b.keyCode, mods: b.mods,
                                       keyLabel: b.keyLabel, kind: b.kind,
                                       path: b.path, bundleID: nil, scriptName: nil)
            if b.kind == .script {
                let name = URL(fileURLWithPath: b.path).lastPathComponent
                item.scriptName = name
                item.path = nil
                if let text = (try? String(contentsOfFile: b.path, encoding: .utf8))
                    ?? (try? String(contentsOfFile: b.path, encoding: .isoLatin1)) {
                    scripts[name] = text
                }
            } else {
                item.bundleID = Bundle(url: URL(fileURLWithPath: b.path))?.bundleIdentifier
            }
            return item
        }
        let cfg = PortableConfig(hyperEnabled: hyperEnabled, hideMenuBarIcon: hideMenuBarIcon,
                                 launchAtLogin: launchAtLogin, layoutTap: layoutTap,
                                 bindings: items, scripts: scripts)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(cfg)
    }

    // Replace current hotkeys / scripts / layout settings with the file. Apps are
    // re-resolved by bundle ID so they work even if they live in a different folder.
    @discardableResult
    func importConfig(_ data: Data) throws -> ImportResult {
        let cfg: PortableConfig
        do { cfg = try JSONDecoder().decode(PortableConfig.self, from: data) }
        catch let e as ConfigError { throw e }
        catch { throw ConfigError.notAConfig }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.scriptsDir, withIntermediateDirectories: true)

        func scriptFile(_ name: String) -> String {
            URL(fileURLWithPath: name).lastPathComponent
        }
        let keep = Set(cfg.scripts.keys.map(scriptFile).filter { !$0.isEmpty && $0 != "." && $0 != ".." })
        let existing = (try? fm.contentsOfDirectory(at: Self.scriptsDir,
            includingPropertiesForKeys: nil)) ?? []
        for url in existing where url.pathExtension == "sh" && !keep.contains(url.lastPathComponent) {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
        for (name, text) in cfg.scripts {
            let safe = scriptFile(name)
            guard keep.contains(safe) else { continue }
            let url = Self.scriptsDir.appendingPathComponent(safe)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        var missing: [String] = []
        var next: [AppBinding] = []
        for item in cfg.bindings {
            var b = AppBinding(path: "", kind: item.kind)
            b.id = item.id; b.keyCode = item.keyCode; b.mods = item.mods; b.keyLabel = item.keyLabel
            if item.kind == .script {
                let name = scriptFile(item.scriptName
                    ?? URL(fileURLWithPath: item.path ?? "script.sh").lastPathComponent)
                guard !name.isEmpty else { continue }
                b.path = Self.scriptsDir.appendingPathComponent(name).path
            } else {
                let resolved = resolveApp(bundleID: item.bundleID, path: item.path)
                b.path = resolved.path
                if !resolved.found { missing.append(appDisplayName(path: item.path, bundleID: item.bundleID)) }
            }
            next.append(b)
        }

        enableInputSources(Set(cfg.layoutTap.keys.keys))
        bindings = next
        layoutTap = cfg.layoutTap
        hyperEnabled = cfg.hyperEnabled
        hideMenuBarIcon = cfg.hideMenuBarIcon
        launchAtLogin = cfg.launchAtLogin
        return ImportResult(missingApps: missing)
    }

    private func saveBindings() {
        UserDefaults.standard.set(try? JSONEncoder().encode(bindings), forKey: "bindings")
    }

    private func setLogin(_ on: Bool) {
        // ponytail: unsigned dev builds may throw; fine for local use
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    // Find the app on this Mac: bundle ID first, then the original path, then /Applications.
    private func resolveApp(bundleID: String?, path: String?) -> (path: String, found: Bool) {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return (url.path, true)
        }
        if let path, FileManager.default.fileExists(atPath: path) { return (path, true) }
        if let path {
            let name = URL(fileURLWithPath: path).lastPathComponent
            for dir in ["/Applications", "/System/Applications",
                        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate) { return (candidate, true) }
            }
            return (path, false)
        }
        return ("", false)
    }

    private func appDisplayName(path: String?, bundleID: String?) -> String {
        if let path {
            let n = FileManager.default.displayName(atPath: path)
            return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
        }
        return bundleID ?? "Unknown app"
    }

    // Turn on any imported layouts that are installed but not currently enabled.
    private func enableInputSources(_ ids: Set<String>) {
        guard !ids.isEmpty,
              let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue()
                as? [TISInputSource] else { return }
        for src in list {
            guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            if ids.contains(id) { TISEnableInputSource(src) }
        }
    }
}
