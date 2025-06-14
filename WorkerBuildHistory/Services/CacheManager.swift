import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    private let userDefaults = UserDefaults.standard
    private let cacheQueue = DispatchQueue(label: "cache.queue", qos: .utility)
    
    // Cache keys
    private let buildHistoryKey = "cached_build_history"
    private let lastUpdatedKey = "last_updated_timestamps"
    private let cacheTimestampKey = "cache_timestamp"
    
    // Cache settings
    private let maxCacheAge: TimeInterval = 3600 // 1 hour max cache age
    private let recentUpdateThreshold: TimeInterval = 300 // 5 minutes for "recent"
    private let frequentPollInterval: TimeInterval = 30 // 30 seconds for recent items
    private let normalPollInterval: TimeInterval = 300 // 5 minutes for older items
    
    private init() {}
    
    // MARK: - Build History Cache
    
    func getCachedBuildHistory() -> [BuildStatus]? {
        guard let data = userDefaults.data(forKey: buildHistoryKey),
              let buildHistory = try? JSONDecoder().decode([BuildStatus].self, from: data) else {
            print("📄 CacheManager: No cached build history found")
            return nil
        }
        
        let cacheTimestamp = userDefaults.double(forKey: cacheTimestampKey)
        let cacheAge = Date().timeIntervalSince1970 - cacheTimestamp
        
        if cacheAge > maxCacheAge {
            print("⏰ CacheManager: Cache expired (age: \(Int(cacheAge))s)")
            return nil
        }
        
        print("✅ CacheManager: Loaded \(buildHistory.count) cached items (age: \(Int(cacheAge))s)")
        return buildHistory
    }
    
    func cacheBuildHistory(_ buildHistory: [BuildStatus]) {
        cacheQueue.async {
            do {
                let data = try JSONEncoder().encode(buildHistory)
                self.userDefaults.set(data, forKey: self.buildHistoryKey)
                self.userDefaults.set(Date().timeIntervalSince1970, forKey: self.cacheTimestampKey)
                
                // Update last updated timestamps for each project
                var timestamps: [String: TimeInterval] = self.userDefaults.dictionary(forKey: self.lastUpdatedKey) as? [String: TimeInterval] ?? [:]
                let now = Date().timeIntervalSince1970
                
                for item in buildHistory {
                    timestamps[item.projectName] = now
                }
                
                self.userDefaults.set(timestamps, forKey: self.lastUpdatedKey)
                print("💾 CacheManager: Cached \(buildHistory.count) build history items")
            } catch {
                print("❌ CacheManager: Failed to cache build history: \(error)")
            }
        }
    }
    
    // MARK: - Smart Refresh Logic
    
    func getRefreshPriority(for projectName: String) -> RefreshPriority {
        let timestamps = userDefaults.dictionary(forKey: lastUpdatedKey) as? [String: TimeInterval] ?? [:]
        
        guard let lastUpdated = timestamps[projectName] else {
            return .high // Never updated, high priority
        }
        
        let timeSinceUpdate = Date().timeIntervalSince1970 - lastUpdated
        
        if timeSinceUpdate < recentUpdateThreshold {
            return .high // Recently updated, check frequently
        } else if timeSinceUpdate < recentUpdateThreshold * 4 { // 20 minutes
            return .medium
        } else {
            return .low // Old data, check less frequently
        }
    }
    
    func shouldRefresh(project: String, force: Bool = false) -> Bool {
        if force { return true }
        
        let priority = getRefreshPriority(for: project)
        let timestamps = userDefaults.dictionary(forKey: lastUpdatedKey) as? [String: TimeInterval] ?? [:]
        
        guard let lastUpdated = timestamps[project] else {
            return true // Never updated
        }
        
        let timeSinceUpdate = Date().timeIntervalSince1970 - lastUpdated
        
        switch priority {
        case .high:
            return timeSinceUpdate > frequentPollInterval
        case .medium:
            return timeSinceUpdate > normalPollInterval
        case .low:
            return timeSinceUpdate > normalPollInterval * 2 // 10 minutes
        }
    }
    
    func getProjectsNeedingRefresh(from buildHistory: [BuildStatus], force: Bool = false) -> Set<String> {
        var projectsToRefresh = Set<String>()
        
        for item in buildHistory {
            if shouldRefresh(project: item.projectName, force: force) {
                projectsToRefresh.insert(item.projectName)
            }
        }
        
        return projectsToRefresh
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        userDefaults.removeObject(forKey: buildHistoryKey)
        userDefaults.removeObject(forKey: lastUpdatedKey)
        userDefaults.removeObject(forKey: cacheTimestampKey)
        print("🗑️ CacheManager: Cache cleared")
    }
    
    func getCacheStats() -> CacheStats {
        let cacheTimestamp = userDefaults.double(forKey: cacheTimestampKey)
        let cacheAge = cacheTimestamp > 0 ? Date().timeIntervalSince1970 - cacheTimestamp : 0
        let timestamps = userDefaults.dictionary(forKey: lastUpdatedKey) as? [String: TimeInterval] ?? [:]
        
        return CacheStats(
            hasCachedData: userDefaults.data(forKey: buildHistoryKey) != nil,
            cacheAge: cacheAge,
            projectCount: timestamps.count,
            oldestUpdate: timestamps.values.min().map { Date().timeIntervalSince1970 - $0 } ?? 0
        )
    }
}

// MARK: - Supporting Types

enum RefreshPriority {
    case high   // Recently updated projects (30s intervals)
    case medium // Moderately old projects (5min intervals) 
    case low    // Old projects (10min intervals)
}

struct CacheStats {
    let hasCachedData: Bool
    let cacheAge: TimeInterval
    let projectCount: Int
    let oldestUpdate: TimeInterval
    
    var description: String {
        if !hasCachedData {
            return "No cached data"
        }
        return "Cache: \(Int(cacheAge))s old, \(projectCount) projects tracked"
    }
}