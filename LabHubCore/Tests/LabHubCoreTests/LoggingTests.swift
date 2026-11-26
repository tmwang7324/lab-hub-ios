import Foundation
import Testing
@testable import LabHubCore

// The logging layer itself (unit level). What the app logs is tested in DiagnosticsTests.

@Suite("Logging")
struct LoggingTests {
    @Test("an entry reaches every sink with its level, category and message")
    func fansOutToSinks() {
        let a = LogRecorder(), b = LogRecorder()
        let log = LabHubLog(minimumLevel: .debug, sinks: [a, b])

        log.error(.feed, "boom")

        #expect(a.entries == [LogEntry(level: .error, category: .feed, message: "boom")])
        #expect(b.entries == a.entries)
    }

    @Test("entries below the minimum level are dropped", arguments: [
        (LogLevel.info, [LogLevel.info, .warning, .error]),
        (LogLevel.warning, [LogLevel.warning, .error]),
        (LogLevel.error, [LogLevel.error]),
        (LogLevel.debug, [LogLevel.debug, .info, .warning, .error]),
    ])
    func minimumLevel(minimum: LogLevel, kept: [LogLevel]) {
        let recorder = LogRecorder()
        let log = LabHubLog(minimumLevel: minimum, sinks: [recorder])

        log.debug(.feed, "d"); log.info(.feed, "i"); log.warning(.feed, "w"); log.error(.feed, "e")

        #expect(recorder.entries.map(\.level) == kept)
    }

    @Test("a dropped entry's message is never built")
    func droppedMessageIsLazy() {
        let log = LabHubLog(minimumLevel: .error, sinks: [LogRecorder()])
        var built = false
        log.debug(.feed, { built = true; return "expensive" }())
        #expect(built == false)
    }

    @Test("the formatted line names level, category and message")
    func formatting() {
        let line = LogEntry(level: .warning, category: .config, message: "GITHUB_TOKEN is empty").formatted
        #expect(line == "[WARNING] [config] GITHUB_TOKEN is empty")
    }

    @Test("a log with no sinks is harmless")
    func noSinks() {
        LabHubLog(minimumLevel: .debug, sinks: []).error(.feed, "nobody is listening")
    }

    @Test("the shared log exists and accepts entries without crashing")
    func sharedLog() {
        LabHubLog.shared.debug(.feed, "shared log smoke test")
    }
}
