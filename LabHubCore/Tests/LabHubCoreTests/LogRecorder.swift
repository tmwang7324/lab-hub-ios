import Foundation
import os
@testable import LabHubCore

/// A log sink that remembers everything, so tests can check what was logged.
final class LogRecorder: LogSink, @unchecked Sendable {
    private let store = OSAllocatedUnfairLock(initialState: [LogEntry]())

    var entries: [LogEntry] { store.withLock { $0 } }
    func write(_ entry: LogEntry) { store.withLock { $0.append(entry) } }

    /// A log wired to this recorder, at the most detailed level.
    var log: LabHubLog { LabHubLog(minimumLevel: .debug, sinks: [self]) }

    func messages(_ level: LogLevel? = nil, _ category: LogCategory? = nil) -> [String] {
        entries
            .filter { (level == nil || $0.level == level) && (category == nil || $0.category == category) }
            .map(\.message)
    }
}
