import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: one key plus modifiers.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt
    /// What to print for the key itself, e.g. "Space" or "1".
    var keyLabel: String

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection([.command, .shift, .option, .control]).rawValue
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        let code = UInt32(event.keyCode)
        let label = Self.specialKeyNames[Int(code)]
            ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
        self.init(keyCode: code, modifiers: event.modifierFlags, keyLabel: label)
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// Since macOS 15, shortcuts made of only Option / Option+Shift plus a key
    /// can't be registered at all. Requiring Command or Control also keeps the
    /// shortcut from swallowing ordinary typing.
    var hasRequiredModifier: Bool {
        modifiers.contains(.command) || modifiers.contains(.control)
    }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyLabel
    }

    static let defaultCapture = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift], keyLabel: "Space")
    static let defaultToggle = KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: [.command, .shift], keyLabel: "1")

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "Fwd Delete", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// System-wide shortcuts through Carbon's RegisterEventHotKey. It is old but
/// still the right tool: it needs no Accessibility or Input Monitoring
/// permission, and the key press is consumed so it never reaches the app you
/// are typing in.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false
    private let signature: OSType = 0x474C_4E43 // "GLNC"

    /// Returns false if the shortcut could not be registered (usually because
    /// another app already owns it).
    @discardableResult
    func register(id: UInt32, combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    func unregisterAll() {
        for id in Array(refs.keys) {
            unregister(id: id)
        }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // A C callback cannot capture anything, so it reaches the shared instance.
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                HotKeyCenter.shared.fire(hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
