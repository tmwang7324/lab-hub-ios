// Logging for Lab Hub. Everything logs through `LabHubLog`, so one place decides where lines go.
//
// RULES (these protect the private-block rule, ADR 0003, and the GitHub token):
//   1. Never log plan text (a block's task, priority or done test). Log block ids (`2026-11-20#1`).
//   2. Never log a secret's value. Log that it is set, how long it is, and what it starts with.
//
// Where to read the output:
//   - Xcode: the debug console while the app runs.
//   - Console.app: filter by subsystem `com.labhub.core` (and a category such as `feed`).
//   - Terminal: set LABHUB_LOG_STDERR=1 to also print every line to stderr.

import Foundation
import os

public enum LogLevel: Int, Comparable, Sendable, CaseIterable {
    case debug, info, warning, error

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        }
    }
}

/// What part of the app a line is about. Use it to filter in Console.app.
public enum LogCategory: String, Sendable, CaseIterable {
    case feed       // decoding feed.json
    case moment     // resolving the Moment
    case config     // reading Secrets.xcconfig values
    case network    // fetching the feed (not built yet)
    case push       // APNs tokens and pushes (not built yet)
}

public struct LogEntry: Equatable, Sendable {
    public let level: LogLevel
    public let category: LogCategory
    public let message: String

    public init(level: LogLevel, category: LogCategory, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }

    /// One readable line, e.g. `[ERROR] [feed] feed decode failed: ...`.
    public var formatted: String { "[\(level.label)] [\(category.rawValue)] \(message)" }
}

/// Somewhere log lines go.
public protocol LogSink: Sendable {
    func write(_ entry: LogEntry)
}

/// Apple's unified log. `privacy: .public` is needed or release builds show every message as `<private>`.
/// That is safe here because of rule 1 and 2 above.
public struct OSLogSink: LogSink {
    public static let subsystem = "com.labhub.core"

    public init() {}

    public func write(_ entry: LogEntry) {
        let logger = Logger(subsystem: Self.subsystem, category: entry.category.rawValue)
        switch entry.level {
        case .debug: logger.debug("\(entry.message, privacy: .public)")
        case .info: logger.info("\(entry.message, privacy: .public)")
        case .warning: logger.warning("\(entry.message, privacy: .public)")
        case .error: logger.error("\(entry.message, privacy: .public)")
        }
    }
}

/// Prints each line to stderr, with a timestamp. Handy in a terminal.
public struct StderrSink: LogSink {
    public init() {}

    public func write(_ entry: LogEntry) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let stamp = formatter.string(from: Date())
        FileHandle.standardError.write(Data("\(stamp) \(entry.formatted)\n".utf8))
    }
}

public struct LabHubLog: Sendable {
    public let minimumLevel: LogLevel
    private let sinks: [any LogSink]

    public init(minimumLevel: LogLevel = .debug, sinks: [any LogSink]) {
        self.minimumLevel = minimumLevel
        self.sinks = sinks
    }

    /// The log the app uses. Always writes to the unified log; also to stderr when `LABHUB_LOG_STDERR=1`.
    public static let shared: LabHubLog = {
        var sinks: [any LogSink] = [OSLogSink()]
        if ProcessInfo.processInfo.environment["LABHUB_LOG_STDERR"] == "1" { sinks.append(StderrSink()) }
        return LabHubLog(sinks: sinks)
    }()

    public func log(_ level: LogLevel, _ category: LogCategory, _ message: @autoclosure () -> String) {
        guard level >= minimumLevel, !sinks.isEmpty else { return }
        let entry = LogEntry(level: level, category: category, message: message())
        for sink in sinks { sink.write(entry) }
    }

    public func debug(_ category: LogCategory, _ message: @autoclosure () -> String) { log(.debug, category, message()) }
    public func info(_ category: LogCategory, _ message: @autoclosure () -> String) { log(.info, category, message()) }
    public func warning(_ category: LogCategory, _ message: @autoclosure () -> String) { log(.warning, category, message()) }
    public func error(_ category: LogCategory, _ message: @autoclosure () -> String) { log(.error, category, message()) }
}
