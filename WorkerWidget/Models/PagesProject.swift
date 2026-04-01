import Foundation

struct PagesProject: Identifiable, Codable {
    let id: String
    let name: String
    let subdomain: String
    let created_on: Date
    var isVisible: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, name, subdomain, created_on
        // isVisible is local-only
    }
}

struct PagesProjectsResponse: Codable {
    let result: [PagesProject]
    let success: Bool
    let errors: [APIError]
} 