import Foundation

enum AppPreferences {
    private static let userDefaults = UserDefaults.standard

    private static let workerVisibilityKey = "workerVisibilitySettings"
    private static let pagesVisibilityKey = "pagesVisibilitySettings"
    private static let autoRefreshEnabledKey = "autoRefreshEnabled"

    static func applyWorkerVisibility(to workers: inout [Worker]) {
        let savedVisibility = userDefaults.dictionary(forKey: workerVisibilityKey) as? [String: Bool] ?? [:]

        for index in workers.indices {
            if let isVisible = savedVisibility[workers[index].id] {
                workers[index].isVisible = isVisible
            }
        }
    }

    static func applyPagesVisibility(to projects: inout [PagesProject]) {
        let savedVisibility = userDefaults.dictionary(forKey: pagesVisibilityKey) as? [String: Bool] ?? [:]

        for index in projects.indices {
            if let isVisible = savedVisibility[projects[index].id] {
                projects[index].isVisible = isVisible
            }
        }
    }

    static func applyVisibility(workers: inout [Worker], pagesProjects: inout [PagesProject]) {
        applyWorkerVisibility(to: &workers)
        applyPagesVisibility(to: &pagesProjects)
    }

    static func saveVisibilitySettings(workers: [Worker], pagesProjects: [PagesProject]) {
        let workerVisibility = workers.reduce(into: [String: Bool]()) { result, worker in
            result[worker.id] = worker.isVisible
        }

        let pagesVisibility = pagesProjects.reduce(into: [String: Bool]()) { result, project in
            result[project.id] = project.isVisible
        }

        userDefaults.set(workerVisibility, forKey: workerVisibilityKey)
        userDefaults.set(pagesVisibility, forKey: pagesVisibilityKey)
    }

    static var autoRefreshEnabled: Bool {
        get {
            if userDefaults.object(forKey: autoRefreshEnabledKey) == nil {
                return true
            }

            return userDefaults.bool(forKey: autoRefreshEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: autoRefreshEnabledKey)
        }
    }
}
