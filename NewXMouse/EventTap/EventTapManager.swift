import Foundation
import CoreGraphics
import Combine
import os.log

private let log = OSLog(subsystem: "com.newxmouse.app", category: "EventTap")

final class EventTapManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastObservedEvent: String = "No events observed yet"
    @Published var lastObservedDate: Date?
    @Published var lastTapError: String?

    var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?

    // Shared context accessible from the C callback
    // Weak reference prevents dangling pointer if manager is deallocated
    private static weak var _shared: EventTapManager?
    static var shared: EventTapManager? { _shared }

    var configStore: ConfigStore?
    var activeAppMonitor: ActiveAppMonitor?

    func start() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }

        guard eventTap == nil else {
            os_log("start() called but tap already exists — skipping", log: log, type: .info)
            return
        }
        EventTapManager._shared = self
        lastTapError = nil

        NSLog("Creating event tap...")

        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        os_log("Event mask: %{public}llu (otherDown=%d otherUp=%d rightDown=%d rightUp=%d scrollWheel=%d)",
               log: log, type: .debug,
               eventMask,
               CGEventType.otherMouseDown.rawValue,
               CGEventType.otherMouseUp.rawValue,
               CGEventType.rightMouseDown.rawValue,
               CGEventType.rightMouseUp.rawValue,
               CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            let msg = "CGEvent.tapCreate returned nil — event tap NOT created. Check Accessibility + Input Monitoring."
            lastTapError = msg
            NSLog("ERROR: \(msg)")
            return
        }

        NSLog("CGEvent.tapCreate succeeded (CFMachPort obtained)")

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            lastTapError = "Failed to create run loop source from Mach port."
            os_log("CFMachPortCreateRunLoopSource failed", log: log, type: .error)
            CFMachPortInvalidate(tap)
            eventTap = nil
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let enabled = CGEvent.tapIsEnabled(tap: tap)
        NSLog("Event tap enabled = \(enabled)")

        if !enabled {
            lastTapError = "Event tap was created but could not be enabled."
            os_log("WARNING: tap exists but tapIsEnabled returned false", log: log, type: .error)
        }

        DispatchQueue.main.async {
            self.isRunning = true
        }

        startHealthCheck()
        NSLog("Event tap started and attached to main run loop.")
    }

    func stop() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }

        healthTimer?.invalidate()
        healthTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        EventTapManager._shared = nil

        DispatchQueue.main.async {
            self.isRunning = false
        }
        os_log("Event tap stopped.", log: log, type: .info)
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    func restart() {
        stop()
        start()
    }

    /// Periodically checks that the tap hasn't been silently disabled by the system.
    private func startHealthCheck() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            let enabled = CGEvent.tapIsEnabled(tap: tap)
            if !enabled {
                os_log("Health check: tap was disabled by system — re-enabling", log: log, type: .error)
                CGEvent.tapEnable(tap: tap, enable: true)
                let nowEnabled = CGEvent.tapIsEnabled(tap: tap)
                os_log("Health check: re-enable result = %{public}d", log: log, type: .info, nowEnabled)
            }
        }
    }

    func recordObservedEvent(button: MouseButton, type: CGEventType, bundleID: String, hadAction: Bool) {
        let eventLabel: String
        switch type {
        case .otherMouseDown, .rightMouseDown:
            eventLabel = "down"
        case .otherMouseUp, .rightMouseUp:
            eventLabel = "up"
        case .scrollWheel:
            eventLabel = "scroll"
        default:
            eventLabel = "\(type.rawValue)"
        }

        let appLabel = bundleID.isEmpty ? "unknown app" : bundleID
        let actionLabel = hadAction ? "matched action" : "no action"
        let summary = "\(button.displayName) \(eventLabel) in \(appLabel) (\(actionLabel))"

        DispatchQueue.main.async {
            self.lastObservedEvent = summary
            self.lastObservedDate = Date()
        }
    }

    func logDiagnostics() {
        os_log("=== EventTapManager Diagnostics ===", log: log, type: .info)
        os_log("  isRunning: %{public}d", log: log, type: .info, isRunning)
        os_log("  eventTap is nil: %{public}d", log: log, type: .info, eventTap == nil)
        os_log("  configStore is nil: %{public}d", log: log, type: .info, configStore == nil)
        os_log("  activeAppMonitor is nil: %{public}d", log: log, type: .info, activeAppMonitor == nil)
        os_log("  shared is nil: %{public}d", log: log, type: .info, EventTapManager.shared == nil)
        if let tap = eventTap {
            let enabled = CGEvent.tapIsEnabled(tap: tap)
            os_log("  tapIsEnabled: %{public}d", log: log, type: .info, enabled)
        }
        if let error = lastTapError {
            os_log("  lastTapError: %{public}s", log: log, type: .error, error)
        }
        os_log("===================================", log: log, type: .info)
    }

    // MARK: - Diagnostic Capture

    @Published var diagnosticCaptures: [DiagnosticEvent] = []
    @Published var isCapturing = false
    private var diagnosticTap: CFMachPort?
    private var diagnosticRunLoopSource: CFRunLoopSource?
    private var captureTimer: Timer?

    static var capturedEvents: [DiagnosticEvent] = []

    func startDiagnosticCapture(duration: TimeInterval = 15) {
        guard !isCapturing else { return }
        stopDiagnosticCapture()

        EventTapManager.capturedEvents = []
        diagnosticCaptures = []
        isCapturing = true

        os_log("Starting diagnostic capture (%.0f seconds, ALL event types)...", log: log, type: .info, duration)

        // Listen-only tap with ALL event types
        let allMask: CGEventMask = ~0

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: allMask,
            callback: diagnosticTapCallback,
            userInfo: nil
        ) else {
            os_log("Failed to create diagnostic tap", log: log, type: .error)
            isCapturing = false
            return
        }

        diagnosticTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            diagnosticTap = nil
            isCapturing = false
            return
        }

        diagnosticRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        os_log("Diagnostic tap created — press your mouse buttons now!", log: log, type: .info)

        captureTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopDiagnosticCapture()
        }
    }

    func stopDiagnosticCapture() {
        captureTimer?.invalidate()
        captureTimer = nil

        if let tap = diagnosticTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = diagnosticRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        diagnosticTap = nil
        diagnosticRunLoopSource = nil

        DispatchQueue.main.async {
            self.diagnosticCaptures = EventTapManager.capturedEvents
            self.isCapturing = false
        }
        os_log("Diagnostic capture stopped. Captured %{public}d events.", log: log, type: .info, EventTapManager.capturedEvents.count)
    }

    deinit {
        stop()
    }
}

// MARK: - Diagnostic Event

struct DiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let eventType: Int
    let eventTypeName: String
    let buttonNumber: Int64
    let keyCode: Int64
    let flags: UInt64
    let subtype: Int64
    let summary: String

    static func eventTypeName(_ rawType: CGEventType) -> String {
        switch rawType {
        case .null: return "null"
        case .leftMouseDown: return "leftMouseDown"
        case .leftMouseUp: return "leftMouseUp"
        case .rightMouseDown: return "rightMouseDown"
        case .rightMouseUp: return "rightMouseUp"
        case .mouseMoved: return "mouseMoved"
        case .leftMouseDragged: return "leftMouseDragged"
        case .rightMouseDragged: return "rightMouseDragged"
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        case .flagsChanged: return "flagsChanged"
        case .scrollWheel: return "scrollWheel"
        case .tabletPointer: return "tabletPointer"
        case .tabletProximity: return "tabletProximity"
        case .otherMouseDown: return "otherMouseDown"
        case .otherMouseUp: return "otherMouseUp"
        case .otherMouseDragged: return "otherMouseDragged"
        case .tapDisabledByTimeout: return "tapDisabledByTimeout"
        case .tapDisabledByUserInput: return "tapDisabledByUserInput"
        default: return "type(\(rawType.rawValue))"
        }
    }
}

// MARK: - Diagnostic Tap Callback

private let diagLog = OSLog(subsystem: "com.newxmouse.app", category: "DiagCapture")

private func diagnosticTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Skip noisy events
    if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
        return Unmanaged.passUnretained(event)
    }

    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags.rawValue
    // NX subtype — field 110 = eventSourceSubType
    let subtype = event.getIntegerValueField(CGEventField(rawValue: 110)!)

    let typeName = DiagnosticEvent.eventTypeName(type)

    var summary: String
    switch type {
    case .otherMouseDown, .otherMouseUp, .rightMouseDown, .rightMouseUp, .leftMouseDown, .leftMouseUp:
        summary = "\(typeName) button=\(buttonNumber)"
    case .keyDown, .keyUp:
        summary = "\(typeName) keyCode=\(keyCode) flags=0x\(String(flags, radix: 16))"
    case .scrollWheel:
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        summary = "\(typeName) deltaY=\(deltaY) deltaX=\(deltaX)"
    case .flagsChanged:
        summary = "\(typeName) flags=0x\(String(flags, radix: 16))"
    default:
        summary = "\(typeName) (raw=\(type.rawValue)) subtype=\(subtype) button=\(buttonNumber) key=\(keyCode)"
    }

    os_log("DIAG: %{public}s", log: diagLog, type: .info, summary)

    let diagEvent = DiagnosticEvent(
        timestamp: Date(),
        eventType: Int(type.rawValue),
        eventTypeName: typeName,
        buttonNumber: buttonNumber,
        keyCode: keyCode,
        flags: flags,
        subtype: subtype,
        summary: summary
    )

    EventTapManager.capturedEvents.append(diagEvent)

    return Unmanaged.passUnretained(event)
}

// MARK: - C Callback

private let callbackLog = OSLog(subsystem: "com.newxmouse.app", category: "Callback")

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Pass through our own synthetic events
    if event.getIntegerValueField(.eventSourceUserData) == Action.syntheticEventMarker {
        return Unmanaged.passUnretained(event)
    }

    // Re-enable tap if system disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        os_log("Tap disabled by system (type=%{public}d) — re-enabling", log: callbackLog, type: .error, type.rawValue)
        if let manager = EventTapManager.shared, let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard let manager = EventTapManager.shared,
          let config = manager.configStore,
          let appMonitor = manager.activeAppMonitor else {
        os_log("Callback fired but manager/config/appMonitor is nil", log: callbackLog, type: .error)
        return Unmanaged.passUnretained(event)
    }

    // MARK: Handle scroll wheel events
    if type == .scrollWheel {
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)

        // Determine scroll direction — use deltaY for vertical, deltaX for horizontal
        let mouseButton: MouseButton?
        let scrollDelta: Int64

        if deltaY != 0 {
            mouseButton = deltaY > 0 ? .scrollUp : .scrollDown
            scrollDelta = abs(deltaY)
        } else if deltaX != 0 {
            mouseButton = deltaX > 0 ? .scrollRight : .scrollLeft
            scrollDelta = abs(deltaX)
        } else {
            return Unmanaged.passUnretained(event)
        }

        guard let button = mouseButton else {
            return Unmanaged.passUnretained(event)
        }

        let currentApp = appMonitor.threadSafeBundleID
        let resolvedAction = config.action(for: button, appBundleID: currentApp)

        manager.recordObservedEvent(button: button, type: .scrollWheel, bundleID: currentApp, hadAction: resolvedAction != nil)

        if let action = resolvedAction {
            os_log("INTERCEPT: %{public}s scroll → %{public}s (app: %{public}s, delta: %{public}lld)",
                   log: callbackLog, type: .info,
                   button.displayName,
                   action.displayName,
                   currentApp,
                   scrollDelta)

            // Execute the action once per scroll tick
            for _ in 0..<scrollDelta {
                action.execute(isDown: true)
            }
            return nil // Suppress original scroll event
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: Handle mouse button events (existing logic)
    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    guard let mouseButton = MouseButton(rawValue: Int(buttonNumber)) else {
        os_log("Unknown button number: %{public}lld — passing through", log: callbackLog, type: .debug, buttonNumber)
        return Unmanaged.passUnretained(event)
    }

    let isDown = (type == .otherMouseDown || type == .rightMouseDown)
    let currentApp = appMonitor.threadSafeBundleID

    let resolvedAction = config.action(for: mouseButton, appBundleID: currentApp)
    manager.recordObservedEvent(button: mouseButton, type: type, bundleID: currentApp, hadAction: resolvedAction != nil)

    if let action = resolvedAction {
        os_log("INTERCEPT: %{public}s %{public}s → %{public}s (app: %{public}s)",
               log: callbackLog, type: .info,
               mouseButton.displayName,
               isDown ? "down" : "up",
               action.displayName,
               currentApp)
        if action != .disabled {
            action.execute(isDown: isDown)
        }
        // Both .disabled and other actions suppress the original event
        return nil
    }

    os_log("PASS: %{public}s %{public}s — no mapping (app: %{public}s)",
           log: callbackLog, type: .debug,
           mouseButton.displayName,
           isDown ? "down" : "up",
           currentApp)

    return Unmanaged.passUnretained(event)
}
