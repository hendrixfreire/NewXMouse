import SwiftUI

struct ActionEditorView: View {
    let button: MouseButton
    let currentAction: Action
    let initialMode: ActionEditorMode
    let onSave: (Action) -> Void
    let onCancel: () -> Void

    @State private var editorMode: ActionEditorMode
    @State private var selectedKeyCode: UInt16 = 0x06
    @State private var useCommand = false
    @State private var useOption = false
    @State private var useControl = false
    @State private var useShift = false
    @State private var recordedKeys: [KeyCombo] = []
    @State private var recorderCapture: [KeyCombo] = []
    @State private var appBundleID: String = ""
    @State private var shellCommand: String = ""

    init(
        button: MouseButton,
        currentAction: Action,
        initialMode: ActionEditorMode,
        onSave: @escaping (Action) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.button = button
        self.currentAction = currentAction
        self.initialMode = initialMode
        self.onSave = onSave
        self.onCancel = onCancel
        _editorMode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section("Action Type") {
                    Picker("Type", selection: $editorMode) {
                        ForEach(ActionEditorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                switch editorMode {
                case .shortcut:
                    shortcutSection
                case .keySequence:
                    keySequenceSection
                case .appLaunch:
                    appLaunchSection
                case .shell:
                    shellSection
                }

                Section("Preview") {
                    Label(buildAction().displayName, systemImage: buildAction().menuSystemImage)
                        .font(.body.weight(.medium))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(buildAction())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onAppear(perform: loadCurrent)
        .onChange(of: recorderCapture) { newValue in
            guard !newValue.isEmpty else { return }
            recordedKeys.append(contentsOf: newValue)
            recorderCapture = []
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(initialMode.title)
                .font(.title3.weight(.semibold))
            Text("Configure the action for \(button.displayName.lowercased()).")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var shortcutSection: some View {
        Section("Shortcut") {
            Picker("Key", selection: $selectedKeyCode) {
                ForEach(VirtualKey.allKeys, id: \.code) { key in
                    Text(key.name).tag(key.code)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Modifiers")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 18) {
                    Toggle("\u{2318} Command", isOn: $useCommand)
                    Toggle("\u{2325} Option", isOn: $useOption)
                    Toggle("\u{2303} Control", isOn: $useControl)
                    Toggle("\u{21E7} Shift", isOn: $useShift)
                }
                .toggleStyle(.checkbox)
            }
            .padding(.vertical, 4)
        }
    }

    private var keySequenceSection: some View {
        Section("Sequence Builder") {
            Text("Build the sequence in the order it should run when the mouse button is pressed.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if recordedKeys.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.number")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("No keys added yet")
                        .font(.subheadline.weight(.medium))
                    Text("Add a step manually or record a sequence.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(Array(recordedKeys.indices), id: \.self) { index in
                    SequenceStepEditor(
                        title: "Step \(index + 1)",
                        combo: $recordedKeys[index],
                        canMoveUp: index > 0,
                        canMoveDown: index < recordedKeys.count - 1,
                        onMoveUp: { moveStep(from: index, to: index - 1) },
                        onMoveDown: { moveStep(from: index, to: index + 1) },
                        onDelete: { recordedKeys.remove(at: index) }
                    )
                }
            }

            HStack {
                Button {
                    recordedKeys.append(KeyCombo(key: 0x06, modifiers: []))
                } label: {
                    Label("Add Step", systemImage: "plus")
                }

                Spacer()

                if !recordedKeys.isEmpty {
                    Button("Clear Sequence", role: .destructive) {
                        recordedKeys.removeAll()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Record Keys")
                    .font(.subheadline.weight(.medium))
                KeyRecorderView(recordedKeys: $recorderCapture, maxKeys: 8)
            }
            .padding(.top, 4)
        }
    }

    private var appLaunchSection: some View {
        Section("Application") {
            TextField("Bundle identifier", text: $appBundleID)
            Text("Example: com.apple.Safari")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var shellSection: some View {
        Section("Shell Command") {
            TextEditor(text: $shellCommand)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
            Text("The command runs with zsh when the button is pressed.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func moveStep(from source: Int, to destination: Int) {
        guard recordedKeys.indices.contains(source), recordedKeys.indices.contains(destination) else { return }
        let item = recordedKeys.remove(at: source)
        recordedKeys.insert(item, at: destination)
    }

    private func buildAction() -> Action {
        switch editorMode {
        case .shortcut:
            var modifiers: [ModifierKey] = []
            if useCommand { modifiers.append(.command) }
            if useOption { modifiers.append(.option) }
            if useControl { modifiers.append(.control) }
            if useShift { modifiers.append(.shift) }
            return .keystroke(key: selectedKeyCode, modifiers: modifiers)
        case .keySequence:
            let cleanedSequence = recordedKeys
            return cleanedSequence.isEmpty ? .passthrough : .keySequence(keys: cleanedSequence)
        case .appLaunch:
            let trimmedBundleID = appBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedBundleID.isEmpty ? .passthrough : .appLaunch(bundleID: trimmedBundleID)
        case .shell:
            let trimmedCommand = shellCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCommand.isEmpty ? .passthrough : .shell(command: trimmedCommand)
        }
    }

    private func loadCurrent() {
        switch currentAction {
        case .keystroke(let key, let modifiers):
            editorMode = initialMode == .keySequence ? .keySequence : .shortcut
            selectedKeyCode = key
            useCommand = modifiers.contains(.command)
            useOption = modifiers.contains(.option)
            useControl = modifiers.contains(.control)
            useShift = modifiers.contains(.shift)
        case .keySequence(let keys):
            editorMode = .keySequence
            recordedKeys = keys
        case .appLaunch(let bundleID):
            editorMode = .appLaunch
            appBundleID = bundleID
        case .shell(let command):
            editorMode = .shell
            shellCommand = command
        case .mouseButton, .doubleClick, .disabled, .passthrough:
            editorMode = initialMode
        }
    }
}

private struct SequenceStepEditor: View {
    let title: String
    @Binding var combo: KeyCombo
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)

                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Picker("Key", selection: $combo.key) {
                ForEach(VirtualKey.allKeys, id: \.code) { key in
                    Text(key.name).tag(key.code)
                }
            }

            HStack(spacing: 18) {
                modifierToggle("\u{2318} Command", modifier: .command)
                modifierToggle("\u{2325} Option", modifier: .option)
                modifierToggle("\u{2303} Control", modifier: .control)
                modifierToggle("\u{21E7} Shift", modifier: .shift)
            }
            .toggleStyle(.checkbox)
        }
        .padding(.vertical, 6)
    }

    private func modifierToggle(_ title: String, modifier: ModifierKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { combo.modifiers.contains(modifier) },
                set: { isOn in
                    if isOn {
                        if !combo.modifiers.contains(modifier) {
                            combo.modifiers.append(modifier)
                        }
                    } else {
                        combo.modifiers.removeAll { $0 == modifier }
                    }
                }
            )
        )
    }
}
