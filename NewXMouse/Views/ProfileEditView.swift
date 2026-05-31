import SwiftUI

struct ProfileEditView: View {
    let bundleID: String
    var onDelete: (() -> Void)?
    @EnvironmentObject var configStore: ConfigStore

    private var hasMappings: Bool {
        profile.mappings.values.contains { $0 != .none }
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
                mappingsSection
                profileInfoSection
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

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
                    Button {
                        clearAllMappings()
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
    }

    private var mappingsSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                // Button mappings
                ForEach(Array(MouseButton.remappable.filter { !$0.isScroll }.enumerated()), id: \.element.id) { index, button in
                    MappingRow(
                        button: button,
                        action: profile.mappings[button] ?? .none,
                        onActionChanged: { newAction in
                            configStore.setMapping(button: button, action: newAction, for: bundleID)
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
                            action: profile.mappings[button] ?? .none,
                            onActionChanged: { newAction in
                                configStore.setMapping(button: button, action: newAction, for: bundleID)
                            }
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

    private var profileInfoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ProfileInfoRow(label: "Profile Type", value: bundleID == ProfileConstants.defaultBundleID ? "Default" : "Application-specific")
                ProfileInfoRow(label: "Display Name", value: profile.displayName)
                ProfileInfoRow(label: "Bundle Identifier", value: bundleID == ProfileConstants.defaultBundleID ? "All Applications" : bundleID)
                ProfileInfoRow(label: "Configured Buttons", value: "\(profile.mappings.values.filter { $0 != .none }.count)")

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
    let action: Action
    let onActionChanged: (Action) -> Void

    @State private var editorMode: ActionEditorMode?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(button.displayName)
                    .font(.body.weight(.medium))
                Text(helperText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 200, alignment: .leading)

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
                    Button("Custom Shortcut…") {
                        editorMode = .shortcut
                    }

                    Button("Simulated Key Sequence…") {
                        editorMode = .keySequence
                    }

                    Button("Launch Application…") {
                        editorMode = .appLaunch
                    }

                    Button("Run Shell Command…") {
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

            Button {
                editorMode = action.editorMode ?? .shortcut
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Open advanced editor")
            .buttonStyle(.bordered)
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
        if action == .none {
            return "Pass through without intercepting the original button."
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
