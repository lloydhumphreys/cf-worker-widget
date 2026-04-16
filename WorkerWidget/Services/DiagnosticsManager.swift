import Foundation
import OSLog

enum DiagnosticLevel: String, Codable, CaseIterable {
    case info
    case warning
    case error
}

struct DiagnosticEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: DiagnosticLevel
    let category: String
    let message: String
    let metadata: [String: String]
}

final class DiagnosticsManager: ObservableObject {
    static let shared = DiagnosticsManager()

    @Published private(set) var events: [DiagnosticEvent] = []

    private let subsystem = "com.workerwidget"
    private let storageKey = "diagnosticEvents"
    private let maxEvents = 80
    private let userDefaults = UserDefaults.standard

    private init() {
        loadPersistedEvents()
    }

    func log(
        _ level: DiagnosticLevel,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let renderedMessage = render(message: message, metadata: metadata)
        let logger = Logger(subsystem: subsystem, category: category)

        switch level {
        case .info:
            logger.info("\(renderedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(renderedMessage, privacy: .public)")
        case .error:
            logger.error("\(renderedMessage, privacy: .public)")
        }

        let event = DiagnosticEvent(
            id: UUID(),
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )

        DispatchQueue.main.async {
            self.events.insert(event, at: 0)
            self.events = Array(self.events.prefix(self.maxEvents))
            self.persistEvents()
        }
    }

    func recordError(
        _ error: Error,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        var payload = metadata
        payload["error"] = error.localizedDescription
        log(.error, category: category, message: message, metadata: payload)
    }

    func clear() {
        events = []
        userDefaults.removeObject(forKey: storageKey)
    }

    private func loadPersistedEvents() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return
        }

        events = decoded
    }

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func render(message: String, metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return message }

        let details = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        return "\(message) \(details)"
    }
}
