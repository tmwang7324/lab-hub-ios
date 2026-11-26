import Foundation
import Testing
@testable import LabHubCore

// Integration: the pieces working together through the public entry point (decode + resolve + log),
// reading feed bytes the way the app will (from a file), with no mocks.

@Suite("Integration: feed bytes to Moment")
struct IntegrationTests {
    @Test("bytes read from a file on disk resolve the same as bytes from the bundle")
    func fromDisk() throws {
        let source = try #require(Bundle.module.url(forResource: "feed-2026-11-20", withExtension: "json", subdirectory: "Fixtures"))
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("labhub-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: source, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }

        let moment = try Moment.resolve(feedData: Data(contentsOf: copy), at: ny("2026-11-20 11:25"))
        #expect(moment == .inBlock(text: "Task 3", end: ny("2026-11-20 11:40")))
    }

    @Test("the same instant written with different offsets gives the same Moment")
    func offsetsDoNotMatter() throws {
        // User story 19: blocks are compared as absolute instants, so travelling shifts nothing.
        let parse = ISO8601DateFormatter()
        let newYork = try #require(parse.date(from: "2026-11-20T10:00:00-05:00"))
        let utc = try #require(parse.date(from: "2026-11-20T15:00:00Z"))
        let tokyo = try #require(parse.date(from: "2026-11-21T00:00:00+09:00"))
        let data = try Fixture.data("feed-2026-11-20")

        let answers = try [newYork, utc, tokyo].map { try Moment.resolve(feedData: data, at: $0, log: LabHubLog(sinks: [])) }

        #expect(answers.allSatisfy { $0 == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")) })
    }

    @Test("a decode, then a resolve, leave a log trail in that order")
    func logTrailOrder() throws {
        let recorder = LogRecorder()
        _ = try Moment.resolve(feedData: Fixture.data("feed-2026-11-23"), at: ny("2026-11-23 13:45"), log: recorder.log)

        let categories = recorder.entries.filter { $0.level >= .info }.map(\.category)
        #expect(categories == [.feed, .moment])
        #expect(recorder.entries.last?.message.contains("2026-11-23#3") == true)
    }

    @Test("a feed that fails to decode leaves no Moment log, only the decode error")
    func failedDecodeStopsEarly() {
        let recorder = LogRecorder()
        #expect(throws: (any Error).self) {
            try Moment.resolve(feedData: Data("{}".utf8), at: ny("2026-11-20 10:00"), log: recorder.log)
        }
        #expect(recorder.messages(nil, .moment).isEmpty)
        #expect(recorder.messages(.error, .feed).count == 1)
    }

    @Test("many resolves over one feed are independent of each other")
    func repeatedCallsAreIndependent() throws {
        let data = try Fixture.data("feed-2026-11-10")
        let log = LabHubLog(sinks: [])
        let first = try Moment.resolve(feedData: data, at: ny("2026-11-10 13:30"), log: log)
        _ = try Moment.resolve(feedData: data, at: ny("2026-11-10 23:45"), log: log)
        let again = try Moment.resolve(feedData: data, at: ny("2026-11-10 13:30"), log: log)
        #expect(first == again)
    }

    @Test("resolving concurrently from many tasks is safe and gives consistent answers")
    func concurrentResolves() async throws {
        let data = try Fixture.data("feed-2026-11-20")
        let recorder = LogRecorder()
        let log = recorder.log
        let answers = try await withThrowingTaskGroup(of: Moment?.self) { group in
            for _ in 0..<50 {
                group.addTask { try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00"), log: log) }
            }
            return try await group.reduce(into: [Moment?]()) { $0.append($1) }
        }
        #expect(answers.count == 50)
        #expect(answers.allSatisfy { $0 == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")) })
        #expect(recorder.entries.count == 150, "3 log lines per resolve, none lost")
    }
}
