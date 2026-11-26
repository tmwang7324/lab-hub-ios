import Foundation
import Testing
@testable import LabHubCore

// Ticket #3: the Moment entry point. Feed bytes plus an instant give what the lock screen shows.
// Every test states the fixture and the instant, then checks only what a surface would show.

@Suite("Moment: current block")
struct MomentCurrentBlockTests {
    @Test("inside a work block gives that block's task and end")
    func insideWorkBlock() throws {
        // Nov 20, block 1 runs 09:30 to 10:30.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:00"))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")))
    }

    @Test("inside a break gives a break, not a work block")
    func insideBreak() throws {
        // Nov 10, block 4 is a break from 13:15 to 13:55.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-10 13:30"))
        #expect(moment == .inBreak(text: "Break 4", end: ny("2026-11-10 13:55")))
    }

    // MARK: boundaries

    @Test("at a block's exact start it is current")
    func exactStart() throws {
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 09:30"))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")))
    }

    @Test("at a block's exact end it is not current")
    func exactEnd() throws {
        // 10:30 is the end of block 1; block 2 doesn't start until 10:40.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:30"))
        #expect(moment != .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")))
    }

    @Test("one second before a block's end it is still current")
    func lastSecond() throws {
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"),
                                        at: ny("2026-11-20 10:30").addingTimeInterval(-1))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")))
    }

    @Test("back-to-back blocks switch exactly at the shared instant")
    func backToBack() throws {
        // Nov 23: block 1 ends 11:50 and block 2 starts 11:50.
        let data = try Fixture.data("feed-2026-11-23")
        let before = try Moment.resolve(feedData: data, at: ny("2026-11-23 11:50").addingTimeInterval(-1))
        let at = try Moment.resolve(feedData: data, at: ny("2026-11-23 11:50"))
        #expect(before == .inBlock(text: "Task 1", end: ny("2026-11-23 11:50")))
        #expect(at == .inBlock(text: "Task 2", end: ny("2026-11-23 12:20")))
    }

    @Test("a work block hands over to a break at the exact instant")
    func workToBreak() throws {
        // Nov 10: block 3 (work) ends 13:15, block 4 (break) starts 13:15.
        let data = try Fixture.data("feed-2026-11-10")
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-10 13:14"))
                == .inBlock(text: "Task 3", end: ny("2026-11-10 13:15")))
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-10 13:15"))
                == .inBreak(text: "Break 4", end: ny("2026-11-10 13:55")))
    }

    // MARK: midnight and other plans

    @Test("a block that crosses midnight is current before and after midnight", arguments: [
        "2026-11-10 23:30", "2026-11-10 23:45", "2026-11-11 00:00", "2026-11-11 00:15",
    ])
    func crossesMidnight(at: String) throws {
        // Nov 10, block 11 runs 23:30 to 00:30.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny(at))
        #expect(moment == .inBlock(text: "Task 11", end: ny("2026-11-11 00:30")))
    }

    @Test("a late block from yesterday's plan still counts while it is running")
    func yesterdaysLateBlock() throws {
        // Nov 10 feed: block 7 of the Nov 9 plan runs 23:20 on Nov 9 to 00:50 on Nov 10.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-10 00:30"))
        #expect(moment == .inBlock(text: "Task 7", end: ny("2026-11-10 00:50")))
    }

    @Test("a block from tomorrow's plan is found too")
    func tomorrowsBlock() throws {
        // Nov 10 feed also holds the Nov 11 plan: block 1 runs 13:00 to 14:00.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-11 13:30"))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-11 14:00")))
    }

    // MARK: status and bad input

    @Test("a block's status does not change the result", arguments: [
        "planned", "done", "failed", "skipped", "missed", "something-new",
    ])
    func statusIsIgnored(status: String) throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["status"] = status }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00"))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")))
    }

    @Test("a block with a null status is still current")
    func nullStatusIsIgnored() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["status"] = NSNull() }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00"))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30")))
    }

    @Test("a block whose end equals its start is never current")
    func zeroLengthBlock() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["end"] = $0["start"] }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 09:30"))
        #expect(moment != .inBlock(text: "Task 1", end: ny("2026-11-20 09:30")))
    }

    @Test("a block whose end is before its start is never current", arguments: [
        "2026-11-20 08:45", "2026-11-20 09:00", "2026-11-20 09:15", "2026-11-20 09:30", "2026-11-20 09:45",
    ])
    func backwardsBlock(at: String) throws {
        // Start 09:30, end 09:00: no instant can be inside it.
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["end"] = "2026-11-20T09:00:00-05:00" }
        let moment = try Moment.resolve(feedData: data, at: ny(at))
        if case .inBlock(let text, _) = moment { #expect(text != "Task 1") }
    }

    @Test("overlapping blocks do not crash the resolver")
    func overlapDoesNotCrash() throws {
        // Nov 10 feed, Nov 9 plan: block 5 (21:20-23:20) overlaps block 6 (21:40-23:10).
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-09 22:00"))
        guard case .inBlock = moment else {
            Issue.record("expected some block to be current, got \(String(describing: moment))")
            return
        }
    }

    @Test("a malformed feed throws instead of giving a Moment")
    func malformedThrows() {
        #expect(throws: (any Error).self) {
            try Moment.resolve(feedData: Data("{\"version\": 1".utf8), at: ny("2026-11-20 10:00"))
        }
    }
}
