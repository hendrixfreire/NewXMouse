import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox
import os.log

// MARK: - Modifier Key

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    var displayName: String {
        switch self {
        case .command: return "\u{2318}"
        case .option: return "\u{2325}"
        case .control: return "\u{2303}"
        case .shift: return "\u{21E7}"
        }
    }
}

// MARK: - Action

/// A single key press with its modifiers, used in key sequences.
struct KeyCombo: Codable, Equatable {
    var key: UInt16
    var modifiers: [ModifierKey]

    var displayName: String {
        let modStr = modifiers.map(\.displayName).joined()
        return "\(modStr)\(VirtualKey.name(for: key))"
    }
}

enum ActionEditorMode: String, CaseIterable, Identifiable {
    case shortcut
    case keySequence
    case appLaunch
    case shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcut: return "Custom Shortcut"
        case .keySequence: return "Simulated Key Sequence"
        case .appLaunch: return "Launch Application"
        case .shell: return "Run Shell Command"
        }
    }
}

enum ActionQuickPreset: String, CaseIterable, Identifiable {
    case passthrough
    case disabled
    case leftClick
    case leftDoubleClick
    case rightClick
    case rightDoubleClick
    case middleClick
    case middleDoubleClick
    case button4
    case button5
    case missionControl
    case appExpose
    case spotlight
    case volumeUp
    case volumeDown
    case zoomIn
    case zoomOut
    case scrollLeft
    case scrollRight

    var id: String { rawValue }

    /// Presets related to scroll wheel and media control
    static let scrollMediaPresets: [ActionQuickPreset] = [.volumeUp, .volumeDown, .zoomIn, .zoomOut, .scrollLeft, .scrollRight]

    var title: String {
        switch self {
        case .passthrough: return "Pass Through"
        case .disabled: return "Block"
        case .leftClick: return "Left Click"
        case .leftDoubleClick: return "Left Double Click"
        case .rightClick: return "Right Click"
        case .rightDoubleClick: return "Right Double Click"
        case .middleClick: return "Middle Click"
        case .middleDoubleClick: return "Middle Double Click"
        case .button4: return "Click Button 4"
        case .button5: return "Click Button 5"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .spotlight: return "Spotlight"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .scrollLeft: return "Scroll Left"
        case .scrollRight: return "Scroll Right"
        }
    }

    var action: Action {
        switch self {
        case .passthrough:
            return .passthrough
        case .disabled:
            return .disabled
        case .leftClick:
            return .mouseButton(button: MouseButton.left.rawValue)
        case .leftDoubleClick:
            return .doubleClick(button: MouseButton.left.rawValue)
        case .rightClick:
            return .mouseButton(button: MouseButton.right.rawValue)
        case .rightDoubleClick:
            return .doubleClick(button: MouseButton.right.rawValue)
        case .middleClick:
            return .mouseButton(button: MouseButton.middle.rawValue)
        case .middleDoubleClick:
            return .doubleClick(button: MouseButton.middle.rawValue)
        case .button4:
            return .mouseButton(button: MouseButton.side1.rawValue)
        case .button5:
            return .mouseButton(button: MouseButton.side2.rawValue)
        case .missionControl:
            return .keystroke(key: 0x7E, modifiers: [.control])
        case .appExpose:
            return .keystroke(key: 0x7D, modifiers: [.control])
        case .spotlight:
            return .keystroke(key: 0x31, modifiers: [.command])
        case .volumeUp:
            return .shell(command: "osascript -e 'set volume output volume ((output volume of (get volume settings)) + 5)'")
        case .volumeDown:
            return .shell(command: "osascript -e 'set volume output volume ((output volume of (get volume settings)) - 5)'")
        case .zoomIn:
            return .keystroke(key: 0x7E, modifiers: [.command])
        case .zoomOut:
            return .keystroke(key: 0x7D, modifiers: [.command])
        case .scrollLeft:
            return .shell(command: "osascript -e 'tell application \"System Events\" to key code 123 using {command down, option down}'")
        case .scrollRight:
            return .shell(command: "osascript -e 'tell application \"System Events\" to key code 124 using {command down, option down}'")
        }
    }
}

enum Action: Codable, Equatable {
    case keystroke(key: UInt16, modifiers: [ModifierKey])
    case keySequence(keys: [KeyCombo])
    case mouseButton(button: Int)
    case doubleClick(button: Int)
    case appLaunch(bundleID: String)
    case shell(command: String)
    case disabled      // Block the button completely — no action, no passthrough
    case passthrough   // Don't intercept — let the original event through

    static let syntheticEventMarker: Int64 = 0x4E584D

    var displayName: String {
        switch self {
        case .keystroke(let key, let modifiers):
            let modStr = modifiers.map(\.displayName).joined()
            let keyName = VirtualKey.name(for: key)
            return "\(modStr)\(keyName)"
        case .keySequence(let keys):
            return keys.map(\.displayName).joined(separator: " \u{2192} ")
        case .mouseButton(let button):
            if let mouseButton = MouseButton(rawValue: button) {
                return mouseButton.displayName
            }
            return "Mouse Button \(button)"
        case .doubleClick(let button):
            if let mouseButton = MouseButton(rawValue: button) {
                return "Double \(mouseButton.displayName)"
            }
            return "Double Click Button \(button)"
        case .appLaunch(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               let appName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
                return "Launch \(appName)"
            }
            return "Launch \(bundleID)"
        case .shell(let command):
            let preview = command.prefix(30)
            return "Run: \(preview)\(command.count > 30 ? "..." : "")"
        case .disabled:
            return "Block"
        case .passthrough:
            return "Pass Through"
        }
    }

    var typeName: String {
        switch self {
        case .keystroke: return "Shortcut"
        case .keySequence: return "Sequence"
        case .mouseButton: return "Mouse"
        case .doubleClick: return "Double Click"
        case .appLaunch: return "App"
        case .shell: return "Shell"
        case .disabled: return "Disabled"
        case .passthrough: return ""
        }
    }

    var systemImage: String {
        switch self {
        case .keystroke: return "keyboard"
        case .keySequence: return "list.number"
        case .mouseButton: return "computermouse"
        case .doubleClick: return "cursorarrow.click.2"
        case .appLaunch: return "app.badge.checkmark"
        case .shell: return "terminal"
        case .disabled: return "nosign"
        case .passthrough: return ""
        }
    }

    var editorMode: ActionEditorMode? {
        switch self {
        case .keystroke:
            return .shortcut
        case .keySequence:
            return .keySequence
        case .appLaunch:
            return .appLaunch
        case .shell:
            return .shell
        case .mouseButton, .doubleClick, .disabled, .passthrough:
            return nil
        }
    }

    var menuTitle: String {
        if let preset = ActionQuickPreset.allCases.first(where: { $0.action == self }) {
            return preset.title
        }
        return displayName
    }

    var menuSystemImage: String {
        if !systemImage.isEmpty {
            return systemImage
        }
        return "arrow.left.arrow.right"
    }

    func execute(isDown: Bool) {
        switch self {
        case .keystroke(let key, let modifiers):
            if isDown {
                executeKeystroke(key: key, modifiers: modifiers)
            }
        case .keySequence(let keys):
            if isDown { executeKeySequence(keys: keys) }
        case .mouseButton(let button):
            executeMouseButton(button: button, isDown: isDown)
        case .doubleClick(let button):
            if isDown { executeDoubleClick(button: button) }
        case .appLaunch(let bundleID):
            if isDown { executeAppLaunch(bundleID: bundleID) }
        case .shell(let command):
            if isDown { executeShell(command: command) }
        case .disabled:
            break  // Block the event — handled by EventTapManager returning nil
        case .passthrough:
            break  // Should never be called — EventTapManager passes through
        }
    }

    private func keyboardEvent(for key: UInt16, modifiers: [ModifierKey], keyDown: Bool) -> CGEvent? {
        let source = CGEventSource(stateID: .privateState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { return nil }
        var flags: CGEventFlags = []
        for mod in modifiers {
            flags.insert(mod.cgEventFlag)
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        return event
    }

    private func executeKeystroke(key: UInt16, modifiers: [ModifierKey]) {
        keyboardEvent(for: key, modifiers: modifiers, keyDown: true)?.post(tap: .cghidEventTap)
        keyboardEvent(for: key, modifiers: modifiers, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func executeKeySequence(keys: [KeyCombo]) {
        for (i, combo) in keys.enumerated() {
            let delay = UInt64(i) * 30_000_000 // 30ms between each key
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Double(delay) / 1_000_000_000) {
                keyboardEvent(for: combo.key, modifiers: combo.modifiers, keyDown: true)?.post(tap: .cghidEventTap)
                keyboardEvent(for: combo.key, modifiers: combo.modifiers, keyDown: false)?.post(tap: .cghidEventTap)
            }
        }
    }

    private func executeMouseButton(button: Int, isDown: Bool) {
        let mouseType: CGEventType
        let cgButton: CGMouseButton

        switch button {
        case 0:
            mouseType = isDown ? .leftMouseDown : .leftMouseUp
            cgButton = .left
        case 1:
            mouseType = isDown ? .rightMouseDown : .rightMouseUp
            cgButton = .right
        default:
            mouseType = isDown ? .otherMouseDown : .otherMouseUp
            guard let validButton = CGMouseButton(rawValue: UInt32(button)) else { return }
            cgButton = validButton
        }

        let source = CGEventSource(stateID: .privateState)
        let location = CGEvent(source: nil)?.location ?? .zero
        guard let event = CGEvent(mouseEventSource: source, mouseType: mouseType, mouseCursorPosition: location, mouseButton: cgButton) else { return }
        if button >= 2 {
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private func executeDoubleClick(button: Int) {
        let mouseDownType: CGEventType
        let mouseUpType: CGEventType
        let cgButton: CGMouseButton

        switch button {
        case 0:
            mouseDownType = .leftMouseDown
            mouseUpType = .leftMouseUp
            cgButton = .left
        case 1:
            mouseDownType = .rightMouseDown
            mouseUpType = .rightMouseUp
            cgButton = .right
        default:
            mouseDownType = .otherMouseDown
            mouseUpType = .otherMouseUp
            guard let validButton = CGMouseButton(rawValue: UInt32(button)) else { return }
            cgButton = validButton
        }

        let source = CGEventSource(stateID: .privateState)
        let location = CGEvent(source: nil)?.location ?? .zero

        // First click
        if let down1 = CGEvent(mouseEventSource: source, mouseType: mouseDownType, mouseCursorPosition: location, mouseButton: cgButton) {
            if button >= 2 { down1.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button)) }
            down1.setIntegerValueField(.mouseEventClickState, value: 1)
            down1.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            down1.post(tap: .cghidEventTap)
        }
        if let up1 = CGEvent(mouseEventSource: source, mouseType: mouseUpType, mouseCursorPosition: location, mouseButton: cgButton) {
            if button >= 2 { up1.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button)) }
            up1.setIntegerValueField(.mouseEventClickState, value: 1)
            up1.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            up1.post(tap: .cghidEventTap)
        }

        // Second click (clickState = 2 tells macOS this is a double-click)
        if let down2 = CGEvent(mouseEventSource: source, mouseType: mouseDownType, mouseCursorPosition: location, mouseButton: cgButton) {
            if button >= 2 { down2.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button)) }
            down2.setIntegerValueField(.mouseEventClickState, value: 2)
            down2.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            down2.post(tap: .cghidEventTap)
        }
        if let up2 = CGEvent(mouseEventSource: source, mouseType: mouseUpType, mouseCursorPosition: location, mouseButton: cgButton) {
            if button >= 2 { up2.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button)) }
            up2.setIntegerValueField(.mouseEventClickState, value: 2)
            up2.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            up2.post(tap: .cghidEventTap)
        }
    }

    private func executeAppLaunch(bundleID: String) {
        DispatchQueue.main.async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static let shellLog = OSLog(subsystem: "com.newxmouse.app", category: "Shell")

    private func executeShell(command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            os_log("Shell command empty — skipping", log: Self.shellLog, type: .info)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", trimmed]

            // Capture stderr for error reporting
            let errPipe = Pipe()
            process.standardError = errPipe

            do {
                try process.run()

                // Enforce a 10-second timeout
                let timeoutDate = Date().addingTimeInterval(10)
                while process.isRunning && Date() < timeoutDate {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }

                if process.isRunning {
                    process.terminate()
                    os_log("Shell command timed out (10s): %{public}s", log: Self.shellLog, type: .error, trimmed)
                    return
                }

                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrStr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    os_log("Shell command exited %d: %{public}s — %{public}s", log: Self.shellLog, type: .error, exitCode, trimmed, stderrStr)
                }
            } catch {
                os_log("Shell command failed to launch: %{public}s — %{public}s", log: Self.shellLog, type: .error, trimmed, error.localizedDescription)
            }
        }
    }
}

// MARK: - Virtual Key Names

enum VirtualKey {
    static func name(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
            0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'",
            0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x30: "Tab", 0x31: "Space", 0x32: "`", 0x33: "Delete",
            0x35: "Escape",
            0x37: "Command", 0x38: "Shift", 0x39: "CapsLock",
            0x3A: "Option", 0x3B: "Control",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3",
            0x64: "F8", 0x65: "F9", 0x67: "F11", 0x69: "F13",
            0x6B: "F14", 0x6D: "F10", 0x6F: "F12",
            0x71: "F15", 0x72: "Help", 0x73: "Home", 0x74: "PageUp",
            0x75: "ForwardDelete", 0x76: "F4", 0x77: "End",
            0x78: "F2", 0x79: "PageDown", 0x7A: "F1",
            0x7B: "\u{2190}", 0x7C: "\u{2192}", 0x7D: "\u{2193}", 0x7E: "\u{2191}",
        ]
        return names[keyCode] ?? "Key(\(keyCode))"
    }

    static let allKeys: [(name: String, code: UInt16)] = [
        ("A", 0x00), ("B", 0x0B), ("C", 0x08), ("D", 0x02), ("E", 0x0E),
        ("F", 0x03), ("G", 0x05), ("H", 0x04), ("I", 0x22), ("J", 0x26),
        ("K", 0x28), ("L", 0x25), ("M", 0x2E), ("N", 0x2D), ("O", 0x1F),
        ("P", 0x23), ("Q", 0x0C), ("R", 0x0F), ("S", 0x01), ("T", 0x11),
        ("U", 0x20), ("V", 0x09), ("W", 0x0D), ("X", 0x07), ("Y", 0x10),
        ("Z", 0x06),
        ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("5", 0x17),
        ("6", 0x16), ("7", 0x1A), ("8", 0x1C), ("9", 0x19), ("0", 0x1D),
        ("Return", 0x24), ("Tab", 0x30), ("Space", 0x31), ("Delete", 0x33),
        ("Escape", 0x35),
        ("F1", 0x7A), ("F2", 0x78), ("F3", 0x63), ("F4", 0x76),
        ("F5", 0x60), ("F6", 0x61), ("F7", 0x62), ("F8", 0x64),
        ("F9", 0x65), ("F10", 0x6D), ("F11", 0x67), ("F12", 0x6F),
        ("\u{2190} Left", 0x7B), ("\u{2192} Right", 0x7C),
        ("\u{2193} Down", 0x7D), ("\u{2191} Up", 0x7E),
        ("Home", 0x73), ("End", 0x77), ("PageUp", 0x74), ("PageDown", 0x79),
    ]
}
