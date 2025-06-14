import Foundation

class CloudflareService {
    static let shared = CloudflareService()
    private let baseURL = "https://api.cloudflare.com/client/v4"
    
    private func getApiKey() throws -> String {
        print("🔑 CloudflareService: Attempting to get API key from keychain...")
        do {
            let apiKey = try KeychainManager.shared.getApiKey()
            if let apiKey = apiKey, !apiKey.isEmpty {
                print("✅ CloudflareService: API key found (length: \(apiKey.count))")
                return apiKey
            } else {
                print("❌ CloudflareService: API key is empty or nil")
                throw CloudflareError.noApiKey
            }
        } catch {
            print("❌ CloudflareService: Error retrieving API key: \(error)")
            throw error
        }
    }
    
    private init() {}
    
    func fetchAccounts() async throws -> [CFAccount] {
        print("🌐 CloudflareService: Starting fetchAccounts...")
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🌐 CloudflareService: Making request to \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ CloudflareService: Invalid response type")
            throw CloudflareError.invalidResponse
        }
        
        print("🌐 CloudflareService: Got response with status code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ CloudflareService: Bad status code. Response: \(responseString)")
            throw CloudflareError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let accountsResponse = try JSONDecoder().decode(AccountsResponse.self, from: data)
            if !accountsResponse.success {
                print("❌ CloudflareService: API returned success=false. Errors: \(accountsResponse.errors)")
                throw CloudflareError.apiError(accountsResponse.errors)
            }
            print("✅ CloudflareService: Successfully fetched \(accountsResponse.result.count) accounts")
            return accountsResponse.result
        } catch {
            print("❌ CloudflareService: JSON decode error: \(error)")
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("📄 CloudflareService: Response body: \(responseString)")
            throw error
        }
    }
    
    func fetchWorkers(accountId: String) async throws -> [Worker] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        // Debug print: show the raw JSON response
        let responseString = String(data: data, encoding: .utf8) ?? ""
        print("Raw workers response: \(responseString)")
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudflareError.invalidResponse
        }
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
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
        let (data, response) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
        let projectsResponse = try decoder.decode(PagesProjectsResponse.self, from: data)
        if !projectsResponse.success {
            throw CloudflareError.apiError(projectsResponse.errors)
        }
        return projectsResponse.result
    }
    
    
    func fetchPagesDeployments(accountId: String, projectName: String, limit: Int = 10) async throws -> [PagesDeployment] {
        let apiKey = try getApiKey()
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/pages/projects/\(projectName)/deployments?limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
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
    
    func fetchLatestWorkerDeployment(accountId: String, scriptName: String) async throws -> WorkerDeployment? {
        let apiKey = try getApiKey()
        // Add limit parameter to only get the latest deployment
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts/\(scriptName)/deployments?limit=1")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ Worker deployments API returned status: \(statusCode)")
            throw CloudflareError.invalidResponse
        }
        
        let decoder = createJSONDecoder()
        do {
            let deploymentsResponse = try decoder.decode(WorkerDeploymentsResponse.self, from: data)
            if !deploymentsResponse.success {
                print("❌ Worker deployments API returned success=false: \(deploymentsResponse.errors)")
                throw CloudflareError.apiError(deploymentsResponse.errors)
            }
            // Return only the latest (first) deployment
            return deploymentsResponse.result.deployments.first
        } catch {
            print("❌ Failed to decode worker deployments response: \(error)")
            // Debug output only for first attempt to avoid spam
            if scriptName.contains("demo") {
                let responseString = String(data: data, encoding: .utf8) ?? ""
                print("📄 Raw response: \(responseString)")
            }
            throw error
        }
    }
    
    func fetchBuildHistoryForWorkers(_ workers: [Worker], accountId: String) async throws -> [BuildStatus] {
        var buildStatuses: [BuildStatus] = []
        
        // Fetch latest deployment status for each visible worker
        for worker in workers where worker.isVisible {
            do {
                if let latestDeployment = try await fetchLatestWorkerDeployment(accountId: accountId, scriptName: worker.id) {
                    let status = latestDeployment.toBuildStatus(workerName: worker.id)
                    buildStatuses.append(status)
                    print("✅ Got latest deployment for worker: \(worker.id)")
                } else {
                    print("⚠️ No deployments found for worker \(worker.id), using fallback")
                    let status = worker.toBuildStatus()
                    buildStatuses.append(status)
                }
            } catch {
                // Continue with other workers if one fails, use fallback
                print("❌ Failed to fetch deployment for worker \(worker.id): \(error)")
                let status = worker.toBuildStatus()
                buildStatuses.append(status)
            }
        }
        
        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchBuildHistoryForPages(_ projects: [PagesProject], accountId: String) async throws -> [BuildStatus] {
        var buildStatuses: [BuildStatus] = []
        
        // Fetch latest deployment for each visible pages project
        for project in projects where project.isVisible {
            do {
                let deployments = try await fetchPagesDeployments(accountId: accountId, projectName: project.name, limit: 1)
                if let latestDeployment = deployments.first {
                    let status = latestDeployment.toBuildStatus(projectName: project.name)
                    buildStatuses.append(status)
                }
            } catch {
                // Continue with other projects if one fails
                print("Failed to fetch deployments for pages project \(project.name): \(error)")
            }
        }
        
        return buildStatuses.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
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