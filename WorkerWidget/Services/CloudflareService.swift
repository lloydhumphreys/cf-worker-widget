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
        // Short-circuit before touching the keychain so callers on the
        // refresh path never trigger a macOS access prompt when nothing
        // has been saved yet.
        guard KeychainManager.isApiKeyConfigured else {
            throw CloudflareError.noApiKey
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
            DiagnosticsManager.shared.log(.error, category: "cloudflare", message: "Accounts request returned a non-HTTP response")
            throw CloudflareError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Accounts request failed",
                metadata: ["statusCode": "\(httpResponse.statusCode)"]
            )
            throw CloudflareError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let accountsResponse = try JSONDecoder().decode(AccountsResponse.self, from: data)
        if !accountsResponse.success {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Cloudflare accounts API returned an error",
                metadata: ["errors": accountsResponse.errors.map(\.message).joined(separator: " | ")]
            )
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
            throw responseError(for: url, response: response)
        }
        let decoder = createJSONDecoder()
        let workersResponse = try decoder.decode(WorkersResponse.self, from: data)
        if !workersResponse.success {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Workers API returned an error",
                metadata: ["accountId": accountId, "errors": workersResponse.errors.map(\.message).joined(separator: " | ")]
            )
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
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw responseError(for: url, response: response)
        }
        let decoder = createJSONDecoder()
        let projectsResponse = try decoder.decode(PagesProjectsResponse.self, from: data)
        if !projectsResponse.success {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Pages projects API returned an error",
                metadata: ["accountId": accountId, "errors": projectsResponse.errors.map(\.message).joined(separator: " | ")]
            )
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
            throw responseError(for: url, response: response)
        }
        let decoder = createJSONDecoder()
        let deploymentsResponse = try decoder.decode(PagesDeploymentsResponse.self, from: data)
        if !deploymentsResponse.success {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Pages deployments API returned an error",
                metadata: ["accountId": accountId, "project": projectName, "errors": deploymentsResponse.errors.map(\.message).joined(separator: " | ")]
            )
            throw CloudflareError.apiError(deploymentsResponse.errors)
        }
        return deploymentsResponse.result
    }

    func fetchWorkerDeployments(accountId: String, scriptName: String, limit: Int = 25) async throws -> [WorkerDeployment] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts/\(scriptName)/deployments?limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw responseError(for: url, response: response)
        }
        
        let decoder = createJSONDecoder()
        let deploymentsResponse = try decoder.decode(WorkerDeploymentsResponse.self, from: data)
        if !deploymentsResponse.success {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Worker deployments API returned an error",
                metadata: ["accountId": accountId, "script": scriptName, "errors": deploymentsResponse.errors.map(\.message).joined(separator: " | ")]
            )
            throw CloudflareError.apiError(deploymentsResponse.errors)
        }
        
        return deploymentsResponse.result.deployments
    }
    
    func fetchWorkerBuilds(accountId: String, workerTag: String, limit: Int = 25) async throws -> [WorkerBuild] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/builds/workers/\(workerTag)/builds")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw responseError(for: url, response: response)
        }
        let buildsResponse = try JSONDecoder().decode(WorkerBuildsResponse.self, from: data)
        if !buildsResponse.success {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Worker builds API returned an error",
                metadata: ["accountId": accountId, "workerTag": workerTag, "errors": buildsResponse.errors.map(\.message).joined(separator: " | ")]
            )
            throw CloudflareError.apiError(buildsResponse.errors)
        }
        return Array(buildsResponse.result.prefix(limit))
    }

    func fetchBuildHistoryForWorkers(_ workers: [Worker], accountId: String) async throws -> [BuildStatus] {
        var buildStatuses: [BuildStatus] = []

        for worker in workers where worker.isVisible {
            do {
                if let tag = worker.tag {
                    // Fetch both Builds API and Deployments API concurrently
                    async let buildsResult = fetchWorkerBuilds(accountId: accountId, workerTag: tag, limit: 1)
                    async let deploysResult = fetchWorkerDeployments(accountId: accountId, scriptName: worker.id, limit: 1)

                    let builds = (try? await buildsResult) ?? []
                    let deployments = (try? await deploysResult) ?? []

                    let latestBuild = builds.first?.toBuildStatus(workerName: worker.id)
                    let latestDeploy = deployments.first?.toBuildStatus(workerName: worker.id)

                    if let result = mostRecent(latestBuild, latestDeploy) {
                        buildStatuses.append(result)
                    } else {
                        buildStatuses.append(worker.toBuildStatus())
                    }
                } else {
                    // No tag — Deployments API only
                    let deployments = try await fetchWorkerDeployments(accountId: accountId, scriptName: worker.id, limit: 5)
                    if let latestDeployment = deployments.first {
                        buildStatuses.append(latestDeployment.toBuildStatus(workerName: worker.id))
                    } else {
                        buildStatuses.append(worker.toBuildStatus())
                    }
                }
            } catch {
                DiagnosticsManager.shared.recordError(
                    error,
                    category: "cloudflare",
                    message: "Fell back to default worker status after build lookup failed",
                    metadata: ["accountId": accountId, "worker": worker.id]
                )
                buildStatuses.append(worker.toBuildStatus())
            }
        }

        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }

    /// Picks the most relevant status when both a git build and a deployment exist.
    /// Prefers in-progress builds, then whichever is more recent.
    private func mostRecent(_ build: BuildStatus?, _ deploy: BuildStatus?) -> BuildStatus? {
        switch (build, deploy) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?):
            // In-progress build is always the most relevant event
            if !x.status.isComplete { return x }
            // If deploy is newer, it's a distinct manual deploy
            if y.createdAt > x.createdAt { return y }
            // Otherwise prefer the build (richer git metadata)
            return x
        }
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
                DiagnosticsManager.shared.recordError(
                    error,
                    category: "cloudflare",
                    message: "Skipped Pages project after deployment lookup failed",
                    metadata: ["accountId": accountId, "project": project.name]
                )
            }
        }
        
        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Self.apiDateFormatter)
        return decoder
    }

    private func responseError(for url: URL, response: URLResponse?) -> CloudflareError {
        if let httpResponse = response as? HTTPURLResponse {
            DiagnosticsManager.shared.log(
                .error,
                category: "cloudflare",
                message: "Cloudflare request failed",
                metadata: ["url": url.absoluteString, "statusCode": "\(httpResponse.statusCode)"]
            )

            return .httpError(statusCode: httpResponse.statusCode)
        }

        DiagnosticsManager.shared.log(
            .error,
            category: "cloudflare",
            message: "Cloudflare request returned a non-HTTP response",
            metadata: ["url": url.absoluteString]
        )

        return .invalidResponse
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
