import Foundation

// Unified build status model that can represent both Worker deployments and Pages builds
struct BuildStatus: Identifiable, Codable {
    let id: String
    let projectId: String
    let projectName: String
    let projectType: ProjectType
    let status: BuildStatusType
    let createdAt: Date
    let completedAt: Date?
    let environment: String?
    let deploymentId: String?
    let commitHash: String?
    let branch: String?
    let commitMessage: String?
    
    enum ProjectType: String, Codable, CaseIterable {
        case worker = "worker"
        case pages = "pages"
    }
    
    enum BuildStatusType: String, Codable, CaseIterable {
        case success = "success"
        case failure = "failure"
        case inProgress = "active"
        case canceled = "canceled"
        case queued = "queued"
        
        var displayName: String {
            switch self {
            case .success: return "Success"
            case .failure: return "Failed"
            case .inProgress: return "Building"
            case .canceled: return "Canceled"
            case .queued: return "Queued"
            }
        }
        
        func displayName(for projectType: ProjectType) -> String {
            switch (self, projectType) {
            case (.success, .worker): return "Deployed"
            case (.success, .pages): return "Success"
            case (.failure, .worker): return "Failed"
            case (.failure, .pages): return "Failed"
            case (.inProgress, .worker): return "Rolling Out"
            case (.inProgress, .pages): return "Building"
            case (.canceled, _): return "Canceled"
            case (.queued, .worker): return "Pending"
            case (.queued, .pages): return "Queued"
            }
        }
        
        var isComplete: Bool {
            switch self {
            case .success, .failure, .canceled:
                return true
            case .inProgress, .queued:
                return false
            }
        }
    }
}


// Pages deployment model from Cloudflare API
struct PagesDeployment: Codable {
    let id: String
    let url: String
    let environment: String
    let created_on: Date
    let modified_on: Date
    let latest_stage: DeploymentStage
    let deployment_trigger: DeploymentTrigger
    
    struct DeploymentStage: Codable {
        let name: String
        let status: String
        let started_on: Date?
        let ended_on: Date?
    }
    
    struct DeploymentTrigger: Codable {
        let type: String
        let metadata: TriggerMetadata?
        
        struct TriggerMetadata: Codable {
            let branch: String?
            let commit_hash: String?
            let commit_message: String?
        }
    }
}

// Worker deployment models from Cloudflare API (based on actual response)
struct WorkerDeployment: Codable {
    let id: String
    let source: String
    let strategy: String
    let author_email: String
    let annotations: [String: String]
    let versions: [WorkerVersion]
    let created_on: Date
}

struct WorkerVersion: Codable {
    let version_id: String
    let percentage: Int
}

// API Response wrappers - matches actual response structure
struct WorkerDeploymentsResponse: Codable {
    let success: Bool
    let result: WorkerDeploymentContainer
    let errors: [APIError]
    let messages: [String]
}

struct WorkerDeploymentContainer: Codable {
    let deployments: [WorkerDeployment]
}

struct PagesDeploymentsResponse: Codable {
    let success: Bool
    let result: [PagesDeployment]
    let errors: [APIError]
}

// Workers Builds API models
struct WorkerBuild: Codable {
    let build_uuid: String
    let status: String
    let build_outcome: String?
    let created_on: String
    let stopped_on: String?
    let trigger: WorkerBuildTrigger?
    let build_trigger_metadata: WorkerBuildTriggerMetadata?
}

struct WorkerBuildTrigger: Codable {
    let trigger_name: String?
    let branch_includes: [String]?
    let repo_connection: WorkerBuildRepoConnection?
    let build_trigger_metadata: WorkerBuildTriggerMetadata?
}

struct WorkerBuildRepoConnection: Codable {
    let repo_name: String?
    let provider_type: String?
}

struct WorkerBuildTriggerMetadata: Codable {
    let branch: String?
    let commit_hash: String?
    let commit_message: String?
}

struct WorkerBuildsResponse: Codable {
    let success: Bool
    let result: [WorkerBuild]
    let errors: [APIError]
}

extension WorkerBuild {
    func toBuildStatus(workerName: String) -> BuildStatus {
        let buildStatus: BuildStatus.BuildStatusType
        let outcome = build_outcome?.lowercased() ?? ""
        let st = status.lowercased()

        if outcome == "failure" || st == "failed" {
            buildStatus = .failure
        } else if outcome == "success" {
            buildStatus = .success
        } else if outcome == "canceled" || st == "canceled" {
            buildStatus = .canceled
        } else if st == "running" || st == "building" || st == "initializing" {
            buildStatus = .inProgress
        } else if st == "queued" || st == "pending" {
            buildStatus = .queued
        } else if st == "stopped" {
            // Stopped without a recognized outcome — likely superseded by a newer build
            buildStatus = .canceled
        } else {
            buildStatus = .queued
        }

        let created = Self.parseDate(from: created_on) ?? Date()
        let completed = stopped_on.flatMap { Self.parseDate(from: $0) }

        // Git metadata — check top-level first, then nested in trigger
        let metadata = build_trigger_metadata ?? trigger?.build_trigger_metadata
        let branch = metadata?.branch ?? trigger?.branch_includes?.first
        let commitHash = metadata?.commit_hash
        let commitMessage = metadata?.commit_message

        return BuildStatus(
            id: build_uuid,
            projectId: workerName,
            projectName: workerName,
            projectType: .worker,
            status: buildStatus,
            createdAt: created,
            completedAt: buildStatus.isComplete ? (completed ?? created) : nil,
            environment: "production",
            deploymentId: build_uuid,
            commitHash: commitHash,
            branch: branch,
            commitMessage: commitMessage ?? "Build \(outcome)"
        )
    }

    private static func parseDate(from dateString: String) -> Date? {
        let iso8601Fractional = ISO8601DateFormatter()
        iso8601Fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Fractional.date(from: dateString) {
            return date
        }
        let iso8601 = ISO8601DateFormatter()
        return iso8601.date(from: dateString)
    }
}

// Extensions to convert API models to unified BuildStatus
extension WorkerDeployment {
    func toBuildStatus(workerName: String) -> BuildStatus {
        // Get the primary version (should be 100% in most cases)
        let primaryVersion = versions.first { $0.percentage == 100 } ?? versions.first
        
        // Determine status based on deployment strategy and version percentages
        let deploymentStatus: BuildStatus.BuildStatusType
        
        if strategy.lowercased() == "percentage" && versions.allSatisfy({ $0.percentage == 100 }) {
            deploymentStatus = .success // Fully deployed
        } else if strategy.lowercased() == "percentage" && versions.contains(where: { $0.percentage < 100 }) {
            deploymentStatus = .inProgress // Gradual rollout in progress
        } else {
            deploymentStatus = .success // Default to success for active deployments
        }
        
        return BuildStatus(
            id: self.id,
            projectId: primaryVersion?.version_id ?? self.id,
            projectName: workerName,
            projectType: .worker,
            status: deploymentStatus,
            createdAt: self.created_on,
            completedAt: deploymentStatus == .success ? self.created_on : nil,
            environment: "production",
            deploymentId: self.id,
            commitHash: String(primaryVersion?.version_id.prefix(8) ?? ""),
            branch: self.source,
            commitMessage: self.source == "wrangler" ? "Manually deployed" : (annotations["workers/triggered_by"] ?? "Deployed")
        )
    }
}

extension PagesDeployment {
    func toBuildStatus(projectName: String) -> BuildStatus {
        let status: BuildStatus.BuildStatusType
        let rawStatus = self.latest_stage.status.lowercased()
        
        switch rawStatus {
        case "success":
            status = .success
        case "failure", "failed":
            status = .failure
        case "active", "building", "in_progress", "deploying":
            status = .inProgress
        case "canceled", "cancelled":
            status = .canceled
        default:
            status = .queued
        }
        
        return BuildStatus(
            id: self.id,
            projectId: self.id,
            projectName: projectName,
            projectType: .pages,
            status: status,
            createdAt: self.created_on,
            completedAt: self.latest_stage.ended_on,
            environment: self.environment,
            deploymentId: self.id,
            commitHash: self.deployment_trigger.metadata?.commit_hash,
            branch: self.deployment_trigger.metadata?.branch,
            commitMessage: self.deployment_trigger.metadata?.commit_message
        )
    }
}