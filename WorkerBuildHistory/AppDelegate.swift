import Cocoa
import SwiftUI

class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var window: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestNotificationPermission()

        // Fetch build history immediately on launch
        Task {
            await DataManager.shared.refreshBuildHistory(force: true)
            DataManager.shared.setAutoRefresh(enabled: true)
        }

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            
            if let image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Worker Build History") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "WBH"
            }
            
            statusBarItem?.isVisible = true
            button.appearsDisabled = false
        }
    }
    
    func getMenuBarHeight() -> CGFloat? {
        guard let desktopFrame = NSScreen.main?.visibleFrame else {
            return nil
        }    
        let screenFrame = NSScreen.main?.frame
        let menuBarHeight = screenFrame!.height - desktopFrame.height
        return menuBarHeight
    }
    
    @objc func getOrBuildWindow(size: NSRect) -> NSWindow {
        if let existingWindow = window {
            return existingWindow
        }
        let contentView = BuildHistoryView()
        window = BorderlessKeyWindow(
            contentRect: size,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false)
        window?.contentView = NSHostingView(rootView: contentView)
        window?.isReleasedWhenClosed = false
        window?.collectionBehavior = .moveToActiveSpace
        window?.level = .floating
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.cornerRadius = 12
        window?.contentView?.layer?.masksToBounds = true
        window?.minSize = NSSize(width: 400, height: 300)
        window?.maxSize = NSSize(width: 1000, height: 800)
        
        // Auto-hide when app loses focus
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        return window!
    }
    
    func toggleWindowVisibility(location: NSPoint) {
        if window == nil {
            return
        }
        if window!.isVisible {
            window?.orderOut(nil)
        } else {
            window?.setFrameOrigin(location)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        
        // Set the window dimensions - larger to accommodate settings sheet
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 500
        
        // Calculate window position with spacing from menu bar
        let mouseLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let menuBarSpacing: CGFloat = 8 // Add 8px spacing from menu bar
        let windowX = mouseLocation.x - windowWidth / 2
        let windowY = screenHeight - windowHeight - (getMenuBarHeight() ?? 0) - menuBarSpacing
        
        // Construct and show/hide the window
        window = getOrBuildWindow(size: NSRect(
            x: windowX,
            y: windowY,
            width: windowWidth,
            height: windowHeight
        ))
        
        toggleWindowVisibility(location: NSPoint(x: windowX, y: windowY))
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        // Hide window when app loses focus
        if window?.isVisible == true {
            window?.orderOut(nil)
        }
    }
} 
