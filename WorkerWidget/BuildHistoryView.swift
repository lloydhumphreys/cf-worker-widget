import SwiftUI

struct BuildHistoryView: View {
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
                        dataManager.setAutoRefresh(enabled: !dataManager.autoRefreshEnabled)
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(dataManager.autoRefreshEnabled ? .green : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(dataManager.autoRefreshEnabled ? "Auto" : "Paused")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                SettingsLink {
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

            // Content
            if selectedProject != nil {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        detailContent
                    }
                    .background(listContainerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            } else if !hasApiKey {
                listContent
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        listContent
                    }
                    .background(listContainerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [.white.opacity(0.18), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
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

    private var listContainerBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.20))
    }

    private var hasApiKey: Bool {
        (try? KeychainManager.shared.getApiKey()) != nil
    }

    @ViewBuilder
    private var listContent: some View {
        if !hasApiKey {
            VStack(spacing: 12) {
                Image(systemName: "cloud")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.secondary)
                Text("Connect your Cloudflare account")
                    .font(.system(size: 13, weight: .medium))
                Text("Create a custom API token with these permissions:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Label("Workers Scripts — Read", systemImage: "checkmark.circle.fill")
                    Label("Workers Builds Configuration — Read", systemImage: "checkmark.circle.fill")
                    Label("Cloudflare Pages — Read", systemImage: "checkmark.circle.fill")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("Create Token") {
                        if let url = URL(string: "https://dash.cloudflare.com/profile/api-tokens") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    SettingsLink {
                        Text("Add API Key")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if dataManager.isLoading && dataManager.buildHistory.isEmpty {
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
            let items = Array(dataManager.buildHistory.prefix(14))
            ForEach(Array(items.enumerated()), id: \.element.id) { index, buildStatus in
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
                if index < items.count - 1 {
                    Divider().opacity(0.35)
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
            ForEach(Array(detailBuilds.enumerated()), id: \.element.id) { index, build in
                DetailBuildRow(build: build, onOpen: {
                    openBuildInBrowser(build)
                })
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openBuildInBrowser(build)
                    }
                if index < detailBuilds.count - 1 {
                    Divider().opacity(0.35)
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
        if let url = BuildDestination.dashboardURL(for: build, accountId: accountId) {
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
            Rectangle()
                .fill(.white.opacity(isHovered ? 0.14 : 0))
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
    let onOpen: (() -> Void)?

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

            if let onOpen {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Open in Cloudflare")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Rectangle()
                .fill(.white.opacity(isHovered ? 0.14 : 0))
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

#Preview("Build History") {
    BuildHistoryView()
        .frame(width: 400, height: 500)
}

#Preview("Rows") {
    let now = Date()
    let samples: [BuildStatus] = [
        BuildStatus(
            id: "1", projectId: "api-worker", projectName: "api-worker",
            projectType: .worker, status: .success,
            createdAt: now.addingTimeInterval(-300),
            completedAt: now.addingTimeInterval(-270),
            environment: "production", deploymentId: "1",
            commitHash: "a1b2c3d4e5f6", branch: "main",
            commitMessage: "Fix rate limiting on auth endpoint"
        ),
        BuildStatus(
            id: "2", projectId: "marketing-site", projectName: "marketing-site",
            projectType: .pages, status: .failure,
            createdAt: now.addingTimeInterval(-1800),
            completedAt: now.addingTimeInterval(-1750),
            environment: "production", deploymentId: "2",
            commitHash: "9f8e7d6c5b4a", branch: "preview/redesign",
            commitMessage: "Try new hero section layout"
        ),
        BuildStatus(
            id: "3", projectId: "edge-router", projectName: "edge-router",
            projectType: .worker, status: .inProgress,
            createdAt: now.addingTimeInterval(-30),
            completedAt: nil,
            environment: "production", deploymentId: "3",
            commitHash: "1122334455", branch: "wrangler",
            commitMessage: nil
        ),
        BuildStatus(
            id: "4", projectId: "docs", projectName: "docs",
            projectType: .pages, status: .queued,
            createdAt: now.addingTimeInterval(-5),
            completedAt: nil,
            environment: "production", deploymentId: "4",
            commitHash: "deadbeef00", branch: "main",
            commitMessage: "Add migration guide for v2"
        ),
    ]

    return VStack(spacing: 8) {
        ForEach(samples) { sample in
            BuildHistoryRow(buildStatus: sample)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.65))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                )
        }
    }
    .padding(16)
    .frame(width: 400)
    .background(
        LinearGradient(
            colors: [.blue.opacity(0.4), .purple.opacity(0.3), .pink.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
