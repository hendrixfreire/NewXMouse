import SwiftUI
import AppKit
import Combine
import ServiceManagement
import os.log

private let log = OSLog(subsystem: "com.newxmouse.app", category: "AppDelegate")

@main
struct NewXMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty settings scene — we manage our own window
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate handles everything

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    let configStore = ConfigStore()
    let eventTapManager = EventTapManager()
    let activeAppMonitor = ActiveAppMonitor()
    let accessibilityChecker = AccessibilityChecker()

    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var enabledMenuItem: NSMenuItem!
    private var activeProfileMenuItem: NSMenuItem!
    private var permissionsMenuItem: NSMenuItem!
    private var userDisabledTap = false
    private var launchAtLoginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireEventTap()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "New X Mouse")
                ?? NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "New X Mouse")
        }

        menu = NSMenu()
        menu.delegate = self

        activeProfileMenuItem = NSMenuItem(title: "Active Profile: Default", action: nil, keyEquivalent: "")
        activeProfileMenuItem.isEnabled = false
        menu.addItem(activeProfileMenuItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Enable/Disable toggle
        enabledMenuItem = NSMenuItem(title: "Enable", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        updateEnabledMenuItem()
        menu.addItem(enabledMenuItem)

        // Launch at Login toggle
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginMenuItem()
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit New X Mouse", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.addItem(.separator())

        permissionsMenuItem = NSMenuItem(title: "", action: #selector(grantAccessibility), keyEquivalent: "")
        permissionsMenuItem.target = self
        menu.addItem(permissionsMenuItem)
        updatePermissionsMenuItem()

        statusItem.menu = menu

        activeAppMonitor.$currentBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                self?.updateActiveProfileMenuItem(bundleID: bundleID)
            }
            .store(in: &cancellables)

        // Update enabled state when tap starts/stops
        eventTapManager.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateEnabledMenuItem()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            accessibilityChecker.$isGranted,
            accessibilityChecker.$isListenGranted,
            accessibilityChecker.$isPostGranted
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updatePermissionsMenuItem()
                self?.syncEventTapWithPermissions()
            }
            .store(in: &cancellables)

        configStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateActiveProfileMenuItem(bundleID: self.activeAppMonitor.currentBundleID)
            }
            .store(in: &cancellables)

        updateActiveProfileMenuItem(bundleID: activeAppMonitor.currentBundleID)
    }

    private func updateEnabledMenuItem() {
        enabledMenuItem?.title = eventTapManager.isRunning ? "Disable" : "Enable"
        enabledMenuItem?.state = eventTapManager.isRunning ? .on : .off
    }

    private func updatePermissionsMenuItem() {
        guard let permissionsMenuItem else { return }

        if !accessibilityChecker.isGranted {
            permissionsMenuItem.title = "Grant Accessibility Access..."
            permissionsMenuItem.action = #selector(grantAccessibility)
            permissionsMenuItem.state = .off
            permissionsMenuItem.isEnabled = true
        } else if !accessibilityChecker.isListenGranted {
            permissionsMenuItem.title = "Grant Input Monitoring Access..."
            permissionsMenuItem.action = #selector(grantAccessibility)
            permissionsMenuItem.state = .off
            permissionsMenuItem.isEnabled = true
        } else {
            permissionsMenuItem.title = "All Permissions Granted"
            permissionsMenuItem.action = nil
            permissionsMenuItem.state = .on
            permissionsMenuItem.isEnabled = false
        }
    }

    private func updateActiveProfileMenuItem(bundleID: String) {
        let activeProfile = configStore.activeProfile(for: bundleID)
        let sourceName = activeAppMonitor.currentAppName.isEmpty ? "No Active App" : activeAppMonitor.currentAppName
        let layerInfo = activeProfile.layers.count > 1 ? " [\(activeProfile.activeLayer?.name ?? "?")]" : ""
        activeProfileMenuItem?.title = "Active Profile: \(activeProfile.displayName)\(layerInfo) (\(sourceName))"
    }

    // MARK: - Event Tap

    private func wireEventTap() {
        eventTapManager.configStore = configStore
        eventTapManager.activeAppMonitor = activeAppMonitor

        accessibilityChecker.refreshStatus()

        os_log("=== STARTUP DIAGNOSTICS ===", log: log, type: .info)
        os_log("  AXIsProcessTrusted (Accessibility): %{public}d", log: log, type: .info, accessibilityChecker.isGranted)
        os_log("  CGPreflightListenEventAccess (Input Monitoring): %{public}d", log: log, type: .info, accessibilityChecker.isListenGranted)
        os_log("  CGPreflightPostEventAccess (Post Events): %{public}d", log: log, type: .info, accessibilityChecker.isPostGranted)
        os_log("  canInterceptEvents: %{public}d", log: log, type: .info, accessibilityChecker.canInterceptEvents)
        os_log("  hasRequiredAccess: %{public}d", log: log, type: .info, accessibilityChecker.hasRequiredAccess)
        os_log("  Default profile mappings count: %{public}d", log: log, type: .info, configStore.defaultProfile.activeLayer?.mappings.count ?? 0)
        if let layer = configStore.defaultProfile.activeLayer {
            for (button, entry) in layer.mappings {
                os_log("    Button %{public}d (%{public}s) → %{public}s", log: log, type: .info, button.rawValue, button.displayName, entry.action.displayName)
            }
        }
        os_log("  App profiles count: %{public}d", log: log, type: .info, configStore.appProfiles.count)
        os_log("============================", log: log, type: .info)

        syncEventTapWithPermissions()

        if !accessibilityChecker.hasRequiredAccess {
            os_log("Missing required access — prompting user", log: log, type: .info)
            accessibilityChecker.promptIfNeeded()
        }

        // Log tap state after attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.eventTapManager.logDiagnostics()
        }
    }

    private func syncEventTapWithPermissions() {
        guard !userDisabledTap else { return }

        if accessibilityChecker.canInterceptEvents {
            if !eventTapManager.isRunning {
                eventTapManager.start()
            }
        } else if eventTapManager.isRunning {
            eventTapManager.stop()
        }
    }

    // MARK: - Actions

    @objc private func grantAccessibility() {
        accessibilityChecker.promptIfNeeded()
    }

    @objc private func toggleEnabled() {
        if eventTapManager.isRunning {
            userDisabledTap = true
            eventTapManager.stop()
        } else {
            userDisabledTap = false
            // Must have permissions before starting the tap
            if accessibilityChecker.canInterceptEvents {
                eventTapManager.start()
            } else {
                accessibilityChecker.promptIfNeeded()
            }
        }
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            os_log("Failed to toggle launch at login: %{public}s", log: log, type: .error, error.localizedDescription)
        }
        updateLaunchAtLoginMenuItem()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(configStore)
            .environmentObject(eventTapManager)
            .environmentObject(activeAppMonitor)
            .environmentObject(accessibilityChecker)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "New X Mouse Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        accessibilityChecker.refreshStatus()
        syncEventTapWithPermissions()
        updateEnabledMenuItem()
        updatePermissionsMenuItem()
        updateActiveProfileMenuItem(bundleID: activeAppMonitor.currentBundleID)
        updateLaunchAtLoginMenuItem()
    }
}
