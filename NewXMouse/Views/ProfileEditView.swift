import SwiftUI

struct ProfileEditView: View {
    let bundleID: String
    var onDelete: (() -> Void)?
    @EnvironmentObject var configStore: ConfigStore

    @State private var newLayerName = ""
    @State private var showAddLayer = false
    @State private var editingLayerID: UUID?
    @State private var editingLayerName = ""
    @State private var showClearConfirmation = false

    private var hasMappings: Bool {
        profile.activeLayer?.mappings.values.contains { $0.action != .passthrough && $0.action != .disabled && $0.enabled } ?? false
    }

    private var profile: AppProfile {
        if bundleID == ProfileConstants.defaultBundleID {
            return configStore.defaultProfile
        }
        return configStore.appProfiles.first { $0.bundleID == bundleID }
            ?? AppProfile(bundleID: bundleID, displayName: bundleID)
    }

    private func clearAllMappings() {
        configStore.clearMappings(for: bundleID)
    }

    private func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([configStore.configFileURL])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeader
                layerSelector
                mappingsSection
                profileInfoSection
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            ProfileIconView(bundleID: bundleID, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName)
                    .font(.title2.weight(.semibold))

                Text(bundleID == ProfileConstants.defaultBundleID ? "Fallback profile used when no app-specific mapping is available." : bundleID)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    _ = configStore.save(showConfirmation: true)
                } label: {
                    Label("Save Profile", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                if hasMappings {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear Mappings", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                if bundleID != ProfileConstants.defaultBundleID {
                    Button(role: .destructive) {
                        onDelete?()
                    } label: {
                        Label("Delete Profile", systemImage: "minus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .alert("Clear All Mappings?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                clearAllMappings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all button mappings from the active layer. This cannot be undone.")
        }
    }

    // MARK: - Layer Selector

    private var layerSelector: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Layer picker with active mapping count badges
                    Picker("Active Layer", selection: Binding(
                        get: { profile.activeLayerID },
                        set: { configStore.switchToLayer(id: $0, for: bundleID) }
                    )) {
                        ForEach(profile.layers) { layer in
                            HStack {
                                Text(layer.name)
                                if layer.isDefault {
                                    Text("default")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                let mappingCount = layer.mappings.values.filter { $0.action != .passthrough && $0.action != .disabled && $0.enabled }.count
                                if mappingCount > 0 {
                                    Text("\(mappingCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                            .tag(layer.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 240)

                    // Layer actions
                    Button {
                        configStore.duplicateLayer(id: profile.activeLayerID, for: bundleID)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Duplicate current layer")
                    .buttonStyle(.bordered)

                    if !profile.layers.isEmpty && profile.layers.filter({ !$0.isDefault }).count > 0,
                       profile.activeLayer?.isDefault == false {
                        Button(role: .destructive) {
                            configStore.removeLayer(id: profile.activeLayerID, for: bundleID)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete current layer")
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    // Add layer
                    Button {
                        showAddLayer = true
                    } label: {
                        Label("Add Layer", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                // Inline rename
                if editingLayerID != nil {
                    HStack(spacing: 8) {
                        TextField("Layer name", text: $editingLayerName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Button("Save") {
                            if let id = editingLayerID {
                                configStore.renameLayer(id: id, name: editingLayerName, for: bundleID)
                            }
                            editingLayerID = nil
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Cancel") {
                            editingLayerID = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Layer info with active indicator
                if profile.layers.count > 1 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text("\(profile.layers.count) layers — active: \(profile.activeLayer?.name ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Add multiple layers to switch between different button configurations for the same app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } label: {
            Label("Layers", systemImage: "square.3.layers.3d")
        }
        .alert("New Layer", isPresented: $showAddLayer) {
            TextField("Layer name", text: $newLayerName)
            Button("Create") {
                let name = newLayerName.isEmpty ? "Layer \(profile.layers.count + 1)" : newLayerName
                configStore.addLayer(name: name, for: bundleID)
                newLayerName = ""
            }
            Button("Cancel", role: .cancel) {
                newLayerName = ""
            }
        } message: {
            Text("Enter a name for the new layer.")
        }
        .contextMenu {
            Button("Rename Current Layer") {
                editingLayerID = profile.activeLayerID
                editingLayerName = profile.activeLayer?.name ?? ""
            }
        }
    }

    // MARK: - Mappings

    private var mappingsSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                let activeMappings = profile.activeLayer?.mappings ?? [:]

                // Button mappings
                ForEach(Array(MouseButton.remappable.filter { !$0.isScroll }.enumerated()), id: \.element.id) { index, button in
                    MappingRow(
                        button: button,
                        entry: activeMappings[button],
                        onActionChanged: { newAction in
                            configStore.setMapping(button: button, action: newAction, for: bundleID)
                        },
                        onEnabledChanged: { enabled in
                            configStore.setMappingEnabled(button: button, enabled: enabled, for: bundleID)
                        },
                        onEditRequested: {
                            // When enabling an unmapped button, open the action menu
                        }
                    )
                    .padding(.vertical, 12)

                    if index < MouseButton.remappable.filter { !$0.isScroll }.count - 1 {
                        Divider()
                    }
                }

                // Scroll wheel section
                if !MouseButton.remappable.filter({ $0.isScroll }).isEmpty {
                    Divider()
                    HStack {
                        Image(systemName: "scroll")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Scroll Wheel")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)

                    ForEach(Array(MouseButton.remappable.filter { $0.isScroll }.enumerated()), id: \.element.id) { index, button in
                        MappingRow(
                            button: button,
                            entry: activeMappings[button],
                            onActionChanged: { newAction in
                                configStore.setMapping(button: button, action: newAction, for: bundleID)
                            },
                            onEnabledChanged: { enabled in
                                configStore.setMappingEnabled(button: button, enabled: enabled, for: bundleID)
                            },
                            onEditRequested: {}
                        )
                        .padding(.vertical, 12)

                        if index < MouseButton.remappable.filter { $0.isScroll }.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        } label: {
            Label("Button Mappings", systemImage: "computermouse")
        }
    }

    // MARK: - Profile Info

    private var profileInfoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ProfileInfoRow(label: "Profile Type", value: bundleID == ProfileConstants.defaultBundleID ? "Default" : "Application-specific")
                ProfileInfoRow(label: "Display Name", value: profile.displayName)
                ProfileInfoRow(label: "Bundle Identifier", value: bundleID == ProfileConstants.defaultBundleID ? "All Applications" : bundleID)
                ProfileInfoRow(label: "Layers", value: "\(profile.layers.count)")
                ProfileInfoRow(label: "Active Layer", value: profile.activeLayer?.name ?? "Unknown")
                ProfileInfoRow(label: "Configured Buttons", value: "\(profile.activeLayer?.mappings.values.filter { $0.action != .passthrough && $0.action != .disabled && $0.enabled }.count ?? 0)")

                if let saveFeedback = configStore.lastManualSave {
                    Divider()

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Profile saved at:")
                                .font(.subheadline.weight(.semibold))
                            Text(saveFeedback.url.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)

                            Button("Open in Finder") {
                                revealConfigInFinder()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        } label: {
            Label("Profile Information", systemImage: "info.circle")
        }
    }
}

struct MappingRow: View {
    let button: MouseButton
    let entry: MappingEntry?   // nil = never configured
    let onActionChanged: (Action) -> Void
    let onEnabledChanged: (Bool) -> Void
    let onEditRequested: () -> Void

    @State private var editorMode: ActionEditorMode?

    private var action: Action { entry?.action ?? .passthrough }
    private var isEnabled: Bool { entry?.enabled ?? false }
    /// True if this button has never been explicitly configured
    private var isUnconfigured: Bool { entry == nil }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newVal in
                    onEnabledChanged(newVal)
                    // When enabling an unconfigured button, auto-set to "Pass Through"
                    // so the user sees it's active and can change it
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(isEnabled ? "Disable this mapping" : "Enable this mapping")

            VStack(alignment: .leading, spacing: 4) {
                Text(button.displayName)
                    .font(.body.weight(.medium))
                Text(helperText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 200, alignment: .leading)
            .opacity(isEnabled ? 1.0 : 0.5)

            Spacer(minLength: 0)

            Menu {
                Section("Quick Actions") {
                    ForEach(ActionQuickPreset.allCases.filter { !ActionQuickPreset.scrollMediaPresets.contains($0) }, id: \.id) { preset in
                        Button {
                            onActionChanged(preset.action)
                        } label: {
                            if action == preset.action {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Text(preset.title)
                            }
                        }
                    }
                }

                Section("Scroll & Media") {
                    ForEach([ActionQuickPreset.volumeUp, .volumeDown, .zoomIn, .zoomOut, .scrollLeft, .scrollRight], id: \.id) { preset in
                        Button {
                            onActionChanged(preset.action)
                        } label: {
                            if action == preset.action {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Text(preset.title)
                            }
                        }
                    }
                }

                Section("Custom Actions") {
                    Button("Custom Shortcut...") {
                        editorMode = .shortcut
                    }

                    Button("Simulated Key Sequence...") {
                        editorMode = .keySequence
                    }

                    Button("Launch Application...") {
                        editorMode = .appLaunch
                    }

                    Button("Run Shell Command...") {
                        editorMode = .shell
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Label(action.menuTitle, systemImage: action.menuSystemImage)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 290, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!isEnabled)

            Button {
                editorMode = action.editorMode ?? .shortcut
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Open advanced editor")
            .buttonStyle(.bordered)
            .disabled(!isEnabled || isUnconfigured)
        }
        .sheet(item: $editorMode) { mode in
            ActionEditorView(
                button: button,
                currentAction: action,
                initialMode: mode,
                onSave: { newAction in
                    onActionChanged(newAction)
                    editorMode = nil
                },
                onCancel: {
                    editorMode = nil
                }
            )
        }
    }

    private var helperText: String {
        if !isEnabled {
            return "Mapping disabled — original button behavior preserved."
        }
        if isUnconfigured {
            return "Not configured — select an action from the menu."
        }
        if action == .passthrough {
            return "Let the original button event through without intercepting."
        }
        if action == .disabled {
            return "Block the button completely — nothing happens when pressed."
        }
        if ActionQuickPreset.allCases.contains(where: { $0.action == action }) {
            return "Preset action"
        }
        return "Custom action"
    }
}

private struct ProfileInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

struct ProfileIconView: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = applicationIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: bundleID == ProfileConstants.defaultBundleID ? "globe" : "app")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundColor(.accentColor)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var applicationIcon: NSImage? {
        guard bundleID != ProfileConstants.defaultBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
