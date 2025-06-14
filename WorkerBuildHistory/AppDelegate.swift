import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Worker Build History")
            button.title = "Worker Build History"
        }
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        print("Menu item clicked")
        // We'll implement the window handling logic here
        // This will include:
        // 1. Creating a window if it doesn't exist
        // 2. Positioning it under the menu bar icon
        // 3. Showing/hiding it based on current state
    }
} 