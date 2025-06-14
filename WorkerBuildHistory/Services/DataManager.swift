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
    private var refreshTimer: Timer?
    private var lastRefreshTime: Date = Date.distantPast
    private let minimumRefreshInterval: TimeInterval = 60 // 1 minute minimum between refreshes
    
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
        // Rate limiting: don't refresh more than once per minute unless forced
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        if !force && timeSinceLastRefresh < minimumRefreshInterval {
            print("⏳ DataManager: Rate limited - last refresh was \(Int(timeSinceLastRefresh))s ago")
            return
        }
        
        lastRefreshTime = Date()
        print("🔄 DataManager: Starting build history refresh...")
        isLoading = true
        error = nil
        
        do {
            // First load accounts to get the selected account ID
            print("📋 DataManager: Loading accounts...")
            await workersViewModel.loadAccounts()
            
            guard let accountId = workersViewModel.selectedAccountId else {
                print("❌ DataManager: No account ID found")
                buildHistory = []
                isLoading = false
                return
            }
            
            print("✅ DataManager: Using account ID: \(accountId)")
            
            // Load workers and pages
            print("🔧 DataManager: Loading workers and pages...")
            await workersViewModel.loadWorkers(for: accountId)
            await workersViewModel.loadPagesProjects(for: accountId)
            
            print("📊 DataManager: Found \(workersViewModel.workers.count) workers, \(workersViewModel.pagesProjects.count) pages")
            
            // Apply saved visibility settings
            print("👁️ DataManager: Applying visibility settings...")
            applyVisibilitySettings()
            
            let visibleWorkers = workersViewModel.workers.filter { $0.isVisible }
            let visiblePages = workersViewModel.pagesProjects.filter { $0.isVisible }
            print("✅ DataManager: \(visibleWorkers.count) visible workers, \(visiblePages.count) visible pages")
            
            // Now load build history for visible items
            print("🏗️ DataManager: Loading build history...")
            await workersViewModel.loadBuildHistory()
            buildHistory = workersViewModel.buildHistory
            
            print("✅ DataManager: Loaded \(buildHistory.count) build history items")
        } catch {
            print("❌ DataManager: Error refreshing build history: \(error)")
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func startPeriodicRefresh() {
        // Prevent multiple timers
        refreshTimer?.invalidate()
        
        // Refresh every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await self.refreshBuildHistory()
            }
        }
    }
    
    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Settings Integration
    
    func onWorkersLoaded() {
        applyVisibilitySettings()
        // Don't auto-refresh on worker load to prevent rate limiting
        print("📝 DataManager: Workers loaded, visibility settings applied")
    }
    
    func onVisibilityChanged() {
        saveVisibilitySettings()
        // Don't auto-refresh on every visibility change to prevent rate limiting
        print("👁️ DataManager: Visibility settings saved")
    }
}