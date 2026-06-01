import Foundation
import ApplicationServices
import Combine

final class AccessibilityChecker: ObservableObject {
    @Published var isGranted: Bool = false
    @Published var isListenGranted: Bool = false
    @Published var isPostGranted: Bool = false

    private var timer: Timer?
    /// Tracks whether we've already requested Listen/Post access this session
    /// to avoid repeatedly showing the system prompt dialog.
    private var hasRequestedListenAccess = false

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        isGranted = AXIsProcessTrusted()
        if #available(macOS 10.15, *) {
            isListenGranted = CGPreflightListenEventAccess()
            isPostGranted = CGPreflightPostEventAccess()
        } else {
            isListenGranted = isGranted
            isPostGranted = isGranted
        }
    }

    func promptIfNeeded() {
        refreshStatus()

        if !isGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            isGranted = AXIsProcessTrustedWithOptions(options)
        }

        // Only request Listen/Post access ONCE per session —
        // CGRequestListenEventAccess() shows a system dialog every time it's called,
        // which is extremely annoying if called repeatedly.
        if #available(macOS 10.15, *) {
            if !isListenGranted && !hasRequestedListenAccess {
                hasRequestedListenAccess = true
                _ = CGRequestListenEventAccess()
            }
        }

        refreshStatus()

        if !hasRequiredAccess {
            startPolling()
        }
    }

    var canInterceptEvents: Bool {
        isGranted && isListenGranted
    }

    var hasRequiredAccess: Bool {
        isGranted && isListenGranted
    }

    func startPolling() {
        guard timer == nil else { return } // Don't stack timers
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.refreshStatus()
                if self.hasRequiredAccess {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
