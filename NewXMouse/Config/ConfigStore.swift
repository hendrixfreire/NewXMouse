import Foundation
import Combine
import os.log

private let configLog = OSLog(subsystem: "com.newxmouse.app", category: "ConfigStore")

final class ConfigStore: ObservableObject {
    @Published var defaultProfile: AppProfile
    @Published var appProfiles: [AppProfile]
    @Published private(set) var lastManualSave: SaveFeedback?
    @Published var lastSaveError: String?

    private let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("NewXMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configURL = appDir.appendingPathComponent("config.json")

        defaultProfile = AppProfile(bundleID: ProfileConstants.defaultBundleID, displayName: "Default", mappings: [:])
        appProfiles = []

        load()
    }

    // MARK: - Lookup

    func action(for button: MouseButton, appBundleID: String) -> Action? {
        // App-specific mapping first
        if let profile = appProfiles.first(where: { $0.bundleID == appBundleID }),
           let action = profile.mappings[button], action != .none {
            return action
        }
        // Fall back to default profile
        if let action = defaultProfile.mappings[button], action != .none {
            return action
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

    var configFileURL: URL {
        configURL
    }

    // MARK: - Profile Management

    func addProfile(_ profile: AppProfile) {
        if let index = appProfiles.firstIndex(where: { $0.bundleID == profile.bundleID }) {
            appProfiles[index] = profile
        } else {
            appProfiles.append(profile)
        }
        save()
    }

    func removeProfile(bundleID: String) {
        appProfiles.removeAll { $0.bundleID == bundleID }
        save()
    }

    func clearMappings(for bundleID: String) {
        if bundleID == ProfileConstants.defaultBundleID {
            defaultProfile.mappings.removeAll()
        } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
            appProfiles[index].mappings.removeAll()
        }
        save()
    }

    func setMapping(button: MouseButton, action: Action, for bundleID: String) {
        if bundleID == ProfileConstants.defaultBundleID {
            defaultProfile.mappings[button] = action
        } else if let index = appProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
            appProfiles[index].mappings[button] = action
        }
        save()
    }

    // MARK: - Import / Export

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
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(SavedConfig.self, from: data)
            defaultProfile = config.defaultProfile
            appProfiles = config.appProfiles
            save()
            os_log("Config imported from %{public}s", log: configLog, type: .info, url.path)
            return true
        } catch {
            os_log("Failed to import config: %{public}s", log: configLog, type: .error, error.localizedDescription)
            lastSaveError = "Import failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Duplicate

    func duplicateProfile(bundleID: String) {
        guard bundleID != ProfileConstants.defaultBundleID,
              let source = appProfiles.first(where: { $0.bundleID == bundleID }) else { return }
        let copy = AppProfile(
            bundleID: source.bundleID + ".copy",
            displayName: source.displayName + " Copy",
            mappings: source.mappings
        )
        appProfiles.append(copy)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(SavedConfig.self, from: data)
            defaultProfile = config.defaultProfile
            appProfiles = config.appProfiles
        } catch {
            os_log("Failed to load config: %{public}s", log: configLog, type: .error, error.localizedDescription)
        }
    }

    @discardableResult
    func save(showConfirmation: Bool = false) -> Bool {
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
