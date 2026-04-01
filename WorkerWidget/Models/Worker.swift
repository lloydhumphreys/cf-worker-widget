import Foundation

struct Worker: Identifiable, Codable {
    let id: String
    let tag: String?
    let created_on: Date
    let modified_on: Date
    var isVisible: Bool = true

    enum CodingKeys: String, CodingKey {
        case id
        case tag
        case created_on
        case modified_on
        // isVisible is intentionally omitted from CodingKeys
    }
}

// Response wrapper for Cloudflare API
struct WorkersResponse: Codable {
    let success: Bool
    let result: [Worker]
    let errors: [APIError]
}

struct APIError: Codable {
    let code: Int
    let message: String
}

// Extension to convert Worker to BuildStatus
extension Worker {
    func toBuildStatus() -> BuildStatus {
        return BuildStatus(
            id: self.id,
            projectId: self.id,
            projectName: self.id,
            projectType: .worker,
            status: .success, // Workers are considered "deployed" if they exist
            createdAt: self.created_on,
            completedAt: self.modified_on,
            environment: "production",
            deploymentId: nil,
            commitHash: nil, // Workers don't expose git commit info easily
            branch: nil,
            commitMessage: nil
        )
    }
} 