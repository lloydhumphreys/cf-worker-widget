import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var window: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Worker Build History")
            button.title = "Worker Build History"
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
        if window != nil {
            return window.unsafelyUnwrapped
        }
        let contentView = BuildHistoryView()
        window = NSWindow(
            contentRect: size,
            styleMask: [.borderless],
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
        return window.unsafelyUnwrapped
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
        print("Menu item clicked")
        
        // Set the window dimensions - larger to accommodate settings sheet
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 500
        
        // Calculate window position
        let mouseLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let windowX = mouseLocation.x - windowWidth / 2
        let windowY = screenHeight - windowHeight - (getMenuBarHeight() ?? 0)
        
        // Construct and show/hide the window
        window = getOrBuildWindow(size: NSRect(
            x: windowX,
            y: windowY,
            width: windowWidth,
            height: windowHeight
        ))
        
        toggleWindowVisibility(location: NSPoint(x: windowX, y: windowY))
    }
} 