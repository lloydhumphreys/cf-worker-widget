import SwiftUI

struct BuildHistoryView: View {
    @State private var showingSettings = false
    @State private var autoRefreshEnabled = true
    @State private var selectedProject: BuildStatus?
    @State private var detailBuilds: [BuildStatus] = []
    @State private var loadingDetail = false
    @StateObject private var dataManager = DataManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                if selectedProject != nil {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProject = nil
                            detailBuilds = []
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Spacer()
                } else {
                    ZStack {
                        if dataManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(action: {
                                Task {
                                    await dataManager.refreshBuildHistory(force: true)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)

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
                }

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

            if selectedProject != nil {
                BuildHistoryRow(buildStatus: detailBuilds.first ?? selectedProject!)
                    .padding(.horizontal, 6)
            }

            Divider().opacity(0.5)

            // Content
            if selectedProject != nil {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        detailContent
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        listContent
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
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

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        if dataManager.isLoading && dataManager.buildHistory.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
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
            ForEach(dataManager.buildHistory.prefix(14)) { buildStatus in
                BuildHistoryRow(buildStatus: buildStatus)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let target = buildStatus
                        selectedProject = target
                        detailBuilds = []
                        loadingDetail = true
                        Task {
                            let results = await dataManager.fetchRecentBuilds(for: target)
                            // Only apply if the user hasn't navigated away
                            if selectedProject?.id == target.id {
                                detailBuilds = results
                                loadingDetail = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if loadingDetail {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading builds...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if detailBuilds.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.secondary)
                Text("No builds found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ForEach(detailBuilds) { build in
                DetailBuildRow(build: build)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openBuildInBrowser(build)
                    }
            }
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openBuildInBrowser(_ build: BuildStatus) {
        guard let accountId = dataManager.workersViewModel.selectedAccountId else { return }

        let urlString: String
        if build.projectType == .worker {
            if let buildId = build.deploymentId, build.branch != "wrangler" {
                // Builds API item — link to specific build
                urlString = "https://dash.cloudflare.com/\(accountId)/workers/services/view/\(build.projectName)/production/builds/\(buildId)"
            } else {
                // Deployment/wrangler item — link to worker overview
                urlString = "https://dash.cloudflare.com/\(accountId)/workers/services/view/\(build.projectName)/production"
            }
        } else {
            if let deploymentId = build.deploymentId {
                urlString = "https://dash.cloudflare.com/\(accountId)/pages/view/\(build.projectName)/\(deploymentId)"
            } else {
                urlString = "https://dash.cloudflare.com/\(accountId)/pages/view/\(build.projectName)"
            }
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Build History Row (summary)

struct BuildHistoryRow: View {
    let buildStatus: BuildStatus

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(buildStatus.projectName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 5) {
                    statusIcon(for: buildStatus.status)
                    Text(buildStatus.status.displayName(for: buildStatus.projectType))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor(for: buildStatus.status))
                }
            }

            if let message = buildStatus.commitMessage, !message.starts(with: "Build ") {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let branch = buildStatus.branch {
                    HStack(spacing: 3) {
                        Image(systemName: branch.lowercased() == "wrangler" ? "terminal" : "arrow.branch")
                            .font(.system(size: 9, weight: .medium))
                        Text(branch)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(branch.lowercased() == "wrangler" ? .orange : .purple)
                    .opacity(0.8)
                }

                if let commitHash = buildStatus.commitHash {
                    Text(String(commitHash.prefix(7)))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(formatRelativeTime(buildStatus.createdAt))
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
        .help(buildStatus.commitMessage ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Detail Build Row

struct DetailBuildRow: View {
    let build: BuildStatus

    @State private var isHovered = false

    private var commitLabel: String {
        if let msg = build.commitMessage, !msg.starts(with: "Build ") {
            return msg
        }
        return build.status.displayName(for: build.projectType)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon(for: build.status)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(commitLabel)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    Spacer(minLength: 8)

                    Text(formatRelativeTime(build.createdAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .layoutPriority(1)
                }

                HStack(spacing: 8) {
                    if let branch = build.branch {
                        HStack(spacing: 3) {
                            Image(systemName: branch.lowercased() == "wrangler" ? "terminal" : "arrow.branch")
                                .font(.system(size: 9, weight: .medium))
                            Text(branch)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(branch.lowercased() == "wrangler" ? .orange : .purple)
                        .opacity(0.8)
                    }

                    if let commitHash = build.commitHash {
                        Text(String(commitHash.prefix(7)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let completedAt = build.completedAt {
                        let duration = completedAt.timeIntervalSince(build.createdAt)
                        if duration > 0 {
                            Text(formatDuration(duration))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
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

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}

// MARK: - Shared Helpers

func statusIcon(for statusType: BuildStatus.BuildStatusType?) -> some View {
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

func statusColor(for statusType: BuildStatus.BuildStatusType?) -> Color {
    guard let statusType = statusType else { return .secondary }
    switch statusType {
    case .success: return .green
    case .failure: return .red
    case .inProgress: return .blue
    case .canceled: return .secondary
    case .queued: return .orange
    }
}

#Preview {
    BuildHistoryView()
        .frame(width: 400, height: 500)
}
