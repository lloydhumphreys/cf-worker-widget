import Cocoa
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestNotificationPermission()

        Task {
            await DataManager.shared.refreshBuildHistory(force: true)
            DataManager.shared.setAutoRefresh(enabled: true)
        }

        // Set up the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: BuildHistoryView())
        self.popover = popover

        // Set up the status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self

            if let image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "WorkerWidget") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "WBH"
            }
        }
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // Ensure the popover's window can receive key events
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
