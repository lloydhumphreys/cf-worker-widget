import AppKit
import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private let userDefaults = UserDefaults.standard
    private let lastKnownStatusKey = "last_known_build_status"
    private let buildStatusCategoryIdentifier = "build_status_category"
    private let openBuildActionIdentifier = "open_build"
    
    private override init() {
        super.init()
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerNotificationActions()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DiagnosticsManager.shared.log(.info, category: "notifications", message: "Notification permission granted")
            } else {
                if let error {
                    DiagnosticsManager.shared.recordError(error, category: "notifications", message: "Notification permission request failed")
                } else {
                    DiagnosticsManager.shared.log(.warning, category: "notifications", message: "Notification permission denied")
                }
            }
        }
    }
    
    // MARK: - Build Status Tracking
    
    func checkForBuildStatusChanges(_ newBuildHistory: [BuildStatus], accountId: String) {
        let previousStatuses = getLastKnownStatuses()

        // First load — save baseline without notifying
        if previousStatuses.isEmpty {
            saveLastKnownStatuses(newBuildHistory)
            return
        }

        var newFailures: [BuildStatus] = []
        var recoveries: [BuildStatus] = []

        for build in newBuildHistory {
            let buildKey = "\(build.projectName)_\(build.projectType.rawValue)"
            let previousStatus = previousStatuses[buildKey]

            if build.status == .failure && previousStatus != .failure {
                newFailures.append(build)
            } else if build.status == .success && previousStatus == .failure {
                recoveries.append(build)
            }
        }

        for failure in newFailures {
            sendBuildFailureNotification(failure, accountId: accountId)
        }

        for recovery in recoveries {
            sendBuildRecoveredNotification(recovery, accountId: accountId)
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
    
    private func sendBuildFailureNotification(_ build: BuildStatus, accountId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Failed"
        content.body = notificationBody(for: build, suffix: "failed")
        content.sound = .default
        content.categoryIdentifier = buildStatusCategoryIdentifier
        content.userInfo = buildUserInfo(for: build, accountId: accountId)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "build_failure_\(build.projectName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Send immediately
        )
        
        // Send notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DiagnosticsManager.shared.recordError(error, category: "notifications", message: "Failed to send build failure notification")
            } else {
                DiagnosticsManager.shared.log(
                    .info,
                    category: "notifications",
                    message: "Sent build failure notification",
                    metadata: ["project": build.projectName]
                )
            }
        }
    }

    private func sendBuildRecoveredNotification(_ build: BuildStatus, accountId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Recovered"
        content.body = notificationBody(for: build, suffix: "is back to green")
        content.sound = .default
        content.categoryIdentifier = buildStatusCategoryIdentifier
        content.userInfo = buildUserInfo(for: build, accountId: accountId)
        
        let request = UNNotificationRequest(
            identifier: "build_recovered_\(build.projectName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DiagnosticsManager.shared.recordError(error, category: "notifications", message: "Failed to send build recovery notification")
            } else {
                DiagnosticsManager.shared.log(
                    .info,
                    category: "notifications",
                    message: "Sent build recovery notification",
                    metadata: ["project": build.projectName]
                )
            }
        }
    }
    
    // MARK: - Settings
    
    func clearStoredStatuses() {
        userDefaults.removeObject(forKey: lastKnownStatusKey)
        DiagnosticsManager.shared.log(.info, category: "notifications", message: "Cleared stored build statuses")
    }

    // MARK: - Notification Actions

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.actionIdentifier == openBuildActionIdentifier || response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }

        guard let urlString = response.notification.request.content.userInfo["build_url"] as? String,
              let url = URL(string: urlString) else {
            DiagnosticsManager.shared.log(.warning, category: "notifications", message: "Notification action missing build URL")
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func registerNotificationActions() {
        let openBuildAction = UNNotificationAction(
            identifier: openBuildActionIdentifier,
            title: "Open Build"
        )

        let category = UNNotificationCategory(
            identifier: buildStatusCategoryIdentifier,
            actions: [openBuildAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func buildUserInfo(for build: BuildStatus, accountId: String) -> [String: String] {
        guard let url = BuildDestination.dashboardURL(for: build, accountId: accountId) else {
            return [:]
        }

        return ["build_url": url.absoluteString]
    }

    private func notificationBody(for build: BuildStatus, suffix: String) -> String {
        var body = "\(build.projectName) (\(build.projectType.rawValue)) \(suffix)"

        if let branch = build.branch {
            body += " on \(branch)"
        }

        return body
    }
}
