import AppKit

/// A key + modifier combination for a global hotkey. Stores the virtual key
/// code (same space as `NSEvent.keyCode` and Carbon's `kVK_*`) and the
/// device-independent modifier flags, restricted to ⌃⌥⇧⌘.
struct KeyCombo: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// ⌘⇧U (keyCode 0x20 == kVK_ANSI_U).
    static let `default` = KeyCombo(keyCode: 0x20, modifiers: [.command, .shift])

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(KeyCombo.relevantModifiers)
    }

    /// A hotkey needs at least one "hard" modifier — shift alone would clash
    /// with normal typing.
    var hasRequiredModifier: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    var displayString: String {
        KeyCombo.symbols(for: modifiers) + KeyCodeMap.string(for: keyCode)
    }

    /// Same symbols as `displayString`, but each component separated by " + "
    /// for prose contexts (e.g. "⌘ + ⇧ + U").
    var spacedDisplayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(KeyCodeMap.string(for: keyCode))
        return parts.joined(separator: " + ")
    }

    /// Best-effort character for an NSMenuItem key equivalent (letters/digits
    /// only); returns nil for keys NSMenu can't easily represent here.
    var menuKeyEquivalent: String? {
        let string = KeyCodeMap.string(for: keyCode)
        guard string.count == 1, let character = string.first,
              character.isLetter || character.isNumber else { return nil }
        return string.lowercased()
    }

    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    // MARK: - Persistence

    var persistentDictionary: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers.rawValue)]
    }

    init?(dictionary: [String: Int]) {
        guard let keyCode = dictionary["keyCode"], let modifiers = dictionary["modifiers"] else { return nil }
        self.init(keyCode: UInt16(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
    }
}

/// Virtual key code → human-readable label for shortcut display.
enum KeyCodeMap {
    static func string(for keyCode: UInt16) -> String {
        map[keyCode] ?? "Key \(keyCode)"
    }

    private static let map: [UInt16: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
        0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
        0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
        0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x18: "=", 0x1B: "-", 0x21: "[", 0x1E: "]", 0x27: "'", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}
