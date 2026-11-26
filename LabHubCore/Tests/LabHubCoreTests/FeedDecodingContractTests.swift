import Foundation
import Testing
@testable import LabHubCore

// Ticket #2: the decoding contract from the spec (ADR 0004: `version` is the schema version).

@Suite("Feed decoding contract")
struct FeedDecodingContractTests {
    private func firstBlock(of data: Data) throws -> Block {
        let feed = try Feed.decode(data)
        return try #require(feed.plans.last?.blocks.first)
    }

    // MARK: status

    @Test("an unknown status decodes to no status", arguments: ["rescheduled", "", "DONE"])
    func unknownStatus(value: String) throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["status"] = value }
        #expect(try firstBlock(of: data).status == nil)
    }

    @Test("a null status decodes to no status")
    func nullStatus() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["status"] = NSNull() }
        #expect(try firstBlock(of: data).status == nil)
    }

    @Test("a missing status decodes to no status")
    func missingStatus() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["status"] = nil }
        #expect(try firstBlock(of: data).status == nil)
    }

    @Test("`missed` is a real status", arguments: [("missed", Block.Status.missed), ("failed", .failed)])
    func missedIsAStatus(raw: String, expected: Block.Status) throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["status"] = raw }
        #expect(try firstBlock(of: data).status == expected)
    }

    // MARK: private

    @Test("a missing `private` means the block is not private")
    func missingPrivate() throws {
        // The shipped fixtures predate the generator writing `private`.
        let block = try firstBlock(of: Fixture.data("feed-2026-11-20"))
        #expect(block.isPrivate == false)
    }

    @Test("`private: true` makes the block private, and `false` does not")
    func explicitPrivate() throws {
        let yes = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["private"] = true }
        let no = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["private"] = false }
        #expect(try firstBlock(of: yes).isPrivate)
        #expect(try firstBlock(of: no).isPrivate == false)
    }

    // MARK: errors

    @Test("data that is not JSON throws instead of producing a plan")
    func notJSON() {
        #expect(throws: (any Error).self) { try Feed.decode(Data("not a feed".utf8)) }
    }

    @Test("empty data throws")
    func emptyData() {
        #expect(throws: (any Error).self) { try Feed.decode(Data()) }
    }

    @Test("a feed missing its `days` throws")
    func missingDays() throws {
        let data = try Fixture.mutated("feed-2026-11-20") { $0["days"] = nil }
        #expect(throws: (any Error).self) { try Feed.decode(data) }
    }

    // MARK: generated_at

    @Test("`generated_at` decodes as an absolute instant")
    func generatedAt() throws {
        let feed = try Feed.decode(Fixture.data("feed-2026-11-20"))
        #expect(feed.generatedAt == ny("2026-11-20 06:00"))
    }

    @Test("a feed missing `generated_at` throws, because staleness can't be judged without it")
    func missingGeneratedAt() throws {
        let data = try Fixture.mutated("feed-2026-11-20") { $0["generated_at"] = nil }
        #expect(throws: (any Error).self) { try Feed.decode(data) }
    }

    @Test("an unreadable `generated_at` throws", arguments: ["yesterday", "2026-11-20 06:00"])
    func badGeneratedAt(value: String) throws {
        let data = try Fixture.mutated("feed-2026-11-20") { $0["generated_at"] = value }
        #expect(throws: (any Error).self) { try Feed.decode(data) }
    }

    @Test("an unknown block kind throws")
    func unknownKind() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["kind"] = "meeting" }
        #expect(throws: (any Error).self) { try Feed.decode(data) }
    }

    @Test("a block with an unreadable time throws")
    func badTime() throws {
        let data = try Fixture.mutatedFirstBlock("feed-2026-11-20") { $0["start"] = "9:30 tomorrow" }
        #expect(throws: (any Error).self) { try Feed.decode(data) }
    }

    // MARK: empty shapes

    @Test("a feed with no days decodes to no plans")
    func noDays() throws {
        let data = try Fixture.mutated("feed-2026-11-20") { $0["days"] = [[String: Any]]() }
        #expect(try Feed.decode(data).plans.isEmpty)
    }

    @Test("a plan with no blocks decodes to an empty plan")
    func planWithNoBlocks() throws {
        let data = try Fixture.mutated("feed-2026-11-20") { json in
            var days = json["days"] as! [[String: Any]]
            days[days.count - 1]["blocks"] = [[String: Any]]()
            json["days"] = days
        }
        let today = try #require(Feed.decode(data).plans.last)
        #expect(today.date == "2026-11-20")
        #expect(today.blocks.isEmpty)
    }

    // MARK: fixtures

    @Test("all three sanitized fixtures decode", arguments: [
        ("feed-2026-11-10", ["2026-11-09", "2026-11-10", "2026-11-11"]),
        ("feed-2026-11-20", ["2026-11-19", "2026-11-20"]),
        ("feed-2026-11-23", ["2026-11-22", "2026-11-23"]),
    ])
    func fixturesDecode(name: String, dates: [String]) throws {
        let feed = try Feed.decode(Fixture.data(name))
        #expect(feed.version == 1)
        #expect(feed.plans.map(\.date) == dates)
    }

    @Test("a block's id is its plan's date and its row")
    func blockIdUsesPlanDate() throws {
        let feed = try Feed.decode(Fixture.data("feed-2026-11-10"))
        let yesterday = try #require(feed.plans.first)
        #expect(yesterday.blocks.map(\.id).prefix(2) == ["2026-11-09#1", "2026-11-09#2"])
    }

    @Test("a block that crosses midnight keeps its real end instant")
    func crossesMidnight() throws {
        let feed = try Feed.decode(Fixture.data("feed-2026-11-10"))
        let late = try #require(feed.plans.first(where: { $0.date == "2026-11-10" })?.blocks.last)
        #expect(late.start == ny("2026-11-10 23:30"))
        #expect(late.end == ny("2026-11-11 00:30"))
    }
}
