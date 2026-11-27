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
        // 13:30 on Nov 11 is 31.5 hours after the feed was built, so the block is marked stale.
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-11 14:00"), isStale: true))
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
        if case .inBlock(let text, _, _) = moment { #expect(text != "Task 1") }
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

// Ticket #4: no block is current, but one is still to come.

@Suite("Moment: waiting for the next block")
struct MomentWaitingTests {
    @Test("between two blocks it waits for the following block")
    func betweenBlocks() throws {
        // Nov 20: block 1 ends 10:30, block 2 runs 10:40 to 11:10.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:35"))
        #expect(moment == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
    }

    @Test("at a block's exact end, before the Next block starts, the Moment is waiting")
    func exactEndBeforeNextBlock() throws {
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:30"))
        #expect(moment == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
    }

    @Test("one second before a block starts it is still the Next block")
    func lastSecondBeforeStart() throws {
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"),
                                        at: ny("2026-11-20 10:40").addingTimeInterval(-1))
        #expect(moment == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
    }

    @Test("before the day's first block it waits for that block", arguments: [
        "2026-11-20 06:00", "2026-11-20 09:00", "2026-11-20 09:29",
    ])
    func beforeFirstBlock(at: String) throws {
        // Yesterday's (Nov 19) blocks all ended by 20:30, so today's block 1 at 09:30 is next.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny(at))
        #expect(moment == .waiting(text: "Task 1", start: ny("2026-11-20 09:30"), end: ny("2026-11-20 10:30")))
    }

    @Test("after the last block of a plan, the Next block is tomorrow's first block")
    func tomorrowsFirstBlock() throws {
        // Nov 10 feed: the Nov 10 plan's last block ends 00:30 on Nov 11; the Nov 11 plan starts at 13:00.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-11 00:30"))
        #expect(moment == .waiting(text: "Task 1", start: ny("2026-11-11 13:00"), end: ny("2026-11-11 14:00")))
    }

    @Test("after yesterday's late block ends, the Next block is today's first block")
    func yesterdaysLastBlockThenToday() throws {
        // Nov 10 feed: the Nov 9 plan's block 7 ends 00:50 on Nov 10; the Nov 10 plan starts at 10:30.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-10 01:00"))
        #expect(moment == .waiting(text: "Task 1", start: ny("2026-11-10 10:30"), end: ny("2026-11-10 11:20")))
    }

    @Test("the Next block does not depend on the order of the plans in the feed")
    func planOrderDoesNotMatter() throws {
        let inOrder = try Fixture.data("feed-2026-11-10")
        let reversed = try Fixture.mutatedDays("feed-2026-11-10") { $0.reverse() }
        let expected = Moment.waiting(text: "Task 1", start: ny("2026-11-10 10:30"), end: ny("2026-11-10 11:20"))

        #expect(try Moment.resolve(feedData: inOrder, at: ny("2026-11-10 01:00")) == expected)
        #expect(try Moment.resolve(feedData: reversed, at: ny("2026-11-10 01:00")) == expected)
    }

    @Test("the Next block is the earliest to start, not the first listed")
    func earliestNotFirstListed() throws {
        // Reverse the blocks inside the Nov 20 plan: block 3 is now listed first, but block 2 starts first.
        let data = try Fixture.mutatedBlocks("feed-2026-11-20") { $0.reverse() }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:35"))
        #expect(moment == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
    }

    @Test("a plan with no blocks is skipped when finding the Next block")
    func emptyPlanIsSkipped() throws {
        // Nov 10 feed with the Nov 10 plan emptied: after yesterday's block 7 ends, the next is Nov 11's first.
        let data = try Fixture.mutatedDays("feed-2026-11-10") { $0[1]["blocks"] = [[String: Any]]() }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-10 01:00"))
        #expect(moment == .waiting(text: "Task 1", start: ny("2026-11-11 13:00"), end: ny("2026-11-11 14:00")))
    }

    @Test("a block that can never be current is never the Next block")
    func invalidBlockIsNeverNext() throws {
        // Nov 20 block 1 made zero-length at 09:30: block 2 at 10:40 is next instead.
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["end"] = $0["start"] }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 09:00"))
        #expect(moment == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
    }
}

// Ticket #5: a fresh feed with no current or future block. Every instant here is within 26 hours of
// the fixture's `generated_at` (06:00 on the feed's day), so the feed is not stale.

@Suite("Moment: nothing left")
struct MomentNothingLeftTests {
    @Test("after the feed's last block, with no later plan, nothing is left", arguments: [
        "2026-11-20 11:40", "2026-11-20 12:00", "2026-11-20 23:59",
    ])
    func afterLastBlock(at: String) throws {
        // Nov 20: block 3 ends at 11:40 and no Nov 21 plan is in the feed.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny(at))
        #expect(moment == .nothingLeft)
    }

    @Test("a feed with no plans at all gives nothing left")
    func noPlans() throws {
        let data = try Fixture.mutatedDays("feed-2026-11-20") { $0.removeAll() }
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00")) == .nothingLeft)
    }

    @Test("a feed whose plans have no blocks gives nothing left")
    func noBlocks() throws {
        let data = try Fixture.mutatedDays("feed-2026-11-20") { days in
            for index in days.indices { days[index]["blocks"] = [[String: Any]]() }
        }
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00")) == .nothingLeft)
    }

    @Test("today's plan with no blocks gives nothing left, not a separate \"no plan\" Moment")
    func todayHasNoBlocks() throws {
        // Nov 20 feed with today's plan emptied; yesterday's (Nov 19) blocks all ended by 20:30.
        let data = try Fixture.mutatedBlocks("feed-2026-11-20") { $0.removeAll() }
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00")) == .nothingLeft)
    }

    @Test("a block that can never be current does not keep the day open")
    func invalidLastBlock() throws {
        // Nov 20's last block (11:20 to 11:40) made to end before it starts: after 11:10 nothing is left.
        let data = try Fixture.mutatedBlock("feed-2026-11-20", id: "2026-11-20#3") { $0["end"] = "2026-11-20T11:00:00-05:00" }
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 11:15")) == .nothingLeft)
    }
}

// Ticket #6: a stale feed (`generated_at` more than 26 hours before the instant) still shows its
// blocks, but never claims nothing is left.

@Suite("Moment: stale feed and can't refresh")
struct MomentStaleFeedTests {
    /// The Nov 20 fixture's `generated_at`: 06:00 New York time on Nov 20.
    static let nov20GeneratedAt = ny("2026-11-20 06:00")

    /// A fixture whose `generated_at` is replaced, so the same blocks can be read as fresh or stale.
    private func generated(_ name: String, at text: String) throws -> Data {
        try Fixture.mutated(name) { $0["generated_at"] = text }
    }

    @Test("a stale feed with a current work block resolves as in a block")
    func staleInBlock() throws {
        let data = try generated("feed-2026-11-20", at: "2026-11-18T06:00:00-05:00")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00"))
        #expect(moment == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30"), isStale: true))
    }

    @Test("a stale feed with a current break resolves as in a break")
    func staleInBreak() throws {
        let data = try generated("feed-2026-11-10", at: "2026-11-08T06:00:00-05:00")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-10 13:30"))
        #expect(moment == .inBreak(text: "Break 4", end: ny("2026-11-10 13:55"), isStale: true))
    }

    @Test("a stale feed with a future block resolves as waiting")
    func staleWaiting() throws {
        let data = try generated("feed-2026-11-20", at: "2026-11-18T06:00:00-05:00")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:35"))
        #expect(moment == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10"), isStale: true))
    }

    @Test("a stale feed with nothing current or to come can't refresh", arguments: [
        "2026-11-21 08:01", "2026-11-22 12:00", "2026-12-20 12:00",
    ])
    func staleNothingLeft(at: String) throws {
        // Nov 20 fixture: the last block ends 11:40 on Nov 20; the feed is stale after 08:00 on Nov 21.
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny(at))
        #expect(moment == .cantRefresh)
    }

    @Test("a stale feed with no blocks at all can't refresh")
    func staleEmptyFeed() throws {
        let data = try Fixture.mutated("feed-2026-11-20") { json in
            json["days"] = [[String: Any]]()
            json["generated_at"] = "2026-11-18T06:00:00-05:00"
        }
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00")) == .cantRefresh)
    }

    @Test("a feed exactly 26 hours old is not stale")
    func exactly26Hours() throws {
        let instant = Self.nov20GeneratedAt.addingTimeInterval(26 * 3600)
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: instant)
        #expect(moment == .nothingLeft)
    }

    @Test("one second past 26 hours the feed is stale")
    func justPast26Hours() throws {
        let instant = Self.nov20GeneratedAt.addingTimeInterval(26 * 3600 + 1)
        let moment = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: instant)
        #expect(moment == .cantRefresh)
    }

    @Test("a feed generated in the future is not stale")
    func generatedInFuture() throws {
        // The phone's clock is behind the server's: `generated_at` is after the instant.
        let data = try generated("feed-2026-11-20", at: "2026-11-25T06:00:00-05:00")
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 12:00")) == .nothingLeft)
    }

    // MARK: the stale mark on blocks

    @Test("on a fresh feed no block is marked stale")
    func freshBlocksAreNotMarkedStale() throws {
        let nov20 = try Fixture.data("feed-2026-11-20")
        #expect(try Moment.resolve(feedData: nov20, at: ny("2026-11-20 10:00"))
                == .inBlock(text: "Task 1", end: ny("2026-11-20 10:30"), isStale: false))
        #expect(try Moment.resolve(feedData: nov20, at: ny("2026-11-20 10:35"))
                == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10"), isStale: false))
        #expect(try Moment.resolve(feedData: Fixture.data("feed-2026-11-10"), at: ny("2026-11-10 13:30"))
                == .inBreak(text: "Break 4", end: ny("2026-11-10 13:55"), isStale: false))
    }

    @Test("a block is marked stale exactly when the feed is more than 26 hours old")
    func staleMarkFollowsTheBoundary() throws {
        // Nov 20 block 1 runs 09:30 to 10:30; read at 10:00, so `generated_at` alone sets the feed's age.
        let exactly26h = try generated("feed-2026-11-20", at: "2026-11-19T08:00:00-05:00")
        let justOver = try generated("feed-2026-11-20", at: "2026-11-19T07:59:59-05:00")
        let inTheFuture = try generated("feed-2026-11-20", at: "2026-11-25T06:00:00-05:00")
        let end = ny("2026-11-20 10:30")

        #expect(try Moment.resolve(feedData: exactly26h, at: ny("2026-11-20 10:00")) == .inBlock(text: "Task 1", end: end, isStale: false))
        #expect(try Moment.resolve(feedData: justOver, at: ny("2026-11-20 10:00")) == .inBlock(text: "Task 1", end: end, isStale: true))
        #expect(try Moment.resolve(feedData: inTheFuture, at: ny("2026-11-20 10:00")) == .inBlock(text: "Task 1", end: end, isStale: false))
    }

    @Test("the stale mark does not change which block is shown or its text")
    func staleMarkChangesNothingElse() throws {
        let fresh = try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:35"))
        let stale = try Moment.resolve(feedData: generated("feed-2026-11-20", at: "2026-11-18T06:00:00-05:00"), at: ny("2026-11-20 10:35"))
        guard case .waiting(let freshText, let freshStart, let freshEnd, false) = fresh,
              case .waiting(let staleText, let staleStart, let staleEnd, true) = stale else {
            Issue.record("expected a fresh and a stale waiting Moment, got \(fresh) and \(stale)")
            return
        }
        #expect((freshText, freshStart, freshEnd) == (staleText, staleStart, staleEnd))
    }

    @Test("staleness compares absolute instants, whatever offset `generated_at` is written with")
    func generatedAtOffset() throws {
        // 11:00 UTC is 06:00 in New York: the same instant as the fixture's own `generated_at`.
        let data = try generated("feed-2026-11-20", at: "2026-11-20T11:00:00Z")
        let instant = Self.nov20GeneratedAt.addingTimeInterval(26 * 3600)
        #expect(try Moment.resolve(feedData: data, at: instant) == .nothingLeft)
        #expect(try Moment.resolve(feedData: data, at: instant.addingTimeInterval(1)) == .cantRefresh)
    }
}

// Ticket #7: a private block shows only "Busy" and its times, whether current or next (ADR 0003).
// The shipped fixtures predate `private`, so each test marks one block private.

@Suite("Moment: private blocks show as Busy")
struct MomentPrivateBlockTests {
    @Test("a private current block shows Busy and its end, with no task text in the result")
    func privateCurrent() throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-20", id: "2026-11-20#1")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00"))
        #expect(moment == .inBlock(text: "Busy", end: ny("2026-11-20 10:30")))
        #expect(!String(describing: moment).contains("Task 1"))
    }

    @Test("a private Next block shows Busy in the waiting Moment")
    func privateNext() throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-20", id: "2026-11-20#2")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:35"))
        #expect(moment == .waiting(text: "Busy", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
        #expect(!String(describing: moment).contains("Task 2"))
    }

    @Test("a private break shows Busy and is still a break")
    func privateBreak() throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-10", id: "2026-11-10#4")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-10 13:30"))
        #expect(moment == .inBreak(text: "Busy", end: ny("2026-11-10 13:55")))
    }

    @Test("a private block that crosses midnight shows Busy on both sides of midnight", arguments: [
        "2026-11-10 23:45", "2026-11-11 00:15",
    ])
    func privateAfterMidnight(at: String) throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-10", id: "2026-11-10#11")
        let moment = try Moment.resolve(feedData: data, at: ny(at))
        #expect(moment == .inBlock(text: "Busy", end: ny("2026-11-11 00:30")))
    }

    @Test("a private late block from yesterday's plan shows Busy")
    func privateYesterday() throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-10", id: "2026-11-09#7")
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-10 00:30"))
        #expect(moment == .inBlock(text: "Busy", end: ny("2026-11-10 00:50")))
    }

    @Test("a private block in a stale feed still shows Busy")
    func privateInStaleFeed() throws {
        let data = try Fixture.edited(Fixture.withPrivateBlock("feed-2026-11-20", id: "2026-11-20#1")) {
            $0["generated_at"] = "2026-11-18T06:00:00-05:00"
        }
        let moment = try Moment.resolve(feedData: data, at: ny("2026-11-20 10:00"))
        #expect(moment == .inBlock(text: "Busy", end: ny("2026-11-20 10:30"), isStale: true))
    }

    @Test("a block marked `private: false`, or with no `private`, shows its task text")
    func notPrivate() throws {
        let explicit = try Fixture.mutatedBlock("feed-2026-11-20", id: "2026-11-20#1") { $0["private"] = false }
        let expected = Moment.inBlock(text: "Task 1", end: ny("2026-11-20 10:30"))
        #expect(try Moment.resolve(feedData: explicit, at: ny("2026-11-20 10:00")) == expected)
        #expect(try Moment.resolve(feedData: Fixture.data("feed-2026-11-20"), at: ny("2026-11-20 10:00")) == expected)
    }

    @Test("only the private block is hidden: the blocks around it keep their text")
    func onlyThePrivateBlockIsHidden() throws {
        let data = try Fixture.withPrivateBlock("feed-2026-11-20", id: "2026-11-20#1")
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 09:00"))
                == .waiting(text: "Busy", start: ny("2026-11-20 09:30"), end: ny("2026-11-20 10:30")))
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 10:35"))
                == .waiting(text: "Task 2", start: ny("2026-11-20 10:40"), end: ny("2026-11-20 11:10")))
        #expect(try Moment.resolve(feedData: data, at: ny("2026-11-20 10:45"))
                == .inBlock(text: "Task 2", end: ny("2026-11-20 11:10")))
    }
}
