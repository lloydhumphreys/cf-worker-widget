import Foundation
import SwiftUI

// Shared data manager to handle persistence and data sharing between views
@MainActor
class DataManager: ObservableObject {
    enum MenuBarState {
        case normal
        case inProgress
        case failed
    }

    static let shared = DataManager()
    
    @Published var workersViewModel = WorkersViewModel()
    @Published var buildHistory: [BuildStatus] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published private(set) var autoRefreshEnabled: Bool
    @Published private(set) var menuBarState: MenuBarState = .normal
    @Published private(set) var lastRefreshStartedAt: Date?
    @Published private(set) var lastSuccessfulRefreshAt: Date?

    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let defaultRefreshMinutes = 5

    private var refreshTimer: Timer?
    private var lastRefreshTime: Date = Date.distantPast
    private let failureHighlightWindow: TimeInterval = 30 * 60

    var refreshIntervalMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
            return stored > 0 ? stored : Self.defaultRefreshMinutes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.refreshIntervalKey)
            // Restart timer with new interval
            if autoRefreshEnabled {
                startPeriodicRefresh()
            }
        }
    }

    private var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
    
    private init() {
        autoRefreshEnabled = AppPreferences.autoRefreshEnabled
    }
    
    // MARK: - Build History Management
    
    func refreshBuildHistory(force: Bool = false) async {
        // Load cached data immediately if available
        if let cachedData = CacheManager.shared.getCachedBuildHistory() {
            buildHistory = cachedData
            updateDerivedState(using: cachedData)
        }
        
        // Rate limiting: don't refresh more than once per minute unless forced
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        if !force && timeSinceLastRefresh < refreshInterval {
            return
        }
        
        lastRefreshTime = Date()
        lastRefreshStartedAt = Date()
        isLoading = true
        error = nil
        DiagnosticsManager.shared.log(
            .info,
            category: "data",
            message: "Refreshing build history",
            metadata: ["force": force ? "true" : "false"]
        )
        
        // First load accounts to get the selected account ID
        await workersViewModel.loadAccounts()
        error = workersViewModel.error

        guard let accountId = workersViewModel.selectedAccountId else {
            buildHistory = []
            updateDerivedState(using: [])
            isLoading = false
            return
        }

        // Load workers and pages
        await workersViewModel.loadWorkers(for: accountId)
        error = workersViewModel.error
        await workersViewModel.loadPagesProjects(for: accountId)
        error = workersViewModel.error

        let visibleWorkers = workersViewModel.workers.filter { $0.isVisible }
        let visiblePages = workersViewModel.pagesProjects.filter { $0.isVisible }

        // Now load build history for visible items progressively
        var progressiveBuildHistory: [BuildStatus] = []

        // Create tasks for all workers and pages
        await withTaskGroup(of: [BuildStatus].self) { group in
            // Add worker tasks
            for worker in visibleWorkers {
                group.addTask {
                    do {
                        return try await CloudflareService.shared.fetchBuildHistoryForWorkers([worker], accountId: accountId)
                    } catch {
                        DiagnosticsManager.shared.recordError(
                            error,
                            category: "data",
                            message: "Failed to refresh worker build history",
                            metadata: ["worker": worker.id, "accountId": accountId]
                        )
                        return []
                    }
                }
            }

            // Add pages tasks
            for page in visiblePages {
                group.addTask {
                    do {
                        return try await CloudflareService.shared.fetchBuildHistoryForPages([page], accountId: accountId)
                    } catch {
                        DiagnosticsManager.shared.recordError(
                            error,
                            category: "data",
                            message: "Failed to refresh Pages build history",
                            metadata: ["project": page.name, "accountId": accountId]
                        )
                        return []
                    }
                }
            }

            // Process results as they complete
            for await result in group {
                if !result.isEmpty {
                    progressiveBuildHistory.append(contentsOf: result)
                    // Update UI immediately with new results
                    let sortedBuilds = progressiveBuildHistory.sorted { $0.createdAt > $1.createdAt }
                    buildHistory = sortedBuilds
                    updateDerivedState(using: sortedBuilds)
                }
            }
        }

        let newBuildHistory = progressiveBuildHistory.sorted { $0.createdAt > $1.createdAt }

        // Check for build status changes and send notifications
        NotificationManager.shared.checkForBuildStatusChanges(newBuildHistory, accountId: accountId)

        // Update build history and cache it
        buildHistory = newBuildHistory
        CacheManager.shared.cacheBuildHistory(newBuildHistory)
        lastSuccessfulRefreshAt = Date()
        updateDerivedState(using: newBuildHistory)
        DiagnosticsManager.shared.log(
            .info,
            category: "data",
            message: "Build history refresh finished",
            metadata: ["items": "\(newBuildHistory.count)"]
        )
        
        isLoading = false
    }
    
    func smartRefresh() async {
        // Always show cached data first for instant loading
        if let cachedData = CacheManager.shared.getCachedBuildHistory() {
            buildHistory = cachedData
        }
        
        // Check which projects need updating
        let projectsNeedingRefresh = CacheManager.shared.getProjectsNeedingRefresh(from: buildHistory)
        
        if projectsNeedingRefresh.isEmpty {
            return
        }
        
        // Only refresh if actually needed, and do it in background
        await refreshBuildHistory(force: false)
    }
    
    func setAutoRefresh(enabled: Bool) {
        autoRefreshEnabled = enabled
        AppPreferences.autoRefreshEnabled = enabled

        if enabled {
            startPeriodicRefresh()
        } else {
            stopPeriodicRefresh()
        }
    }
    
    func startPeriodicRefresh() {
        guard autoRefreshEnabled else { return }
        
        // Prevent multiple timers
        refreshTimer?.invalidate()
        
        // Auto-refresh every 30 seconds when enabled
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.smartRefresh()
            }
        }
    }
    
    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Detail Builds

    func fetchRecentBuilds(for project: BuildStatus) async -> [BuildStatus] {
        guard let accountId = workersViewModel.selectedAccountId else { return [] }

        if project.projectType == .worker {
            if let worker = workersViewModel.workers.first(where: { $0.id == project.projectName }),
               let tag = worker.tag {
                // Fetch both APIs concurrently and merge the results
                async let buildsResult = CloudflareService.shared.fetchWorkerBuilds(accountId: accountId, workerTag: tag, limit: 10)
                async let deploysResult = CloudflareService.shared.fetchWorkerDeployments(accountId: accountId, scriptName: project.projectName, limit: 10)

                let builds = (try? await buildsResult) ?? []
                let deployments = (try? await deploysResult) ?? []

                let gitStatuses = builds.map { $0.toBuildStatus(workerName: project.projectName) }
                let deployStatuses = deployments.map { $0.toBuildStatus(workerName: project.projectName) }

                return mergeAndDeduplicate(builds: gitStatuses, deployments: deployStatuses)
            }
            // No tag — Deployments API only
            do {
                let deployments = try await CloudflareService.shared.fetchWorkerDeployments(accountId: accountId, scriptName: project.projectName, limit: 10)
                return deployments.map { $0.toBuildStatus(workerName: project.projectName) }
            } catch {
                return []
            }
        } else {
            // Pages project
            do {
                let deployments = try await CloudflareService.shared.fetchPagesDeployments(accountId: accountId, projectName: project.projectName, limit: 10)
                return deployments.map { $0.toBuildStatus(projectName: project.projectName) }
            } catch {
                return []
            }
        }
    }

    /// Merges git builds with manual (wrangler) deployments, avoiding duplicates.
    /// Git-triggered deployments appear in both APIs, so we keep only wrangler entries from the Deployments API.
    private func mergeAndDeduplicate(builds: [BuildStatus], deployments: [BuildStatus]) -> [BuildStatus] {
        let manualDeploys = deployments.filter { $0.branch?.lowercased() == "wrangler" }
        let merged = builds + manualDeploys
        return Array(merged.sorted { $0.createdAt > $1.createdAt }.prefix(10))
    }

    private func updateDerivedState(using builds: [BuildStatus]) {
        if builds.contains(where: isRecentFailure(_:)) {
            menuBarState = .failed
        } else if builds.contains(where: isActiveBuild(_:)) {
            menuBarState = .inProgress
        } else {
            menuBarState = .normal
        }
    }

    private func isRecentFailure(_ build: BuildStatus) -> Bool {
        build.status == .failure && Date().timeIntervalSince(build.createdAt) <= failureHighlightWindow
    }

    private func isActiveBuild(_ build: BuildStatus) -> Bool {
        build.status == .inProgress || build.status == .queued
    }
}
