import Foundation
import Testing
@testable import LabHubCore

// End to end, two ways:
//  1. The real `labhub-moment` program, run as a separate process the way you would run it in a terminal.
//  2. A sweep of every minute of every fixture against an oracle that reads the raw JSON itself.

// MARK: running the real program

struct CLIResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum CLI {
    /// The built `labhub-moment` binary. SwiftPM puts it in the products folder, and the test bundle's
    /// resources are nested inside `LabHubCoreTests.xctest` there, so walk up until we find it.
    static var binary: URL {
        var folder = Bundle.module.bundleURL
        for _ in 0..<8 {
            folder.deleteLastPathComponent()
            let candidate = folder.appendingPathComponent("labhub-moment")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return Bundle.module.bundleURL.appendingPathComponent("labhub-moment-not-found")
    }

    static func fixturePath(_ name: String) throws -> String {
        try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")).path
    }

    static func run(_ arguments: [String]) throws -> CLIResult {
        try #require(FileManager.default.isExecutableFile(atPath: binary.path),
                     "labhub-moment was not built; run `swift build` first")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CLIResult(status: process.terminationStatus,
                         stdout: String(decoding: stdoutData, as: UTF8.self),
                         stderr: String(decoding: stderrData, as: UTF8.self))
    }
}

@Suite("End to end: the labhub-moment program")
struct CommandLineEndToEndTests {
    @Test("inside a work block it prints the block and exits 0")
    func inWorkBlock() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-20T10:00:00-05:00"])
        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("in a block: Task 1 (until 2026-11-20T10:30:00"))
    }

    @Test("inside a break it says so")
    func inBreak() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-10"), "--at", "2026-11-10T13:30:00-05:00"])
        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("in a break: Break 4"))
    }

    @Test("between blocks it says which block is next")
    func waiting() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-20T10:35:00-05:00"])
        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("waiting: next is Task 2 at "))
        #expect(result.stderr.contains("waiting for 2026-11-20#2"))
    }

    @Test("after the last block of a fresh feed it says nothing left")
    func nothingLeft() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-20T12:00:00-05:00"])
        #expect(result.status == 0)
        #expect(result.stdout == "nothing left\n")
    }

    @Test("days later, with nothing left in a stale feed, it says it can't refresh")
    func cantRefresh() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-23T10:00:00-05:00"])
        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("can't refresh"))
        #expect(result.stderr.contains("[WARNING] [moment]"))
        #expect(result.stderr.contains("feed is stale"))
    }

    @Test("an instant given in UTC gives the same answer as one given in New York time")
    func offsets() throws {
        let path = try CLI.fixturePath("feed-2026-11-20")
        let a = try CLI.run([path, "--at", "2026-11-20T10:00:00-05:00"])
        let b = try CLI.run([path, "--at", "2026-11-20T15:00:00Z"])
        #expect(a.stdout == b.stdout)
    }

    @Test("the log on stderr shows what was decoded and which block matched")
    func logOnStderr() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-20T10:00:00-05:00"])
        #expect(result.stderr.contains("[INFO] [feed] feed decoded: version=1 plans=2 blocks=9"))
        #expect(result.stderr.contains("[INFO] [moment]"))
        #expect(result.stderr.contains("2026-11-20#1"))
    }

    @Test("the log never contains the plan text, even though stdout does")
    func logHasNoPlanText() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-20T10:00:00-05:00"])
        #expect(result.stdout.contains("Task 1"))
        #expect(!result.stderr.contains("Task 1"))
    }

    @Test("a private block prints as Busy, and its task appears nowhere in the output")
    func privateBlockIsBusy() throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-20", id: "2026-11-20#1")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("labhub-\(UUID().uuidString).json")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try CLI.run([file.path, "--at", "2026-11-20T10:00:00-05:00"])

        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("in a block: Busy (until "))
        #expect(!result.stdout.contains("Task 1"))
        #expect(!result.stderr.contains("Task 1"))
        #expect(result.stderr.contains("2026-11-20#1 (private)"))
    }

    @Test("--quiet silences the log on success")
    func quiet() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "2026-11-20T10:00:00-05:00", "--quiet"])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
    }

    @Test("a file that is not a feed exits 1 and the log names the problem")
    func notAFeed() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("labhub-\(UUID().uuidString).json")
        try Data("<html>404: Not Found</html>".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try CLI.run([file.path, "--at", "2026-11-20T10:00:00-05:00"])

        #expect(result.status == 1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("[ERROR] [feed] feed decode failed"))
        #expect(result.stderr.contains("27 bytes"))
    }

    @Test("a feed with a broken field exits 1 and the log names the field")
    func brokenField() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["kind"] = "meeting" }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("labhub-\(UUID().uuidString).json")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try CLI.run([file.path, "--at", "2026-11-20T10:00:00-05:00"])

        #expect(result.status == 1)
        #expect(result.stderr.contains("days[1].blocks[0].kind"))
    }

    @Test("a file that does not exist exits 1 and says so")
    func missingFile() throws {
        let result = try CLI.run(["/nonexistent/feed.json"])
        #expect(result.status == 1)
        #expect(result.stderr.contains("can't read feed file '/nonexistent/feed.json'"))
    }

    @Test("a bad --at exits 2 and explains the format")
    func badInstant() throws {
        let result = try CLI.run([CLI.fixturePath("feed-2026-11-20"), "--at", "tomorrow"])
        #expect(result.status == 2)
        #expect(result.stderr.contains("ISO-8601"))
    }

    @Test("no arguments exits 2 and prints usage")
    func noArguments() throws {
        let result = try CLI.run([])
        #expect(result.status == 2)
        #expect(result.stderr.contains("usage: labhub-moment"))
    }

    @Test("--help prints usage and exits 0")
    func help() throws {
        let result = try CLI.run(["--help"])
        #expect(result.status == 0)
        #expect(result.stdout.contains("usage: labhub-moment"))
    }
}

// MARK: sweeping whole days against an independent oracle

/// Knows the answer without using the code under test: it reads the raw JSON and checks each block's
/// times itself. It accepts any matching block, because which one wins on an overlap is not specified.
private struct Oracle {
    struct Row { let start: Date; let end: Date; let displayText: String; let isBreak: Bool }
    let rows: [Row]
    let generatedAt: Date

    init(fixture: String) throws {
        let json = try #require(JSONSerialization.jsonObject(with: Fixture.data(fixture)) as? [String: Any])
        let parse = ISO8601DateFormatter()
        generatedAt = try #require(parse.date(from: json["generated_at"] as! String))
        rows = (json["days"] as! [[String: Any]]).flatMap { day in
            (day["blocks"] as! [[String: Any]]).map { block in
                Row(start: parse.date(from: block["start"] as! String)!,
                    end: parse.date(from: block["end"] as! String)!,
                    // What the lock screen may show: a private block's task never appears.
                    displayText: (block["private"] as? Bool == true) ? "Busy" : block["task"] as! String,
                    isBreak: (block["kind"] as! String) == "break")
            }
        }
    }

    func acceptable(at instant: Date) -> [Moment] {
        let current = rows.filter { $0.start <= instant && instant < $0.end }
            .map { $0.isBreak ? Moment.inBreak(text: $0.displayText, end: $0.end) : .inBlock(text: $0.displayText, end: $0.end) }
        if !current.isEmpty { return current }

        // Nothing current: the Next block is any block (of any plan) that starts soonest after the instant.
        let future = rows.filter { instant < $0.start && $0.start < $0.end }
        guard let soonest = future.map(\.start).min() else {
            // Nothing to come: a feed built more than 26 hours ago can't claim nothing is left.
            let stale = instant.timeIntervalSince(generatedAt) > 26 * 3600
            return [stale ? .cantRefresh : .nothingLeft]
        }
        return future.filter { $0.start == soonest }.map { Moment.waiting(text: $0.displayText, start: $0.start, end: $0.end) }
    }

    /// Every block edge, with one second either side: where mistakes hide.
    var edges: [Date] {
        rows.flatMap { [$0.start, $0.end] }.flatMap { [$0.addingTimeInterval(-1), $0, $0.addingTimeInterval(1)] }
    }
}

@Suite("End to end: sweeping the fixtures")
struct SweepEndToEndTests {
    static let fixtures = ["feed-2026-11-10", "feed-2026-11-20", "feed-2026-11-23"]

    @Test("every minute of every day agrees with the oracle", arguments: fixtures)
    func everyMinute(fixture: String) throws {
        let data = try Fixture.data(fixture)
        let oracle = try Oracle(fixture: fixture)
        let log = LabHubLog(sinks: [])
        let start = try #require(oracle.rows.map(\.start).min()).addingTimeInterval(-6 * 3600)
        let end = try #require(oracle.rows.map(\.end).max()).addingTimeInterval(6 * 3600)

        var checked = 0
        var current = start
        while current <= end {
            try check(data, oracle, at: current, log: log)
            checked += 1
            current = current.addingTimeInterval(60)
        }
        #expect(checked > 500)
    }

    @Test("every block edge, one second either side, agrees with the oracle", arguments: fixtures)
    func everyEdge(fixture: String) throws {
        let data = try Fixture.data(fixture)
        let oracle = try Oracle(fixture: fixture)
        let log = LabHubLog(sinks: [])
        for instant in oracle.edges { try check(data, oracle, at: instant, log: log) }
    }

    @Test("a whole run through a fixture never logs an error", arguments: fixtures)
    func noErrorsLogged(fixture: String) throws {
        let recorder = LogRecorder()
        let oracle = try Oracle(fixture: fixture)
        for instant in oracle.edges { _ = try Moment.resolve(feedData: Fixture.data(fixture), at: instant, log: recorder.log) }
        #expect(recorder.messages(.error).isEmpty)
    }

    private func check(_ data: Data, _ oracle: Oracle, at instant: Date, log: LabHubLog) throws {
        let moment = try Moment.resolve(feedData: data, at: instant, log: log)
        let acceptable = oracle.acceptable(at: instant)
        #expect(acceptable.contains(moment), "at \(instant): got \(moment), oracle allows \(acceptable)")
    }
}
