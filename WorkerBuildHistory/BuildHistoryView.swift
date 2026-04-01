import SwiftUI

struct BuildHistoryView: View {
    @State private var showingSettings = false
    @State private var autoRefreshEnabled = true
    @StateObject private var dataManager = DataManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await dataManager.refreshBuildHistory(force: true)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .rotationEffect(.degrees(dataManager.isLoading ? 360 : 0))
                        .animation(dataManager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataManager.isLoading)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(dataManager.isLoading)

                Button(action: {
                    autoRefreshEnabled.toggle()
                    dataManager.setAutoRefresh(enabled: autoRefreshEnabled)
                }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(autoRefreshEnabled ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(autoRefreshEnabled ? "Auto" : "Paused")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    if !showingSettings {
                        showingSettings = true
                    }
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.5)

            // Content
            ScrollView {
                LazyVStack(spacing: 2) {
                    if dataManager.isLoading && dataManager.buildHistory.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let error = dataManager.error, dataManager.buildHistory.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if dataManager.buildHistory.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(.secondary)
                            Text("No build history")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(dataManager.buildHistory.prefix(12)) { buildStatus in
                            BuildHistoryRow(
                                buildNumber: buildStatus.projectName,
                                status: buildStatus.status.displayName(for: buildStatus.projectType),
                                timestamp: formatRelativeTime(buildStatus.createdAt),
                                statusType: buildStatus.status,
                                projectType: buildStatus.projectType,
                                commitHash: buildStatus.commitHash,
                                branch: buildStatus.branch
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(width: 550, height: 450)
        }
        .onAppear {
            if dataManager.buildHistory.isEmpty {
                Task {
                    await dataManager.smartRefresh()
                }
            }
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Build History Row

struct BuildHistoryRow: View {
    let buildNumber: String
    let status: String
    let timestamp: String
    let statusType: BuildStatus.BuildStatusType?
    let projectType: BuildStatus.ProjectType?
    let commitHash: String?
    let branch: String?

    @State private var isHovered = false

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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 5) {
                    statusIcon
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)
                }
            }

            HStack(spacing: 8) {
                if let branch = branch {
                    HStack(spacing: 3) {
                        Image(systemName: branch.lowercased() == "wrangler" ? "terminal" : "arrow.branch")
                            .font(.system(size: 9, weight: .medium))
                        Text(branch)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(branch.lowercased() == "wrangler" ? .orange : .purple)
                    .opacity(0.8)
                }

                if let commitHash = commitHash {
                    HStack(spacing: 2) {
                        Text(String(commitHash.prefix(7)))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(timestamp)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch statusType {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .inProgress:
                Image(systemName: "progress.indicator")
                    .foregroundColor(.blue)
            case .canceled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary)
            case .queued:
                Image(systemName: "clock.fill")
                    .foregroundColor(.secondary)
            default:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    private var statusColor: Color {
        guard let statusType = statusType else { return .secondary }

        switch statusType {
        case .success: return .green
        case .failure: return .red
        case .inProgress: return .blue
        case .canceled: return .secondary
        case .queued: return .orange
        }
    }
}

#Preview {
    BuildHistoryView()
        .frame(width: 400, height: 500)
}
