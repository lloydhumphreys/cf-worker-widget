import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private let userDefaults = UserDefaults.standard
    private let lastKnownStatusKey = "last_known_build_status"
    
    private init() {}
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ NotificationManager: Notification permission granted")
            } else {
                print("❌ NotificationManager: Notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    // MARK: - Build Status Tracking
    
    func checkForBuildStatusChanges(_ newBuildHistory: [BuildStatus]) {
        let previousStatuses = getLastKnownStatuses()

        // First load — save baseline without notifying
        if previousStatuses.isEmpty {
            saveLastKnownStatuses(newBuildHistory)
            return
        }

        var newFailures: [BuildStatus] = []

        for build in newBuildHistory {
            let buildKey = "\(build.projectName)_\(build.projectType.rawValue)"
            let previousStatus = previousStatuses[buildKey]

            if build.status == .failure && previousStatus != .failure {
                newFailures.append(build)
            }
        }

        for failure in newFailures {
            sendBuildFailureNotification(failure)
        }

        saveLastKnownStatuses(newBuildHistory)
    }
    
    private func getLastKnownStatuses() -> [String: BuildStatus.BuildStatusType] {
        guard let data = userDefaults.data(forKey: lastKnownStatusKey),
              let statuses = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        
        var result: [String: BuildStatus.BuildStatusType] = [:]
        for (key, value) in statuses {
            if let status = BuildStatus.BuildStatusType(rawValue: value) {
                result[key] = status
            }
        }
        return result
    }
    
    private func saveLastKnownStatuses(_ buildHistory: [BuildStatus]) {
        var statuses: [String: String] = [:]
        
        for build in buildHistory {
            let buildKey = "\(build.projectName)_\(build.projectType.rawValue)"
            statuses[buildKey] = build.status.rawValue
        }
        
        if let data = try? JSONEncoder().encode(statuses) {
            userDefaults.set(data, forKey: lastKnownStatusKey)
        }
    }
    
    // MARK: - Notification Sending
    
    private func sendBuildFailureNotification(_ build: BuildStatus) {
        let content = UNMutableNotificationContent()
        content.title = "Build Failed"
        content.body = "\(build.projectName) (\(build.projectType.rawValue)) build has failed"
        content.sound = .default
        
        // Add additional info if available
        if let branch = build.branch {
            content.body += " on \(branch)"
        }
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "build_failure_\(build.projectName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Send immediately
        )
        
        // Send notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ NotificationManager: Failed to send notification: \(error)")
            } else {
                print("✅ NotificationManager: Sent failure notification for \(build.projectName)")
            }
        }
    }
    
    func sendNewBuildNotification(_ build: BuildStatus) {
        let content = UNMutableNotificationContent()
        
        switch build.status {
        case .success:
            content.title = "Build Succeeded"
            content.body = "\(build.projectName) (\(build.projectType.rawValue)) deployed successfully"
        case .failure:
            content.title = "Build Failed"
            content.body = "\(build.projectName) (\(build.projectType.rawValue)) build failed"
        case .inProgress:
            // Don't notify for in-progress builds to avoid spam
            return
        case .canceled:
            content.title = "Build Canceled"
            content.body = "\(build.projectName) (\(build.projectType.rawValue)) build was canceled"
        case .queued:
            // Don't notify for queued builds to avoid spam
            return
        }
        
        content.sound = .default
        
        if let branch = build.branch {
            content.body += " on \(branch)"
        }
        
        let request = UNNotificationRequest(
            identifier: "build_status_\(build.projectName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ NotificationManager: Failed to send notification: \(error)")
            } else {
                print("✅ NotificationManager: Sent notification for \(build.projectName)")
            }
        }
    }
    
    // MARK: - Settings
    
    func clearStoredStatuses() {
        userDefaults.removeObject(forKey: lastKnownStatusKey)
        print("🗑️ NotificationManager: Cleared stored build statuses")
    }
}