import Foundation

enum BuildDestination {
    static func dashboardURL(for build: BuildStatus, accountId: String) -> URL? {
        let urlString: String

        if build.projectType == .worker {
            if let buildId = build.deploymentId, build.branch != "wrangler" {
                urlString = "https://dash.cloudflare.com/\(accountId)/workers/services/view/\(build.projectName)/production/builds/\(buildId)"
            } else {
                urlString = "https://dash.cloudflare.com/\(accountId)/workers/services/view/\(build.projectName)/production"
            }
        } else if let deploymentId = build.deploymentId {
            urlString = "https://dash.cloudflare.com/\(accountId)/pages/view/\(build.projectName)/\(deploymentId)"
        } else {
            urlString = "https://dash.cloudflare.com/\(accountId)/pages/view/\(build.projectName)"
        }

        return URL(string: urlString)
    }
}
