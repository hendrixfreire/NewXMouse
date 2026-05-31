import SwiftUI
import Carbon.HIToolbox

/// SwiftUI wrapper for the key recorder.
struct KeyRecorderView: View {
    @Binding var recordedKeys: [KeyCombo]
    var maxKeys: Int = 3

    @StateObject private var recorder = KeyRecorderState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recorder button
            Button {
                if recorder.isRecording {
                    recorder.stop(confirmed: false)
                } else {
                    recorder.start(maxKeys: maxKeys)
                }
            } label: {
                HStack {
                    if recorder.isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        if recorder.currentKeys.isEmpty {
                            Text("Press a key combo... (Esc to cancel)")
                                .foregroundColor(.secondary)
                        } else {
                            let remaining = maxKeys - recorder.currentKeys.count
                            Text(recorder.currentKeys.map(\.displayName).joined(separator: " \u{2192} "))
                            if remaining > 0 {
                                Text("(\(remaining) left)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if recordedKeys.isEmpty {
                        Image(systemName: "record.circle")
                            .foregroundColor(.secondary)
                        Text("Click to record keys...")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "keyboard")
                        Text(recordedKeys.map(\.displayName).joined(separator: " \u{2192} "))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recorder.isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: recorder.isRecording ? 2 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(recorder.isRecording ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                )
            }
            .buttonStyle(.plain)

            if recorder.isRecording {
                Text("Press keys in sequence. **Enter** to confirm, **Esc** to cancel.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: recorder.finishedKeys) { newValue in
            if let keys = newValue {
                recordedKeys = keys
                recorder.finishedKeys = nil
            }
        }
        .onDisappear {
            recorder.stop(confirmed: false)
        }
    }
}

// MARK: - Recording State

final class KeyRecorderState: ObservableObject {
    @Published var isRecording = false
    @Published var currentKeys: [KeyCombo] = []
    @Published var finishedKeys: [KeyCombo]?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var flagsMonitor: Any?
    private var maxKeys: Int = 3

    func start(maxKeys: Int) {
        self.maxKeys = maxKeys
        isRecording = true
        currentKeys = []
        finishedKeys = nil

        // Local monitor catches key events when the app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        // Global monitor catches keys if focus moves away
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return }
            _ = self.handleKeyDown(event)
        }
    }

    func stop(confirmed: Bool) {
        guard isRecording else { return }
        isRecording = false

        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        localMonitor = nil
        globalMonitor = nil
        flagsMonitor = nil

        if confirmed && !currentKeys.isEmpty {
            finishedKeys = currentKeys
        } else {
            finishedKeys = []
        }
        currentKeys = []
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode

        // Escape cancels
        if keyCode == 0x35 {
            stop(confirmed: false)
            return true
        }

        // Enter/Return confirms
        if keyCode == 0x24 || keyCode == 0x4C {
            if !currentKeys.isEmpty {
                stop(confirmed: true)
            }
            return true
        }

        // Skip pure modifier keys
        let modifierKeyCodes: Set<UInt16> = [0x37, 0x38, 0x3A, 0x3B, 0x36, 0x3C, 0x3D, 0x3E]
        if modifierKeyCodes.contains(keyCode) { return true }

        // Build modifier list
        var modifiers: [ModifierKey] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.append(.command) }
        if flags.contains(.option) { modifiers.append(.option) }
        if flags.contains(.control) { modifiers.append(.control) }
        if flags.contains(.shift) { modifiers.append(.shift) }

        let combo = KeyCombo(key: keyCode, modifiers: modifiers)
        currentKeys.append(combo)

        if currentKeys.count >= maxKeys {
            stop(confirmed: true)
        }

        return true
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
    }
}
