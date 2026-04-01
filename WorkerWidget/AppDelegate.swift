import Cocoa
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    // MARK: - Sparkle Gentle Reminders

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate || !state.userInitiated {
            // Show a badge on the menu bar icon when an update is available
            if let button = statusBarItem?.button {
                button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Update available")
                button.image?.size = NSSize(width: 18, height: 18)
                button.image?.isTemplate = true
            }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // Restore normal icon after user sees the update
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "WorkerWidget")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestNotificationPermission()

        Task {
            await DataManager.shared.refreshBuildHistory(force: true)
            DataManager.shared.setAutoRefresh(enabled: true)
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: BuildHistoryView())
        self.popover = popover

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self

            if let image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "WorkerWidget") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "WW"
            }
        }
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
