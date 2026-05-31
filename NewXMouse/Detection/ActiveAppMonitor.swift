import Foundation
import AppKit
import Combine
import os

final class ActiveAppMonitor: ObservableObject {
    @Published var currentBundleID: String = ""
    @Published var currentAppName: String = ""

    private let lock = OSAllocatedUnfairLock(initialState: "")
    private var cancellable: AnyCancellable?

    init() {
        if let app = NSWorkspace.shared.frontmostApplication {
            let bundleID = app.bundleIdentifier ?? ""
            currentBundleID = bundleID
            currentAppName = app.localizedName ?? ""
            lock.withLock { $0 = bundleID }
        }

        cancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                guard let self else { return }
                let bundleID = app.bundleIdentifier ?? ""
                self.currentBundleID = bundleID
                self.currentAppName = app.localizedName ?? ""
                self.lock.withLock { $0 = bundleID }
            }
    }

    /// Thread-safe access for the event tap callback
    var threadSafeBundleID: String {
        lock.withLock { $0 }
    }
}
