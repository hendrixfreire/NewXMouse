import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var eventTapManager: EventTapManager
    @EnvironmentObject var activeAppMonitor: ActiveAppMonitor
    @EnvironmentObject var accessibilityChecker: AccessibilityChecker
    @State private var selectedProfileID: String? = ProfileConstants.defaultBundleID
    @State private var showingDiagnostics = false
    @State private var showImportConfirmation = false
    @State private var pendingImportURL: URL?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProfileID) {
                Section("Global") {
                    HStack(spacing: 10) {
                        ProfileIconView(bundleID: ProfileConstants.defaultBundleID, size: 18)
                        Text("Default")
                    }
                        .tag(ProfileConstants.defaultBundleID)
                }

                Section("Applications") {
                    ForEach(configStore.appProfiles) { profile in
                        HStack(spacing: 10) {
                            ProfileIconView(bundleID: profile.bundleID, size: 18)
                            Text(profile.displayName)
                        }
                            .tag(profile.bundleID)
                            .contextMenu {
                                Button {
                                    configStore.duplicateProfile(bundleID: profile.bundleID)
                                } label: {
                                    Label("Duplicate Profile", systemImage: "doc.on.doc")
                                }

                                Button {
                                    exportSingleProfile(bundleID: profile.bundleID, displayName: profile.displayName)
                                } label: {
                                    Label("Export Profile", systemImage: "square.and.arrow.up")
                                }

                                Button {
                                    importSingleProfile()
                                } label: {
                                    Label("Import Profile", systemImage: "square.and.arrow.down.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    if selectedProfileID == profile.bundleID {
                                        selectedProfileID = ProfileConstants.defaultBundleID
                                    }
                                    configStore.removeProfile(bundleID: profile.bundleID)
                                } label: {
                                    Label("Delete Profile", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let bundleID = configStore.appProfiles[index].bundleID
                            if selectedProfileID == bundleID {
                                selectedProfileID = ProfileConstants.defaultBundleID
                            }
                            configStore.removeProfile(bundleID: bundleID)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // On/Off toggle
                    Toggle(isOn: Binding(
                        get: { eventTapManager.isRunning },
                        set: { on in
                            if on {
                                if accessibilityChecker.canInterceptEvents {
                                    eventTapManager.start()
                                } else {
                                    accessibilityChecker.promptIfNeeded()
                                }
                            } else {
                                eventTapManager.stop()
                            }
                        }
                    )) {
                        Image(systemName: eventTapManager.isRunning ? "power.circle.fill" : "power.circle")
                    }
                    .toggleStyle(.button)
                    .help(eventTapManager.isRunning ? "Disable Remapping" : "Enable Remapping")
                    .tint(eventTapManager.isRunning ? .green : .secondary)

                    Button {
                        exportConfig()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export Configuration")

                    Button {
                        importConfig()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Import Configuration")

                    Button {
                        showingDiagnostics.toggle()
                    } label: {
                        Image(systemName: diagnosticsNeedsAttention ? "stethoscope.circle.fill" : "stethoscope.circle")
                    }
                    .help("Diagnostics")
                    .popover(isPresented: $showingDiagnostics) {
                        DiagnosticsPanel()
                            .frame(width: 520)
                            .padding(16)
                    }

                    AddAppButton(configStore: configStore)
                }
            }
        } detail: {
            if let profileID = selectedProfileID {
                ProfileEditView(bundleID: profileID, onDelete: profileID != ProfileConstants.defaultBundleID ? {
                    selectedProfileID = ProfileConstants.defaultBundleID
                    configStore.removeProfile(bundleID: profileID)
                } : nil)
                    .id(profileID)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sidebar.left")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a Profile")
                        .font(.title3.weight(.semibold))
                    Text("Choose a default mapping or add an application-specific profile.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .alert("Replace Configuration?", isPresented: $showImportConfirmation) {
            Button("Replace", role: .destructive) {
                if let url = pendingImportURL {
                    if !configStore.importConfig(from: url) {
                        showAlert(title: "Import Failed", message: configStore.lastSaveError ?? "Unknown error")
                    }
                }
                pendingImportURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("Importing a full configuration will replace all your current profiles and mappings. This cannot be undone.")
        }
    }

    private var diagnosticsNeedsAttention: Bool {
        !accessibilityChecker.hasRequiredAccess || !eventTapManager.isRunning
    }

    // MARK: - Import / Export

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "newxmouse-config.json"
        panel.message = "Export New X Mouse configuration"
        if panel.runModal() == .OK, let url = panel.url {
            if !configStore.exportConfig(to: url) {
                showAlert(title: "Export Failed", message: configStore.lastSaveError ?? "Unknown error")
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Import New X Mouse configuration"
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showImportConfirmation = true
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func exportSingleProfile(bundleID: String, displayName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "newxmouse-\(displayName.lowercased().replacingOccurrences(of: " ", with: "-")).json"
        panel.message = "Export profile for \(displayName)"
        if panel.runModal() == .OK, let url = panel.url {
            if !configStore.exportProfile(bundleID: bundleID, to: url) {
                showAlert(title: "Export Failed", message: configStore.lastSaveError ?? "Unknown error")
            }
        }
    }

    private func importSingleProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Import a New X Mouse profile"
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !configStore.importProfile(from: url) {
                showAlert(title: "Import Failed", message: configStore.lastSaveError ?? "Unknown error")
            }
        }
    }
}

struct AddAppButton: View {
    @ObservedObject var configStore: ConfigStore
    @State private var showingAppPicker = false

    var body: some View {
        Button {
            showingAppPicker = true
        } label: {
            Label("Add Profile", systemImage: "plus")
        }
        .popover(isPresented: $showingAppPicker) {
            AppPickerView(configStore: configStore, isPresented: $showingAppPicker)
                .frame(width: 400, height: 500)
        }
    }
}

// MARK: - Installed App Model

struct InstalledApp: Identifiable {
    let bundleID: String
    let displayName: String
    let url: URL

    var id: String { bundleID }

    /// Lazy-loaded icon — only created when the row appears on screen
    var icon: NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        return img
    }
}

// MARK: - App Picker

struct AppPickerView: View {
    @ObservedObject var configStore: ConfigStore
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var installedApps: [InstalledApp] = []
    @State private var showManualEntry = false
    @State private var manualBundleID = ""
    @State private var manualName = ""
    @State private var isScanning = true

    private let searchDebounce = 0.3

    var filteredApps: [InstalledApp] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter { app in
            app.displayName.localizedCaseInsensitiveContains(searchText) ||
            app.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Application")
                    .font(.headline)
                Text("Choose an installed app or enter a bundle ID manually.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            TextField("Search by name or bundle ID...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 6)

            // Loading or list
            if isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning installed applications...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps) { app in
                    Button {
                        let profile = AppProfile(
                            bundleID: app.bundleID,
                            displayName: app.displayName
                        )
                        configStore.addProfile(profile)
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.displayName)
                                    .font(.body)
                                Text(app.bundleID)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            if configStore.appProfiles.contains(where: { $0.bundleID == app.bundleID }) {
                                Text("Added")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if filteredApps.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 6) {
                        Text("No matching apps found.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Try entering the bundle ID manually.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }

            Divider()

            // Manual entry section
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { showManualEntry.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showManualEntry ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text("Enter Bundle ID Manually")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.plain)

                if showManualEntry {
                    HStack(spacing: 8) {
                        TextField("Bundle ID (e.g. com.apple.Safari)", text: $manualBundleID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        TextField("Display Name", text: $manualName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Button("Add") {
                            guard !manualBundleID.isEmpty else { return }
                            let profile = AppProfile(
                                bundleID: manualBundleID,
                                displayName: manualName.isEmpty ? manualBundleID : manualName
                            )
                            configStore.addProfile(profile)
                            manualBundleID = ""
                            manualName = ""
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualBundleID.isEmpty)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .onAppear {
            scanInstalledApps()
        }
    }

    // MARK: - Scan

    private func scanInstalledApps() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            var apps = [InstalledApp]()
            var seen = Set<String>()

            let searchPaths = [
                "/Applications",
                "/System/Applications",
                "/System/Applications/Utilities",
                NSHomeDirectory() + "/Applications",
                "/Developer/Applications"
            ]

            for searchPath in searchPaths {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: searchPath), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { continue }

                for case let fileURL as URL in enumerator {
                    guard fileURL.pathExtension == "app" else { continue }
                    guard let bundle = Bundle(url: fileURL),
                          let bundleID = bundle.bundleIdentifier,
                          !seen.contains(bundleID) else { continue }

                    seen.insert(bundleID)
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                                ?? fileURL.deletingPathExtension().lastPathComponent

                    apps.append(InstalledApp(
                        bundleID: bundleID,
                        displayName: name,
                        url: fileURL
                    ))
                }
            }

            apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            DispatchQueue.main.async {
                self.installedApps = apps
                self.isScanning = false
            }
        }
    }
}

private struct DiagnosticsPanel: View {
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var eventTapManager: EventTapManager
    @EnvironmentObject var activeAppMonitor: ActiveAppMonitor
    @EnvironmentObject var accessibilityChecker: AccessibilityChecker
    private var activeProfileName: String {
        configStore.activeProfile(for: activeAppMonitor.currentBundleID).displayName
    }

    private var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics")
                .font(.headline)

            HStack(spacing: 18) {
                DiagnosticStatusBadge(
                    title: "Accessibility",
                    value: accessibilityChecker.isGranted ? "Granted" : "Missing",
                    isGood: accessibilityChecker.isGranted
                )

                DiagnosticStatusBadge(
                    title: "Input Monitoring",
                    value: accessibilityChecker.isListenGranted ? "Granted" : "Missing",
                    isGood: accessibilityChecker.isListenGranted
                )

                DiagnosticStatusBadge(
                    title: "Event Tap",
                    value: eventTapManager.isRunning ? "Running" : "Stopped",
                    isGood: eventTapManager.isRunning
                )
            }

            if let lastTapError = eventTapManager.lastTapError, !lastTapError.isEmpty {
                Text(lastTapError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
            }

            DiagnosticRow(label: "Active App", value: activeAppMonitor.currentAppName.isEmpty ? "None" : activeAppMonitor.currentAppName)
            DiagnosticRow(label: "Bundle ID", value: activeAppMonitor.currentBundleID.isEmpty ? "None" : activeAppMonitor.currentBundleID)
            DiagnosticRow(label: "Active Profile", value: activeProfileName)
            DiagnosticRow(label: "Last Event", value: eventTapManager.lastObservedEvent)
            DiagnosticRow(label: "App Location", value: appBundlePath)
            DiagnosticRow(label: "Config File", value: configStore.configFileURL.path)

            Divider()

            // MARK: Button Capture Diagnostic
            VStack(alignment: .leading, spacing: 8) {
                Text("Button Capture Test")
                    .font(.subheadline.weight(.medium))

                Text("Captures ALL events for 15 seconds to identify what your mouse buttons generate.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    if eventTapManager.isCapturing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Capturing... press your mouse buttons now!")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.orange)

                        Button("Stop") {
                            eventTapManager.stopDiagnosticCapture()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            eventTapManager.startDiagnosticCapture()
                        } label: {
                            Label("Start Capture", systemImage: "record.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }

                if !eventTapManager.diagnosticCaptures.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(eventTapManager.diagnosticCaptures.suffix(30)) { evt in
                                Text(evt.summary)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(colorForEventType(evt.eventTypeName))
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Actions")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 10) {
                    Button {
                        accessibilityChecker.promptIfNeeded()
                        accessibilityChecker.refreshStatus()
                        if accessibilityChecker.canInterceptEvents {
                            eventTapManager.restart()
                        }
                    } label: {
                        Label("Re-check Permissions", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        eventTapManager.restart()
                    } label: {
                        Label("Restart Event Tap", systemImage: "bolt.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([configStore.configFileURL])
                    } label: {
                        Label("Reveal Config", systemImage: "doc")
                    }
                    .buttonStyle(.bordered)

                    if !accessibilityChecker.hasRequiredAccess {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        } label: {
                            Label("Open Privacy Settings", systemImage: "lock.shield")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func colorForEventType(_ name: String) -> Color {
        if name.contains("otherMouse") { return .green }
        if name.contains("rightMouse") { return .blue }
        if name.contains("leftMouse") { return .primary }
        if name.contains("key") { return .orange }
        if name.contains("scroll") { return .secondary }
        if name.contains("type(") { return .red }
        return .secondary
    }
}

private struct DiagnosticStatusBadge: View {
    let title: String
    let value: String
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Image(systemName: isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isGood ? .green : .red)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
