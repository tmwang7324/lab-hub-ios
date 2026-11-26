import Foundation
import Testing
@testable import LabHubCore

// What the app logs when it decodes and resolves. The goal: when something goes wrong on a phone,
// the log says what and where, without ever containing plan text.

@Suite("Diagnostics: feed")
struct FeedDiagnosticsTests {
    @Test("a good decode logs the schema version and how much it found")
    func decodeSuccess() throws {
        let recorder = LogRecorder()
        _ = try Feed.decode(Fixture.data("feed-2026-11-20"), log: recorder.log)

        let line = try #require(recorder.messages(.info, .feed).first)
        #expect(line.contains("version=1"))
        #expect(line.contains("plans=2"))
        #expect(line.contains("blocks=9"))
        #expect(line.contains("2026-11-19") && line.contains("2026-11-20"))
    }

    @Test("a decode failure is logged as an error that names the field that broke")
    func decodeFailureNamesField() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["kind"] = "meeting" }
        let recorder = LogRecorder()

        #expect(throws: (any Error).self) { try Feed.decode(data, log: recorder.log) }

        let line = try #require(recorder.messages(.error, .feed).first)
        #expect(line.contains("days[1].blocks[0].kind"))
        #expect(recorder.messages(.info, .feed).isEmpty, "a failed decode must not also claim success")
    }

    @Test("data that is not JSON is logged as an error with its size")
    func notJSON() {
        let recorder = LogRecorder()
        #expect(throws: (any Error).self) { try Feed.decode(Data("<html>404</html>".utf8), log: recorder.log) }
        let line = recorder.messages(.error, .feed).first
        #expect(line?.contains("16 bytes") == true)
    }

    @Test("empty data says it is empty, which usually means the download failed")
    func emptyData() {
        let recorder = LogRecorder()
        #expect(throws: (any Error).self) { try Feed.decode(Data(), log: recorder.log) }
        #expect(recorder.messages(.error, .feed).first?.contains("empty") == true)
    }

    @Test("a schema version newer than the decoder knows is a warning, not a failure")
    func newerVersion() throws {
        let data = try Fixture.mutated("feed-2026-11-20") { $0["version"] = 2 }
        let recorder = LogRecorder()

        let feed = try Feed.decode(data, log: recorder.log)

        #expect(feed.version == 2)
        #expect(recorder.messages(.warning, .feed).first?.contains("version 2") == true)
    }

    @Test("the current schema version raises no warning")
    func currentVersionIsQuiet() throws {
        let recorder = LogRecorder()
        _ = try Feed.decode(Fixture.data("feed-2026-11-20"), log: recorder.log)
        #expect(recorder.messages(.warning).isEmpty)
    }
}

@Suite("Diagnostics: moment")
struct MomentDiagnosticsTests {
    @Test("resolving logs which block id is current and its kind, not its text")
    func logsCurrentBlock() throws {
        let recorder = LogRecorder()
        _ = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:00"), log: recorder.log)

        let line = try #require(recorder.messages(.info, .moment).first)
        #expect(line.contains("2026-11-20#1"))
        #expect(line.contains("work"))
        #expect(!line.contains("Task 1"))
    }

    @Test("a break is logged as a break")
    func logsBreak() throws {
        let recorder = LogRecorder()
        _ = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-10 13:30"), log: recorder.log)
        #expect(recorder.messages(.info, .moment).first?.contains("break") == true)
    }

    @Test("when no block is current the log says so")
    func logsNoCurrent() throws {
        let recorder = LogRecorder()
        _ = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 12:00"), log: recorder.log)
        #expect(recorder.messages(.info, .moment).first?.contains("no block is current") == true)
    }

    @Test("waiting logs the Next block's id, not its text")
    func logsNextBlock() throws {
        let recorder = LogRecorder()
        _ = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:35"), log: recorder.log)

        let line = try #require(recorder.messages(.info, .moment).first)
        #expect(line.contains("waiting for 2026-11-20#2"))
        #expect(!line.contains("Task 2"))
    }

    @Test("blocks that overlap are a warning that names both ids")
    func overlapWarns() throws {
        // Nov 9 plan: blocks 5 and 6 overlap between 21:40 and 23:10.
        let recorder = LogRecorder()
        _ = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-09 22:00"), log: recorder.log)

        let line = try #require(recorder.messages(.warning, .moment).first)
        #expect(line.contains("2026-11-09#5") && line.contains("2026-11-09#6"))
    }

    @Test("a feed that fails to decode logs the error once and still throws")
    func failureIsLoggedOnce() {
        let recorder = LogRecorder()
        #expect(throws: (any Error).self) {
            try Moment.resolve(feedData: Data("nope".utf8), at: ny("2026-11-20 10:00"), log: recorder.log)
        }
        #expect(recorder.messages(.error).count == 1)
    }

    @Test("no log line ever contains plan text, at any minute of any fixture", arguments: [
        "feed-2026-11-10", "feed-2026-11-20", "feed-2026-11-23",
    ])
    func neverLogsPlanText(fixture: String) throws {
        let data = try Fixture.data(fixture)
        let feed = try Feed.decode(data, log: LabHubLog(sinks: []))
        let texts = Set(feed.plans.flatMap(\.blocks).flatMap { [$0.task, $0.priority, $0.doneTest] })
        #expect(!texts.isEmpty)

        let recorder = LogRecorder()
        let first = feed.plans.flatMap(\.blocks).map(\.start).min()!
        // Every 7 minutes over three days covers every block.
        for step in stride(from: 0.0, through: 72 * 3600, by: 7 * 60) {
            _ = try Moment.resolve(feedData: data, at: first.addingTimeInterval(step - 3600), log: recorder.log)
        }

        let everything = recorder.entries.map(\.message).joined(separator: "\n")
        for text in texts {
            #expect(!everything.contains(text), "log leaked plan text: \(text)")
        }
    }
}
