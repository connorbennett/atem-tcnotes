import SwiftUI
import AppKit

/// The eight marker colours Premiere Pro offers.
enum MarkerColor: String, Codable, CaseIterable, Identifiable {
    case green, red, purple, orange, yellow, white, blue, cyan

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var rgb: (r: UInt32, g: UInt32, b: UInt32) {
        switch self {
        case .green: (0x4C, 0xB0, 0x50)
        case .red: (0xE0, 0x40, 0x40)
        case .purple: (0x9B, 0x59, 0xD0)
        case .orange: (0xF0, 0x8A, 0x24)
        case .yellow: (0xE8, 0xCE, 0x2E)
        case .white: (0xE6, 0xE6, 0xE6)
        case .blue: (0x3D, 0x7D, 0xF0)
        case .cyan: (0x2E, 0xC4, 0xD6)
        }
    }

    var color: Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    /// Premiere's `pproColor` is a packed ABGR integer. Where editingtools.io's exports use a specific
    /// value for a colour, that exact value is used so Premiere treats the markers the same way.
    var pproColor: UInt32 {
        switch self {
        case .blue: 4_294_741_314
        case .red: 4_281_740_498
        case .cyan: 4_292_277_273
        default: 0xFF00_0000 | rgb.b << 16 | rgb.g << 8 | rgb.r
        }
    }
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var timecode: Timecode
    var name: String
    var text: String
    var color: MarkerColor
    var created = Date()
}

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var display: String

    private static let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        display = s + key
    }

    /// Hotkeys need ⌘, ⌃ or ⌥ (or to be a function key) so they never collide with typing a note.
    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection(Self.relevant)
        let functionKey = Self.functionKeys[event.keyCode]
        guard functionKey != nil || !mods.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let key = functionKey
            ?? (event.keyCode == 49 ? "Space" : event.charactersIgnoringModifiers?.uppercased())
            ?? "Key \(event.keyCode)"
        self.init(keyCode: event.keyCode, modifiers: mods, key: key)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevant).rawValue == modifiers
    }
}

struct Shortcut: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var text = ""
    var color: MarkerColor
    var hotkey: Hotkey?

    static var defaults: [Shortcut] {
        let items: [(String, MarkerColor, UInt16)] = [
            ("GFX", .cyan, 18), ("VFX", .purple, 19), ("TAKE", .green, 20),
            ("MUSIC", .orange, 21), ("AUDIO", .yellow, 23), ("CHECK", .red, 22),
        ]
        return items.enumerated().map { index, item in
            Shortcut(label: item.0, color: item.1,
                     hotkey: Hotkey(keyCode: item.2, modifiers: .control, key: "\(index + 1)"))
        }
    }
}

enum TimecodeSource: String, CaseIterable, Identifiable {
    case ntp, atem
    var id: String { rawValue }
    var label: String { self == .ntp ? "NTP time of day" : "ATEM switcher" }
}

enum ATEMState: Equatable {
    case disconnected
    case connecting
    case connected(String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}
