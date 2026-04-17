import Cocoa
import Combine
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    private var statusBarMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    private var hasPendingUpdateBadge = false
    private var currentMenuBarState: DataManager.MenuBarState = .normal

    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    // MARK: - Sparkle Gentle Reminders

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate || !state.userInitiated {
            hasPendingUpdateBadge = true
            updateStatusBarAppearance()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        hasPendingUpdateBadge = false
        updateStatusBarAppearance()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestNotificationPermission()
        DiagnosticsManager.shared.log(.info, category: "app", message: "Application did finish launching")

        // Materialize the Sparkle controller now so background checks run
        // and `canCheckForUpdates` has settled to true by the time Settings
        // first opens.
        _ = updaterController

        // Only fire the launch refresh / auto-refresh timer once the user
        // has saved a key. Otherwise every refresh would cascade into a
        // keychain read that macOS may prompt on. The first save in
        // SettingsView starts auto-refresh itself.
        if KeychainManager.isApiKeyConfigured {
            Task {
                await DataManager.shared.refreshBuildHistory(force: true)
                DataManager.shared.setAutoRefresh(enabled: DataManager.shared.autoRefreshEnabled)
            }
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self

            updateStatusBarAppearance()
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WorkerWidget", action: #selector(quitApp), keyEquivalent: "q"))
        statusBarItem?.menu = nil
        self.statusBarMenu = menu

        DataManager.shared.$menuBarState
            .receive(on: RunLoop.main)
            .sink { [weak self] menuBarState in
                self?.currentMenuBarState = menuBarState
                self?.updateStatusBarAppearance()
            }
            .store(in: &cancellables)
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Show context menu on right-click
            if let menu = statusBarMenu {
                statusBarItem?.menu = menu
                statusBarItem?.button?.performClick(nil)
                statusBarItem?.menu = nil
            }
            return
        }

        guard let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateStatusBarAppearance() {
        guard let button = statusBarItem?.button else { return }

        let imageName: String
        let accessibilityDescription: String
        let tintColor: NSColor?

        switch currentMenuBarState {
        case .failed:
            imageName = "cloud.fill"
            accessibilityDescription = "Recent build failed"
            tintColor = .systemRed
        case .inProgress:
            imageName = "cloud.fill"
            accessibilityDescription = "Build in progress"
            tintColor = .systemBlue
        case .normal:
            imageName = hasPendingUpdateBadge ? "cloud.fill" : "cloud"
            accessibilityDescription = hasPendingUpdateBadge ? "Update available" : "WorkerWidget"
            tintColor = nil
        }

        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: accessibilityDescription) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            button.image = image
            button.contentTintColor = tintColor
        } else {
            button.title = "WW"
        }
    }
}
