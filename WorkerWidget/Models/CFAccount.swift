import Foundation

struct CFAccount: Identifiable, Codable, Hashable {
    let id: String
    let name: String
}

struct AccountsResponse: Codable {
    let result: [CFAccount]
    let success: Bool
    let errors: [APIError]
} 