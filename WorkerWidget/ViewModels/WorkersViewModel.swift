import Foundation

@MainActor
class WorkersViewModel: ObservableObject {
    @Published var accounts: [CFAccount] = []
    @Published var selectedAccountId: String? = nil
    @Published var workers: [Worker] = []
    @Published var pagesProjects: [PagesProject] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isActive: Bool = true
    
    func deactivate() {
        isActive = false
        // Clear data to prevent stale state
        workers = []
        pagesProjects = []
        error = nil
    }
    
    func loadAccounts() async {
        guard isActive else { return }
        isLoading = true
        error = nil

        do {
            accounts = try await CloudflareService.shared.fetchAccounts()
            guard isActive else { return }

            let preferredAccountId = selectedAccountId.flatMap { currentId in
                accounts.contains(where: { $0.id == currentId }) ? currentId : nil
            } ?? accounts.first?.id

            if let preferredAccountId {
                selectedAccountId = preferredAccountId
                await loadWorkers(for: preferredAccountId)
                await loadPagesProjects(for: preferredAccountId)
            }
        } catch {
            guard isActive else { return }
            self.error = error.localizedDescription
            DiagnosticsManager.shared.recordError(error, category: "workers", message: "Failed to load Cloudflare accounts")
        }

        guard isActive else { return }
        isLoading = false
    }
    
    func loadWorkers(for accountId: String) async {
        guard isActive else { return }
        isLoading = true
        error = nil
        do {
            var loadedWorkers = try await CloudflareService.shared.fetchWorkers(accountId: accountId)
            AppPreferences.applyWorkerVisibility(to: &loadedWorkers)
            workers = loadedWorkers
        } catch {
            guard isActive else { return }
            self.error = error.localizedDescription
            DiagnosticsManager.shared.recordError(
                error,
                category: "workers",
                message: "Failed to load Workers",
                metadata: ["accountId": accountId]
            )
        }
        guard isActive else { return }
        isLoading = false
    }
    
    func loadPagesProjects(for accountId: String) async {
        guard isActive else { return }
        isLoading = true
        error = nil
        do {
            var loadedPagesProjects = try await CloudflareService.shared.fetchPagesProjects(accountId: accountId)
            AppPreferences.applyPagesVisibility(to: &loadedPagesProjects)
            pagesProjects = loadedPagesProjects
        } catch {
            guard isActive else { return }
            self.error = error.localizedDescription
            DiagnosticsManager.shared.recordError(
                error,
                category: "workers",
                message: "Failed to load Pages projects",
                metadata: ["accountId": accountId]
            )
        }
        guard isActive else { return }
        isLoading = false
    }

    func setAllVisibility(_ isVisible: Bool) {
        for i in workers.indices {
            workers[i].isVisible = isVisible
        }

        for i in pagesProjects.indices {
            pagesProjects[i].isVisible = isVisible
        }

        AppPreferences.saveVisibilitySettings(workers: workers, pagesProjects: pagesProjects)
    }
}
