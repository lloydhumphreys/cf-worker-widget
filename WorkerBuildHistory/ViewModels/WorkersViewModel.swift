import Foundation

@MainActor
class WorkersViewModel: ObservableObject {
    @Published var accounts: [CFAccount] = []
    @Published var selectedAccountId: String? = nil
    @Published var workers: [Worker] = []
    @Published var pagesProjects: [PagesProject] = []
    @Published var buildHistory: [BuildStatus] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isActive: Bool = true
    
    private var currentTasks: [Task<Void, Never>] = []
    
    func cancelAllTasks() {
        currentTasks.forEach { $0.cancel() }
        currentTasks.removeAll()
        isActive = false
    }
    
    func deactivate() {
        cancelAllTasks()
        // Clear data to prevent stale state
        workers = []
        pagesProjects = []
        buildHistory = []
        error = nil
    }
    
    private func addTask(_ task: Task<Void, Never>) {
        currentTasks.append(task)
        // Clean up cancelled tasks
        currentTasks.removeAll { $0.isCancelled }
    }
    
    func loadAccounts() async {
        guard isActive else { 
            print("❌ WorkersViewModel: Not active, skipping account load")
            return 
        }
        
        print("🔄 WorkersViewModel: Starting account load...")
        isLoading = true
        error = nil
        
        do {
            print("🔑 WorkersViewModel: Fetching accounts from API...")
            accounts = try await CloudflareService.shared.fetchAccounts()
            print("✅ WorkersViewModel: Fetched \(accounts.count) accounts")
            
            guard isActive else { 
                print("❌ WorkersViewModel: No longer active after account fetch")
                return 
            }
            
            if let first = accounts.first {
                selectedAccountId = first.id
                print("✅ WorkersViewModel: Selected account: \(first.name) (\(first.id))")
                await loadWorkers(for: first.id)
                await loadPagesProjects(for: first.id)
            } else {
                print("❌ WorkersViewModel: No accounts found")
            }
        } catch {
            guard isActive else { return }
            print("❌ WorkersViewModel: Account load error: \(error)")
            self.error = error.localizedDescription
        }
        
        guard isActive else { return }
        isLoading = false
        print("✅ WorkersViewModel: Account load complete")
    }
    
    func loadWorkers(for accountId: String) async {
        guard isActive else { return }
        isLoading = true
        error = nil
        do {
            workers = try await CloudflareService.shared.fetchWorkers(accountId: accountId)
            // Notify data manager that workers were loaded
            await DataManager.shared.onWorkersLoaded()
        } catch {
            guard isActive else { return }
            self.error = error.localizedDescription
        }
        guard isActive else { return }
        isLoading = false
    }
    
    func loadPagesProjects(for accountId: String) async {
        guard isActive else { return }
        isLoading = true
        error = nil
        do {
            pagesProjects = try await CloudflareService.shared.fetchPagesProjects(accountId: accountId)
            // Notify data manager that pages were loaded
            await DataManager.shared.onWorkersLoaded()
        } catch {
            guard isActive else { return }
            self.error = error.localizedDescription
        }
        guard isActive else { return }
        isLoading = false
    }
    
    func toggleWorkerVisibility(_ worker: Worker) {
        if let index = workers.firstIndex(where: { $0.id == worker.id }) {
            workers[index].isVisible.toggle()
            Task {
                await DataManager.shared.onVisibilityChanged()
            }
        }
    }
    
    func enableAll() {
        for i in workers.indices {
            workers[i].isVisible = true
        }
        Task {
            await DataManager.shared.onVisibilityChanged()
        }
    }
    
    func disableAll() {
        for i in workers.indices {
            workers[i].isVisible = false
        }
        Task {
            await DataManager.shared.onVisibilityChanged()
        }
    }
    
    func loadBuildHistory() async {
        guard isActive, let accountId = selectedAccountId else { return }
        
        do {
            async let workerBuilds = CloudflareService.shared.fetchBuildHistoryForWorkers(workers, accountId: accountId)
            async let pagesBuilds = CloudflareService.shared.fetchBuildHistoryForPages(pagesProjects, accountId: accountId)
            
            let allBuilds = try await workerBuilds + pagesBuilds
            guard isActive else { return }
            
            buildHistory = allBuilds.sorted { $0.createdAt > $1.createdAt }
        } catch {
            guard isActive else { return }
            self.error = error.localizedDescription
        }
    }
    
    func refreshBuildHistory() async {
        await loadBuildHistory()
    }
} 