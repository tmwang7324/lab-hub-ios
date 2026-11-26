import Foundation
import Testing
@testable import LabHubCore

@Suite("Feed decoding")
struct FeedDecodingTests {
    @Test("Nov 20 feed gives yesterday's and today's plans with real block times")
    func decodesNov20() throws {
        let feed = try Feed.decode(Fixture.data("feed-2026-11-20"))

        #expect(feed.plans.map(\.date) == ["2026-11-19", "2026-11-20"])
        let today = try #require(feed.plans.last)
        #expect(today.blocks.count == 3)

        let first = try #require(today.blocks.first)
        #expect(first.id == "2026-11-20#1")
        #expect(first.start == ny("2026-11-20 09:30"))
        #expect(first.end == ny("2026-11-20 10:30"))
        #expect(first.kind == .work)
        #expect(first.status == .planned)
    }
}
