import SwiftUI

struct BuildHistoryView: View {
    @State private var showingSettings = false
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            
            VStack(spacing: 8) {
                HStack {
                    Button(action: { 
                        Task {
                            await dataManager.refreshBuildHistory(force: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(dataManager.isLoading)
                    .padding(8)
                    
                    Spacer()
                    
                    Button(action: { 
                        if !showingSettings {
                            openSettings()
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .background(Color(NSColor.controlBackgroundColor))
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if dataManager.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading build history...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else if let error = dataManager.error {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        } else if dataManager.buildHistory.isEmpty {
                            VStack {
                                Image(systemName: "tray")
                                    .foregroundColor(.secondary)
                                Text("No build history found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Configure workers and pages in settings")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(Array(dataManager.buildHistory.prefix(10).enumerated()), id: \.element.id) { index, buildStatus in
                                VStack(spacing: 0) {
                                    BuildHistoryRow(
                                        buildNumber: buildStatus.projectName,
                                        status: buildStatus.status.displayName(for: buildStatus.projectType),
                                        timestamp: formatRelativeTime(buildStatus.createdAt),
                                        statusType: buildStatus.status,
                                        projectType: buildStatus.projectType,
                                        commitHash: buildStatus.commitHash,
                                        branch: buildStatus.branch
                                    )
                                    
                                    if index < dataManager.buildHistory.prefix(10).count - 1 {
                                        Divider()
                                            .padding(.leading, 12)
                                    }
                                }
                            }
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(4)
        }
        .frame(minWidth: 400, minHeight: 300)
        .mask(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(width: 550, height: 450)
        }
        .onAppear {
            dataManager.startPeriodicRefresh()
            // Smart refresh on app open - shows cached data instantly, then updates as needed
            Task {
                await dataManager.smartRefresh()
            }
        }
        .onDisappear {
            dataManager.stopPeriodicRefresh()
        }
    }
    
    private func openSettings() {
        showingSettings = true
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct BuildHistoryRow: View {
    let buildNumber: String
    let status: String
    let timestamp: String
    let statusType: BuildStatus.BuildStatusType?
    let projectType: BuildStatus.ProjectType?
    let commitHash: String?
    let branch: String?
    
    init(buildNumber: String, status: String, timestamp: String, statusType: BuildStatus.BuildStatusType? = nil, projectType: BuildStatus.ProjectType? = nil, commitHash: String? = nil, branch: String? = nil) {
        self.buildNumber = buildNumber
        self.status = status
        self.timestamp = timestamp
        self.statusType = statusType
        self.projectType = projectType
        self.commitHash = commitHash
        self.branch = branch
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(buildNumber)
                    .font(.headline)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 4) {
                    // Status indicator with appropriate icon
                    statusIcon
                    
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                }
            }
            
            // Commit and branch info
            HStack(spacing: 8) {
                if let branch = branch {
                    HStack(spacing: 2) {
                        Image(systemName: branch.lowercased() == "wrangler" ? "chevron.forward" : "arrow.branch")
                            .font(.caption2)
                            .foregroundColor(branch.lowercased() == "wrangler" ? Color.orange : Color.purple)
                        Text(branch)
                            .font(.caption)
                            .foregroundColor(branch.lowercased() == "wrangler" ? Color.orange : Color.purple)
                    }
                }
                
                if let commitHash = commitHash {
                    HStack(spacing: 2) {
                        Image(systemName: "number")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(commitHash.prefix(8))) // Show first 8 characters
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
                
                Spacer()
                
                Text(timestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
    
    private var statusIcon: some View {
        Group {
            switch statusType {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.0, green: 0.6, blue: 0.0))
            case .failure:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            case .inProgress:
                Image(systemName: "clock")
                    .foregroundColor(.blue)
            case .canceled:
                Image(systemName: "xmark")
                    .foregroundColor(.orange)
            case .queued:
                Image(systemName: "clock.badge")
                    .foregroundColor(.gray)
            default:
                Image(systemName: "questionmark")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }
    
    private var statusColor: Color {
        guard let statusType = statusType else { return Color.green.opacity(0.8) }
        
        switch statusType {
        case .success:
            return Color(red: 0.0, green: 0.6, blue: 0.0) // Dark green
        case .failure:
            return .red
        case .inProgress:
            return .orange
        case .canceled:
            return .gray
        case .queued:
            return .orange
        }
    }
}

#Preview {
    BuildHistoryView()
        .frame(width: 600, height: 500)
        .padding()
} 
