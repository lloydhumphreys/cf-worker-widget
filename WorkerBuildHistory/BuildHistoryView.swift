import SwiftUI

struct BuildHistoryView: View {
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            List {
                // Placeholder items until we wire up the Cloudflare data
                ForEach(0..<5) { index in
                    BuildHistoryRow(
                        buildNumber: "Build #\(index + 1)",
                        status: "Success",
                        timestamp: "Just now"
                    )
                }
            }
        }
        .frame(width: 300, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
        .onChange(of: showingSettings) { newValue in
            if newValue {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                    styleMask: [.titled, .closable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Settings"
                window.center()
                window.contentView = NSHostingView(rootView: SettingsView())
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                
                // Reset the state when the window is closed
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    showingSettings = false
                }
            }
        }
    }
}

struct BuildHistoryRow: View {
    let buildNumber: String
    let status: String
    let timestamp: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(buildNumber)
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            Text(timestamp)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

#Preview {
    BuildHistoryView()
        .frame(width: 300, height: 400)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
} 