import Foundation
import ApplicationServices
import Combine

final class AccessibilityChecker: ObservableObject {
    @Published var isGranted: Bool = false
    @Published var isListenGranted: Bool = false
    @Published var isPostGranted: Bool = false

    private var timer: Timer?

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

        if #available(macOS 10.15, *) {
            if !isListenGranted {
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
        timer?.invalidate()
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
