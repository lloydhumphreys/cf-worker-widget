import Foundation
import SwiftUI

// Shared data manager to handle persistence and data sharing between views
@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var workersViewModel = WorkersViewModel()
    @Published var buildHistory: [BuildStatus] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let visibilityKey = "workerVisibilitySettings"
    private let pagesVisibilityKey = "pagesVisibilitySettings"
    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let defaultRefreshMinutes = 5

    private var refreshTimer: Timer?
    private var lastRefreshTime: Date = Date.distantPast
    private var autoRefreshEnabled: Bool = true
    private static var hasExploredAPIs = false

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
        // Load saved visibility settings on initialization
        loadVisibilitySettings()
    }
    
    // MARK: - Persistence Methods
    
    func saveVisibilitySettings() {
        // This method is now handled in SettingsView directly
        // We keep this here for compatibility but it's not the primary save method
    }
    
    private func loadVisibilitySettings() {
        // This will be called after workers and pages are loaded
    }
    
    func applyVisibilitySettings() {
        guard let workerSettings = UserDefaults.standard.dictionary(forKey: visibilityKey) as? [String: Bool],
              let pagesSettings = UserDefaults.standard.dictionary(forKey: pagesVisibilityKey) as? [String: Bool] else {
            return
        }
        
        // Apply saved settings to workers
        for i in workersViewModel.workers.indices {
            if let savedVisibility = workerSettings[workersViewModel.workers[i].id] {
                workersViewModel.workers[i].isVisible = savedVisibility
            }
        }
        
        // Apply saved settings to pages projects
        for i in workersViewModel.pagesProjects.indices {
            if let savedVisibility = pagesSettings[workersViewModel.pagesProjects[i].id] {
                workersViewModel.pagesProjects[i].isVisible = savedVisibility
            }
        }
    }
    
    // MARK: - Build History Management
    
    func refreshBuildHistory(force: Bool = false) async {
        // Load cached data immediately if available
        if let cachedData = CacheManager.shared.getCachedBuildHistory() {
            buildHistory = cachedData
        }
        
        // Rate limiting: don't refresh more than once per minute unless forced
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        if !force && timeSinceLastRefresh < refreshInterval {
            return
        }
        
        lastRefreshTime = Date()
        isLoading = true
        error = nil
        
        // First load accounts to get the selected account ID
        await workersViewModel.loadAccounts()

        guard let accountId = workersViewModel.selectedAccountId else {
            buildHistory = []
            isLoading = false
            return
        }

        // Load workers and pages
        await workersViewModel.loadWorkers(for: accountId)
        await workersViewModel.loadPagesProjects(for: accountId)

        // Apply saved visibility settings
        applyVisibilitySettings()

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
                        return []
                    }
                }
            }

            // Process results as they complete
            for await result in group {
                if !result.isEmpty {
                    progressiveBuildHistory.append(contentsOf: result)
                    // Update UI immediately with new results
                    buildHistory = progressiveBuildHistory.sorted { $0.createdAt > $1.createdAt }
                }
            }
        }

        let newBuildHistory = progressiveBuildHistory.sorted { $0.createdAt > $1.createdAt }

        // Check for build status changes and send notifications
        NotificationManager.shared.checkForBuildStatusChanges(newBuildHistory)

        // Update build history and cache it
        buildHistory = newBuildHistory
        CacheManager.shared.cacheBuildHistory(newBuildHistory)
        
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
    
    // MARK: - Build Merging
    
    private func mergeBuilds(existing: [BuildStatus], active: [BuildStatus]) -> [BuildStatus] {
        var merged = existing
        
        for activeBuild in active {
            // Remove any existing entry for the same project
            merged.removeAll { existingBuild in
                existingBuild.projectName == activeBuild.projectName && 
                existingBuild.projectType == activeBuild.projectType
            }
            // Add the active build
            merged.append(activeBuild)
        }
        
        // Sort by creation date, most recent first
        return merged.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - Detail Builds

    func fetchRecentBuilds(for project: BuildStatus) async -> [BuildStatus] {
        guard let accountId = workersViewModel.selectedAccountId else { return [] }

        if project.projectType == .worker {
            // Try Builds API first
            if let worker = workersViewModel.workers.first(where: { $0.id == project.projectName }),
               let tag = worker.tag {
                if let builds = try? await CloudflareService.shared.fetchWorkerBuilds(accountId: accountId, workerTag: tag, limit: 10),
                   !builds.isEmpty {
                    return builds.map { $0.toBuildStatus(workerName: project.projectName) }
                }
            }
            // Fall back to deployments API
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

    // MARK: - Settings Integration

    func onWorkersLoaded() {
        applyVisibilitySettings()
        // Don't auto-refresh on worker load to prevent rate limiting
    }
    
    func onVisibilityChanged() {
        saveVisibilitySettings()
        // Don't auto-refresh on every visibility change to prevent rate limiting
    }
}
