import Foundation

class CloudflareService {
    static let shared = CloudflareService()
    private let baseURL = "https://api.cloudflare.com/client/v4"
    private var cachedApiKey: String?

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private func getApiKey() throws -> String {
        if let cached = cachedApiKey {
            return cached
        }
        guard let apiKey = try KeychainManager.shared.getApiKey(), !apiKey.isEmpty else {
            throw CloudflareError.noApiKey
        }
        cachedApiKey = apiKey
        return apiKey
    }

    func clearCachedApiKey() {
        cachedApiKey = nil
    }

    private init() {}
    
    func fetchAccounts() async throws -> [CFAccount] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudflareError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw CloudflareError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let accountsResponse = try JSONDecoder().decode(AccountsResponse.self, from: data)
        if !accountsResponse.success {
            throw CloudflareError.apiError(accountsResponse.errors)
        }
        return accountsResponse.result
    }
    
    func fetchWorkers(accountId: String) async throws -> [Worker] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        let decoder = createJSONDecoder()
        let workersResponse = try decoder.decode(WorkersResponse.self, from: data)
        if !workersResponse.success {
            throw CloudflareError.apiError(workersResponse.errors)
        }
        // Set all workers to visible by default
        return workersResponse.result.map { worker in
            var modifiedWorker = worker
            modifiedWorker.isVisible = true
            return modifiedWorker
        }
    }

    func fetchPagesProjects(accountId: String) async throws -> [PagesProject] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/pages/projects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await session.data(for: request)
        let decoder = createJSONDecoder()
        let projectsResponse = try decoder.decode(PagesProjectsResponse.self, from: data)
        if !projectsResponse.success {
            throw CloudflareError.apiError(projectsResponse.errors)
        }
        return projectsResponse.result
    }
    
    
    func fetchPagesDeployments(accountId: String, projectName: String, limit: Int = 25) async throws -> [PagesDeployment] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/pages/projects/\(projectName)/deployments?limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        let decoder = createJSONDecoder()
        let deploymentsResponse = try decoder.decode(PagesDeploymentsResponse.self, from: data)
        if !deploymentsResponse.success {
            throw CloudflareError.apiError(deploymentsResponse.errors)
        }
        
        
        return deploymentsResponse.result
    }
    
    // New function to specifically look for active/in-progress builds
    func fetchActiveBuilds(accountId: String) async throws -> [BuildStatus] {
        var activeBuilds: [BuildStatus] = []
        
        // Check for active Worker deployments across all workers
        do {
            let workers = try await fetchWorkers(accountId: accountId)
            for worker in workers {
                
                // Get multiple deployments to check for any in-progress ones
                let deployments = try await fetchWorkerDeployments(accountId: accountId, scriptName: worker.id, limit: 25)
                
                // Look specifically for active/in-progress deployments
                let activeDeployments = deployments.filter { deployment in
                    // Check for gradual rollouts (percentage < 100%)
                    let hasPartialRollout = deployment.strategy.lowercased() == "percentage" && 
                                          deployment.versions.contains(where: { $0.percentage < 100 })
                    
                    // Check for recent deployments that might still be rolling out
                    let isVeryRecent = Date().timeIntervalSince(deployment.created_on) < 300 // 5 minutes
                    
                    let isActive = hasPartialRollout || (isVeryRecent && deployment.strategy.lowercased() == "percentage")
                    return isActive
                }
                
                for deployment in activeDeployments {
                    let buildStatus = deployment.toBuildStatus(workerName: worker.id)
                    activeBuilds.append(buildStatus)
                }
            }
        } catch {
        }
        
        // Check for active Pages builds across all projects
        do {
            let projects = try await fetchPagesProjects(accountId: accountId)
            for project in projects {
                let deployments = try await fetchPagesDeployments(accountId: accountId, projectName: project.name, limit: 50)
                
                // Look specifically for active builds
                let activeDeployments = deployments.filter { deployment in
                    let status = deployment.latest_stage.status.lowercased()
                    return ["active", "building", "in_progress", "deploying", "queued", "pending"].contains(status)
                }
                
                for deployment in activeDeployments {
                    let buildStatus = deployment.toBuildStatus(projectName: project.name)
                    activeBuilds.append(buildStatus)
                }
            }
        } catch {
        }
        
        // Check audit logs for recent deployment activity
        do {
            let auditBuilds = try await fetchRecentDeploymentActivity(accountId: accountId)
            activeBuilds.append(contentsOf: auditBuilds)
        } catch {
            // Silently continue if audit logs fail
        }
        
        return activeBuilds
    }
    
    // Parse audit logs for recent deployment activities
    func fetchRecentDeploymentActivity(accountId: String) async throws -> [BuildStatus] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/audit_logs?direction=desc&per_page=100")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        
        // Parse audit logs for deployment events
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = jsonObject["result"] as? [[String: Any]] {
            
            var buildStatuses: [BuildStatus] = []
            let now = Date()
            let recentThreshold = now.addingTimeInterval(-3600) // Last hour
            
            for log in result {
                // Look for worker deployment events
                if let action = log["action"] as? [String: Any],
                   let actionType = action["type"] as? String,
                   let metadata = log["metadata"] as? [String: Any],
                   let whenString = log["when"] as? String,
                   let resourceType = log["resource"] as? [String: Any],
                   let type = resourceType["type"] as? String {
                    
                    // Parse timestamp
                    let formatter = ISO8601DateFormatter()
                    guard let when = formatter.date(from: whenString),
                          when > recentThreshold else { continue }
                    
                    // Check for worker script events
                    if type == "worker_script" || actionType.contains("deploy") {
                        if let scriptName = metadata["script_name"] as? String {
                            
                            let status: BuildStatus.BuildStatusType
                            if actionType.contains("delete") {
                                status = .canceled
                            } else if actionType.contains("update") || actionType.contains("create") {
                                status = .success
                            } else {
                                continue
                            }
                            
                            
                            let buildStatus = BuildStatus(
                                id: "audit-\(scriptName)-\(when.timeIntervalSince1970)",
                                projectId: scriptName,
                                projectName: scriptName,
                                projectType: .worker,
                                status: status,
                                createdAt: when,
                                completedAt: when,
                                environment: "production",
                                deploymentId: nil,
                                commitHash: nil,
                                branch: "wrangler",
                                commitMessage: "Deployment via \(actionType)"
                            )
                            buildStatuses.append(buildStatus)
                        }
                    }
                }
            }
            
            return buildStatuses
        }
        
        return []
    }
    
    
    
    
    
    
    // Parse build statuses from the builds API response
    private func parseBuildStatuses(from builds: [[String: Any]], scriptName: String) -> [BuildStatus] {
        var buildStatuses: [BuildStatus] = []
        
        for build in builds {
            if let buildId = build["id"] as? String,
               let buildOutcome = build["build_outcome"] as? String,
               let status = build["status"] as? String {
                
                // Parse timestamps if available
                var createdAt = Date()
                var completedAt: Date? = nil
                
                if let createdAtString = build["created_at"] as? String {
                    createdAt = parseDate(from: createdAtString) ?? Date()
                }
                
                if let completedAtString = build["completed_at"] as? String {
                    completedAt = parseDate(from: completedAtString)
                }
                
                // Map build outcome to our status
                let buildStatus: BuildStatus.BuildStatusType
                if buildOutcome == "fail" || status == "stopped" || status == "failed" {
                    buildStatus = .failure
                } else if status == "running" || status == "building" {
                    buildStatus = .inProgress
                } else if status == "queued" || status == "pending" {
                    buildStatus = .queued
                } else if buildOutcome == "success" || status == "completed" {
                    buildStatus = .success
                } else {
                    buildStatus = .queued
                }
                
                // Get additional metadata
                let commitHash = build["commit_hash"] as? String
                let branch = build["branch"] as? String ?? "main"
                let message = build["message"] as? String
                
                
                let buildStatusEntry = BuildStatus(
                    id: buildId,
                    projectId: scriptName,
                    projectName: scriptName,
                    projectType: .worker,
                    status: buildStatus,
                    createdAt: createdAt,
                    completedAt: buildStatus.isComplete ? (completedAt ?? createdAt) : nil,
                    environment: "production",
                    deploymentId: buildId,
                    commitHash: commitHash,
                    branch: branch,
                    commitMessage: message ?? "Build \(buildOutcome)"
                )
                
                buildStatuses.append(buildStatusEntry)
            }
        }
        
        // Sort by creation date, most recent first
        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }
    
    // Helper function to parse dates from various formats
    private func parseDate(from dateString: String) -> Date? {
        // Try ISO8601 with fractional seconds first
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Fallback to standard ISO8601
        let standardFormatter = ISO8601DateFormatter()
        return standardFormatter.date(from: dateString)
    }
    
    
    
    func fetchWorkerDeployments(accountId: String, scriptName: String, limit: Int = 25) async throws -> [WorkerDeployment] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts/\(scriptName)/deployments?limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        
        let decoder = createJSONDecoder()
        let deploymentsResponse = try decoder.decode(WorkerDeploymentsResponse.self, from: data)
        if !deploymentsResponse.success {
            throw CloudflareError.apiError(deploymentsResponse.errors)
        }
        
        return deploymentsResponse.result.deployments
    }
    
    func fetchLatestWorkerDeployment(accountId: String, scriptName: String) async throws -> WorkerDeployment? {
        let apiKey = try getApiKey()
        // Get more deployments to catch in-progress ones
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts/\(scriptName)/deployments?limit=10")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        
        let decoder = createJSONDecoder()
        do {
            let deploymentsResponse = try decoder.decode(WorkerDeploymentsResponse.self, from: data)
            if !deploymentsResponse.success {

                throw CloudflareError.apiError(deploymentsResponse.errors)
            }
            // Prioritize in-progress deployments, otherwise return the latest
            let inProgressDeployment = deploymentsResponse.result.deployments.first { deployment in
                deployment.strategy.lowercased() == "percentage" && 
                deployment.versions.contains(where: { $0.percentage < 100 })
            }
            
            let selectedDeployment = inProgressDeployment ?? deploymentsResponse.result.deployments.first
            return selectedDeployment
        } catch {
            throw error
        }
    }
    
    func fetchWorkerBuilds(accountId: String, workerTag: String, limit: Int = 25) async throws -> [WorkerBuild] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/builds/workers/\(workerTag)/builds")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        let buildsResponse = try JSONDecoder().decode(WorkerBuildsResponse.self, from: data)
        if !buildsResponse.success {
            throw CloudflareError.apiError(buildsResponse.errors)
        }
        return Array(buildsResponse.result.prefix(limit))
    }

    func fetchBuildHistoryForWorkers(_ workers: [Worker], accountId: String) async throws -> [BuildStatus] {
        var buildStatuses: [BuildStatus] = []

        for worker in workers where worker.isVisible {
            do {
                // Try the Builds API first if we have a tag
                if let tag = worker.tag {
                    let builds = try await fetchWorkerBuilds(accountId: accountId, workerTag: tag, limit: 25)
                    if let latestBuild = builds.first {
                        buildStatuses.append(latestBuild.toBuildStatus(workerName: worker.id))
                        continue
                    }
                }

                // Fall back to deployments API for workers without Builds enabled
                let deployments = try await fetchWorkerDeployments(accountId: accountId, scriptName: worker.id, limit: 5)
                if let latestDeployment = deployments.first {
                    buildStatuses.append(latestDeployment.toBuildStatus(workerName: worker.id))
                } else {
                    buildStatuses.append(worker.toBuildStatus())
                }
            } catch {
                buildStatuses.append(worker.toBuildStatus())
            }
        }

        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchBuildHistoryForPages(_ projects: [PagesProject], accountId: String) async throws -> [BuildStatus] {
        var buildStatuses: [BuildStatus] = []
        
        // Fetch latest deployment for each visible pages project
        for project in projects where project.isVisible {
            do {
                let deployments = try await fetchPagesDeployments(accountId: accountId, projectName: project.name, limit: 25)
                // Prioritize in-progress deployments, otherwise get the most recent
                let inProgressDeployment = deployments.first { deployment in
                    let status = deployment.latest_stage.status.lowercased()
                    return ["active", "building", "in_progress", "deploying"].contains(status)
                }
                
                let selectedDeployment = inProgressDeployment ?? deployments.first
                if let deployment = selectedDeployment {
                    let status = deployment.toBuildStatus(projectName: project.name)
                    buildStatuses.append(status)
                }
            } catch {
                // Continue with other projects if one fails
            }
        }
        
        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Self.apiDateFormatter)
        return decoder
    }
}

enum CloudflareError: Error {
    case noApiKey
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError([APIError])
    
    var localizedDescription: String {
        switch self {
        case .noApiKey:
            return "No API key found. Please add your Cloudflare API key in settings."
        case .invalidResponse:
            return "Invalid response from Cloudflare API"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .apiError(let errors):
            return errors.map { "Error \($0.code): \($0.message)" }.joined(separator: "\n")
        }
    }
} 