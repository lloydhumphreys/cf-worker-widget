import SwiftUI

struct DebugSettingsView: View {
    @StateObject private var diagnostics = DiagnosticsManager.shared
    @StateObject private var dataManager = DataManager.shared

    private var cacheStats: CacheStats {
        CacheManager.shared.getCacheStats()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Runtime") {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugValueRow(label: "Builds in memory", value: "\(dataManager.buildHistory.count)")
                        DebugValueRow(label: "Last refresh started", value: formatTimestamp(dataManager.lastRefreshStartedAt))
                        DebugValueRow(label: "Last refresh succeeded", value: formatTimestamp(dataManager.lastSuccessfulRefreshAt))
                        DebugValueRow(label: "Auto refresh", value: dataManager.autoRefreshEnabled ? "Enabled" : "Paused")
                        DebugValueRow(label: "Selected account", value: dataManager.workersViewModel.selectedAccountId ?? "None")
                        DebugValueRow(label: "Visible workers", value: "\(dataManager.workersViewModel.workers.filter(\.isVisible).count)")
                        DebugValueRow(label: "Visible Pages", value: "\(dataManager.workersViewModel.pagesProjects.filter(\.isVisible).count)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Cache") {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugValueRow(label: "Has cached data", value: cacheStats.hasCachedData ? "Yes" : "No")
                        DebugValueRow(label: "Cache age", value: formatInterval(cacheStats.cacheAge))
                        DebugValueRow(label: "Tracked projects", value: "\(cacheStats.projectCount)")
                        DebugValueRow(label: "Oldest update", value: formatInterval(cacheStats.oldestUpdate))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Actions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Refresh Now") {
                            Task {
                                await DataManager.shared.refreshBuildHistory(force: true)
                            }
                        }

                        Button("Clear Build Cache") {
                            CacheManager.shared.clearCache()
                            DiagnosticsManager.shared.log(.info, category: "debug", message: "Cleared cached build history")
                        }

                        Button("Reset Notification Baseline") {
                            NotificationManager.shared.clearStoredStatuses()
                        }

                        Button("Clear Debug Events") {
                            DiagnosticsManager.shared.clear()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Recent Events") {
                    if diagnostics.events.isEmpty {
                        Text("No diagnostic events recorded yet.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(diagnostics.events) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(event.level.rawValue.uppercased())
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(color(for: event.level))

                                        Text(event.category)
                                            .font(.caption.monospaced())
                                            .foregroundColor(.secondary)

                                        Spacer()

                                        Text(formatTimestamp(event.timestamp))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Text(event.message)
                                        .font(.callout)

                                    if !event.metadata.isEmpty {
                                        Text(event.metadata
                                            .sorted { $0.key < $1.key }
                                            .map { "\($0.key): \($0.value)" }
                                            .joined(separator: "\n"))
                                            .font(.caption.monospaced())
                                            .foregroundColor(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if event.id != diagnostics.events.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    private func color(for level: DiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func formatTimestamp(_ date: Date?) -> String {
        guard let date else { return "Never" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "n/a" }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }
}

private struct DebugValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}
