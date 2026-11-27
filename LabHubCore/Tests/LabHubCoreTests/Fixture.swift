import Foundation
import Testing

/// Loads a sanitized feed from `Fixtures/` (see `Scripts/sanitize_feed.py`).
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

/// A New York wall-clock time as an absolute instant, e.g. `ny("2026-11-20 10:00")`.
func ny(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

extension Fixture {
    /// A fixture with a change applied to its parsed JSON, so tests start from a real feed shape
    /// (ADR 0004) instead of hand-written JSON. The closure edits the top-level dictionary in place.
    static func mutated(_ name: String, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        try edited(data(name), edit)
    }

    /// Feed bytes with a further change applied, so edits can be stacked:
    /// `edited(withPrivateBlock(...)) { $0["generated_at"] = ... }`.
    static func edited(_ feed: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: feed) as? [String: Any])
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// A fixture with its list of plans (`days`) edited, e.g. to empty a plan or reorder the plans.
    static func mutatedDays(_ name: String, _ edit: @escaping (inout [[String: Any]]) -> Void) throws -> Data {
        try mutated(name) { json in
            var days = json["days"] as! [[String: Any]]
            edit(&days)
            json["days"] = days
        }
    }

    /// Edits the list of blocks of one plan: the plan dated `date`, or the last plan (the feed's
    /// "today") when `date` is nil. Use it to reorder, empty or change several blocks at once.
    static func mutatedBlocks(_ name: String, date: String? = nil,
                              _ edit: @escaping (inout [[String: Any]]) -> Void) throws -> Data {
        try mutatedDays(name) { days in
            let day = date.map { date in days.firstIndex { $0["date"] as? String == date }! } ?? days.count - 1
            var blocks = days[day]["blocks"] as! [[String: Any]]
            edit(&blocks)
            days[day]["blocks"] = blocks
        }
    }

    /// Edits the first block of the last plan (the feed's "today") in a fixture.
    static func mutatedFirstBlock(_ name: String, _ edit: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try mutatedBlocks(name) { edit(&$0[0]) }
    }

    /// Edits one block, named by its id (`<date>#<row>`, ADR 0003), e.g. `mutatedBlock(name, id: "2026-11-10#4")`.
    static func mutatedBlock(_ name: String, id: String, _ edit: @escaping (inout [String: Any]) -> Void) throws -> Data {
        let parts = id.split(separator: "#")
        let date = String(parts[0])
        let row = Int(parts[1])!
        return try mutatedBlocks(name, date: date) { blocks in
            let index = blocks.firstIndex { $0["row"] as? Int == row }!
            edit(&blocks[index])
        }
    }

    /// A fixture with the block `id` marked `private: true`. The shipped fixtures predate `private`.
    static func withPrivateBlock(_ name: String, id: String) throws -> Data {
        try mutatedBlock(name, id: id) { $0["private"] = true }
    }
}
