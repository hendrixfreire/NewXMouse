import Foundation
import Combine
import os.log

private let configLog = OSLog(subsystem: "com.newxmouse.app", category: "ConfigStore")

final class ConfigStore: ObservableObject {
    @Published var defaultProfile: AppProfile
    @Published var appProfiles: [AppProfile]
    @Published private(set) var lastManualSave: SaveFeedback?
    @Published var lastSaveError: String?

    let undoManager = UndoManager()
    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    private let configURL: URL
    private var saveTimer: Timer?
    private let saveDebounceInterval: TimeInterval = 0.5

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("NewXMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configURL = appDir.appendingPathComponent("config.json")

        defaultProfile = AppProfile(bundleID: ProfileConstants.defaultBundleID, displayName: "Default", mappings: [:])
        appProfiles = []

        load()
    }

    // MARK: - Undo Helpers

    private typealias Snapshot = (defaultProfile: AppProfile, appProfiles: [AppProfile])

    private func snapshot() -> Snapshot {
        (defaultProfile, appProfiles)
    }

    private func restore(snapshot: Snapshot) {
        defaultProfile = snapshot.defaultProfile
        appProfiles = snapshot.appProfiles
        scheduleSave()
    }

    /// Wraps a mutation with undo support using state snapshots.
    private func withUndo(_ label: String, _ mutation: () -> Void) {
        let before = snapshot()
        mutation()
        let after = snapshot()
        undoManager.registerUndo(withTarget: self) { store in
            let currentSnap = store.snapshot()
            store.restore(snapshot: before)
            store.undoManager.registerUndo(withTarget: store) { s in
                s.restore(snapshot: after)
            }
        }
        undoManager.setActionName(label)
    }

    func undo() { undoManager.undo() }
    func redo() { undoManager.redo() }

    // MARK: - Lookup

    func action(for button: MouseButton, appBundleID: String) -> Action? {
        // App-specific mapping first
        if let profile = appProfiles.first(where: { $0.bundleID == appBundleID }),
           let entry = profile.activeLayer?.mappings[button] {
            if !entry.enabled || entry.action == .passthrough { return nil }
            return entry.action
        }
        // Fall back to default profile
        if let entry = defaultProfile.activeLayer?.mappings[button] {
            if !entry.enabled || entry.action == .passthrough { return nil }
            return entry.action
        }
        return nil
    }

    func activeProfile(for appBundleID: String) -> AppProfile {
        if let profile = appProfiles.first(where: { $0.bundleID == appBundleID }) {
            return profile
        }
        return defaultProfile
    }

    func displayName(for bundleID: String) -> String {
        if bundleID == ProfileConstants.defaultBundleID {
            return defaultProfile.displayName
        }
        return appProfiles.first(where: { $0.bundleID == bundleID })?.displayName ?? bundleID
    }

    var configFileURL: URL { configURL }

    // MARK: - Profile Management

    func addProfile(_ profile: AppProfile) {
        withUndo("Add Profile") {
            if let index = appProfiles.firstIndex(where: { $0.bundleID == profile.bundleID }) {
                appProfiles[index] = profile
            } else {
                appProfiles.append(profile)
            }
            scheduleSave()
        }
    }

    func removeProfile(bundleID: String) {
        withUndo("Remove Profile") {
            appProfiles.removeAll { $0.bundleID == bundleID }
            scheduleSave()
        }
    }

    // MARK: - Helper: Mutate active layer

    private func activeLayerIndex(in profile: AppProfile) -> Int? {
        profile.layers.firstIndex(where: { $0.id == profile.activeLayerID })
    }

    func clearMappings(for bundleID: String) {
        withUndo("Clear Mappings") {
            if bundleID == ProfileConstants.defaultBundleID {
                if let idx = activeLayerIndex(in: defaultProfile) {
                    defaultProfile.layers[idx].mappings.removeAll()
                }
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }),
                      let layerIdx = activeLayerIndex(in: appProfiles[index]) {
                appProfiles[index].layers[layerIdx].mappings.removeAll()
            }
            scheduleSave()
        }
    }

    func setMapping(button: MouseButton, action: Action, for bundleID: String) {
        withUndo("Change Mapping") {
            if bundleID == ProfileConstants.defaultBundleID {
                if let idx = activeLayerIndex(in: defaultProfile) {
                    if let existing = defaultProfile.layers[idx].mappings[button] {
                        defaultProfile.layers[idx].mappings[button] = MappingEntry(action: action, enabled: existing.enabled)
                    } else {
                        defaultProfile.layers[idx].mappings[button] = MappingEntry(action: action)
                    }
                }
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }),
                      let layerIdx = activeLayerIndex(in: appProfiles[index]) {
                if let existing = appProfiles[index].layers[layerIdx].mappings[button] {
                    appProfiles[index].layers[layerIdx].mappings[button] = MappingEntry(action: action, enabled: existing.enabled)
                } else {
                    appProfiles[index].layers[layerIdx].mappings[button] = MappingEntry(action: action)
                }
            }
            scheduleSave()
        }
    }

    func setMappingEnabled(button: MouseButton, enabled: Bool, for bundleID: String) {
        withUndo("Toggle Mapping") {
            if bundleID == ProfileConstants.defaultBundleID {
                if let idx = activeLayerIndex(in: defaultProfile) {
                    if defaultProfile.layers[idx].mappings[button] == nil {
                        defaultProfile.layers[idx].mappings[button] = MappingEntry(action: .passthrough, enabled: enabled)
                    } else {
                        defaultProfile.layers[idx].mappings[button]?.enabled = enabled
                    }
                }
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }),
                      let layerIdx = activeLayerIndex(in: appProfiles[index]) {
                if appProfiles[index].layers[layerIdx].mappings[button] == nil {
                    appProfiles[index].layers[layerIdx].mappings[button] = MappingEntry(action: .passthrough, enabled: enabled)
                } else {
                    appProfiles[index].layers[layerIdx].mappings[button]?.enabled = enabled
                }
            }
            scheduleSave()
        }
    }

    // MARK: - Layer Management

    func addLayer(name: String, for bundleID: String) {
        withUndo("Add Layer") {
            if bundleID == ProfileConstants.defaultBundleID {
                defaultProfile.addLayer(name: name)
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                appProfiles[index].addLayer(name: name)
            }
            scheduleSave()
        }
    }

    func removeLayer(id: UUID, for bundleID: String) {
        withUndo("Remove Layer") {
            if bundleID == ProfileConstants.defaultBundleID {
                defaultProfile.removeLayer(id: id)
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                appProfiles[index].removeLayer(id: id)
            }
            scheduleSave()
        }
    }

    func switchToLayer(id: UUID, for bundleID: String) {
        withUndo("Switch Layer") {
            if bundleID == ProfileConstants.defaultBundleID {
                defaultProfile.switchToLayer(id: id)
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                appProfiles[index].switchToLayer(id: id)
            }
            scheduleSave()
        }
    }

    func renameLayer(id: UUID, name: String, for bundleID: String) {
        withUndo("Rename Layer") {
            if bundleID == ProfileConstants.defaultBundleID {
                defaultProfile.renameLayer(id: id, name: name)
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                appProfiles[index].renameLayer(id: id, name: name)
            }
            scheduleSave()
        }
    }

    func duplicateLayer(id: UUID, for bundleID: String) {
        withUndo("Duplicate Layer") {
            if bundleID == ProfileConstants.defaultBundleID {
                guard let source = defaultProfile.layers.first(where: { $0.id == id }) else { return }
                var copy = source
                copy.id = UUID()
                copy.name = "\(source.name) Copy"
                copy.isDefault = false
                defaultProfile.layers.append(copy)
                defaultProfile.switchToLayer(id: copy.id)
            } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                guard let source = appProfiles[index].layers.first(where: { $0.id == id }) else { return }
                var copy = source
                copy.id = UUID()
                copy.name = "\(source.name) Copy"
                copy.isDefault = false
                appProfiles[index].layers.append(copy)
                appProfiles[index].switchToLayer(id: copy.id)
            }
            scheduleSave()
        }
    }

    // MARK: - Import / Export (Full Config)

    func exportConfig(to url: URL) -> Bool {
        let config = SavedConfig(defaultProfile: defaultProfile, appProfiles: appProfiles)
        do {
            let data = try JSONEncoder().encode(config)
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try prettyData.write(to: url, options: .atomic)
            os_log("Config exported to %{public}s", log: configLog, type: .info, url.path)
            return true
        } catch {
            os_log("Failed to export config: %{public}s", log: configLog, type: .error, error.localizedDescription)
            lastSaveError = "Export failed: \(error.localizedDescription)"
            return false
        }
    }

    func importConfig(from url: URL) -> Bool {
        withUndo("Import Configuration") {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(SavedConfig.self, from: data)
                defaultProfile = config.defaultProfile
                appProfiles = config.appProfiles
                saveImmediately()
                os_log("Config imported from %{public}s", log: configLog, type: .info, url.path)
            } catch {
                os_log("Failed to import config: %{public}s", log: configLog, type: .error, error.localizedDescription)
                lastSaveError = "Import failed: \(error.localizedDescription)"
            }
        }
        return lastSaveError == nil
    }

    // MARK: - Duplicate (preserves all layers)

    func duplicateProfile(bundleID: String) {
        withUndo("Duplicate Profile") {
            guard bundleID != ProfileConstants.defaultBundleID,
                  let source = appProfiles.first(where: { $0.bundleID == bundleID }) else { return }

            // Deep-copy all layers, not just the active one
            var copiedLayers = source.layers.map { layer -> Layer in
                var copy = layer
                copy.id = UUID()
                return copy
            }
            // Reset the default layer flag on copies — only one default per profile
            for i in copiedLayers.indices {
                copiedLayers[i].isDefault = (i == 0)
            }

            let copy = AppProfile(
                bundleID: source.bundleID + ".copy",
                displayName: source.displayName + " Copy",
                layers: copiedLayers
            )
            appProfiles.append(copy)
            scheduleSave()
        }
    }

    // MARK: - Import / Export (Individual Profile)

    func exportProfile(bundleID: String, to url: URL) -> Bool {
        let profile: AppProfile
        if bundleID == ProfileConstants.defaultBundleID {
            profile = defaultProfile
        } else {
            guard let p = appProfiles.first(where: { $0.bundleID == bundleID }) else { return false }
            profile = p
        }
        do {
            let data = try JSONEncoder().encode(profile)
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try prettyData.write(to: url, options: .atomic)
            os_log("Profile exported to %{public}s", log: configLog, type: .info, url.path)
            return true
        } catch {
            os_log("Failed to export profile: %{public}s", log: configLog, type: .error, error.localizedDescription)
            lastSaveError = "Profile export failed: \(error.localizedDescription)"
            return false
        }
    }

    func importProfile(from url: URL) -> Bool {
        withUndo("Import Profile") {
            do {
                let data = try Data(contentsOf: url)
                let profile = try JSONDecoder().decode(AppProfile.self, from: data)
                addProfile(profile)
                os_log("Profile imported from %{public}s", log: configLog, type: .info, url.path)
            } catch {
                os_log("Failed to import profile: %{public}s", log: configLog, type: .error, error.localizedDescription)
                lastSaveError = "Profile import failed: \(error.localizedDescription)"
            }
        }
        return lastSaveError == nil
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        do {
            var data = try Data(contentsOf: configURL)
            // Migrate legacy config: Action enum case "none" → "passthrough"
            // Use JSON-aware replacement instead of fragile string substitution
            if var jsonString = String(data: data, encoding: .utf8),
               jsonString.contains("\"none\"") {
                // Replace the specific pattern: "none":{} (legacy Action.none case)
                jsonString = jsonString.replacingOccurrences(
                    of: "\"none\"\\s*:\\s*\\{\\}",
                    with: "\"passthrough\":{}",
                    options: .regularExpression
                )
                if let migratedData = jsonString.data(using: .utf8) {
                    data = migratedData
                    try? data.write(to: configURL, options: .atomic)
                }
            }
            let config = try JSONDecoder().decode(SavedConfig.self, from: data)
            defaultProfile = config.defaultProfile
            appProfiles = config.appProfiles
        } catch {
            os_log("Failed to load config: %{public}s", log: configLog, type: .error, error.localizedDescription)
        }
    }

    /// Debounced save — coalesces rapid edits into a single write.
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
            self?.saveImmediately()
        }
    }

    /// Immediate save — used for explicit user actions (import, manual save).
    @discardableResult
    func save(showConfirmation: Bool = false) -> Bool {
        // If called with showConfirmation, save immediately (user tapped Save)
        if showConfirmation {
            return saveImmediately(showConfirmation: true)
        }
        // Otherwise debounce
        scheduleSave()
        return true
    }

    @discardableResult
    private func saveImmediately(showConfirmation: Bool = false) -> Bool {
        let config = SavedConfig(defaultProfile: defaultProfile, appProfiles: appProfiles)
        do {
            let data = try JSONEncoder().encode(config)
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try prettyData.write(to: configURL, options: .atomic)
            if showConfirmation {
                lastManualSave = SaveFeedback(date: Date(), url: configURL)
            }
            return true
        } catch {
            let msg = "Failed to save config: \(error.localizedDescription)"
            os_log("%{public}s", log: configLog, type: .error, msg)
            lastSaveError = msg
            return false
        }
    }
}

private struct SavedConfig: Codable {
    var defaultProfile: AppProfile
    var appProfiles: [AppProfile]
}

struct SaveFeedback: Equatable {
    let date: Date
    let url: URL
}
