import AppKit
import Carbon.HIToolbox
import Carbon          // TISInputSource / TISSelectInputSource

// CapsLock is remapped (via hidutil) to F18; the tap treats F18 as the hyper modifier.
private let f18KeyCode: Int64 = Int64(kVK_F18) // 79

// Running app -> hide if it's frontmost, else bring to front. Otherwise launch / open folder.
// Uses NSWorkspace to activate: a background app may not call NSRunningApplication.activate()
// while it isn't itself frontmost, but openApplication works regardless.
private func activateOrToggle(_ path: String) {
    let url = URL(fileURLWithPath: path)
    guard url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier else {
        NSWorkspace.shared.open(url)            // folder / file
        return
    }
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first, app.isActive {
        app.hide()
    } else {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }
}

// Switch the active keyboard layout, the native equivalent of Karabiner's select_input_source.
private func selectInputSource(_ id: String) {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
            as? [TISInputSource] else { return }
    for src in list {
        guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
        if Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String == id {
            TISSelectInputSource(src); return
        }
    }
}

private func runScript(_ path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [path]
    try? p.run()
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType,
                         event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HyperManager>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

final class HyperManager {
    var lookup: ((UInt16, Mods) -> (path: String, isScript: Bool)?)?
    var isRecording: () -> Bool = { false }
    var layoutFor: ((UInt16) -> String?)?   // configured tap-key -> input-source id, or nil

    private var tap: CFMachPort?
    private var hyperOn = false
    private var pendingTap: Int64?           // a configured modifier is down and "alone" so far
    private var pendingSince = Date()
    private let hyperFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    // Queried live from HID state, not tracked: a missed F18 keyUp (e.g. focus jumps to a
    // secure-input password field mid-press, swallowing the up event) can't leave it stuck on.
    private var hyperHeld: Bool { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_F18)) }

    /// Create the event tap (needs Accessibility permission). Returns false if not trusted.
    @discardableResult
    func start() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return false }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)   // modifier presses, for tap-if-alone
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false) // off until hyper enabled
        return true
    }

    // The tap runs if either feature is on; CapsLock is only remapped for the hyper feature.
    func apply(hyperOn: Bool, layoutOn: Bool) {
        self.hyperOn = hyperOn
        let run = hyperOn || layoutOn
        if run && tap == nil { _ = start() } // retry after Accessibility was granted
        remapCapsLock(hyperOn)
        if let tap { CGEvent.tapEnable(tap: tap, enable: run) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged {                 // tap a modifier alone -> switch layout
            if let id = layoutFor?(UInt16(code)) {
                let down = event.flags.contains(maskFor(code))
                if down { pendingTap = code; pendingSince = Date() }
                else if pendingTap == code, Date().timeIntervalSince(pendingSince) < 0.5 {
                    selectInputSource(id)          // released alone & quick -> fire
                }
                if !down { pendingTap = nil }
            } else {
                pendingTap = nil                   // another modifier -> no longer "alone"
            }
            return Unmanaged.passUnretained(event) // modifiers always pass through unchanged
        }

        if code == f18KeyCode {                    // the hyper key itself
            return nil                             // swallow F18; "held" is queried live
        }

        if type == .keyDown {
            pendingTap = nil                       // any key press cancels "alone"
            if hyperOn, !isRecording() {
                var mods = Mods(cg: event.flags)
                if hyperHeld { mods.formUnion(.hyper) }
                if let hit = lookup?(UInt16(code), mods) {
                    DispatchQueue.main.async {
                        hit.isScript ? runScript(hit.path) : activateOrToggle(hit.path)
                    }
                    return nil                     // launcher hit: swallow
                }
            }
        }
        guard hyperHeld else { return Unmanaged.passUnretained(event) }
        event.flags.insert(hyperFlags)             // otherwise pass through as ⌃⌥⌘⇧+key
        return Unmanaged.passUnretained(event)
    }

    // Device-independent flag for a left/right modifier keycode (down-vs-up = is the flag still set).
    // ponytail: left/right share one flag — breaks only if you hold both ⌘ at once, not a real tap
    private func maskFor(_ code: Int64) -> CGEventFlags {
        switch code {
        case 54, 55: return .maskCommand
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        default:     return []
        }
    }

    // 0x700000039 = CapsLock, 0x70000006D = F18
    private func remapCapsLock(_ on: Bool) {
        let map = on
            ? #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
            : #"{"UserKeyMapping":[]}"#
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", map]
        try? p.run()
    }
}
