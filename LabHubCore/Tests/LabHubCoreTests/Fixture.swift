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
        var json = try #require(JSONSerialization.jsonObject(with: data(name)) as? [String: Any])
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

    /// Edits the first block of the last plan (the feed's "today") in a fixture.
    static func mutatedFirstBlock(_ name: String, _ edit: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try mutated(name) { json in
            var days = json["days"] as! [[String: Any]]
            var today = days[days.count - 1]
            var blocks = today["blocks"] as! [[String: Any]]
            edit(&blocks[0])
            today["blocks"] = blocks
            days[days.count - 1] = today
            json["days"] = days
        }
    }

    /// Edits one block, named the way its id is (`date#row`): `mutatedBlock(name, "2026-11-10", row: 4)`.
    static func mutatedBlock(_ name: String, _ date: String, row: Int,
                             _ edit: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try mutatedDays(name) { days in
            let day = days.firstIndex { $0["date"] as? String == date }!
            var blocks = days[day]["blocks"] as! [[String: Any]]
            let index = blocks.firstIndex { $0["row"] as? Int == row }!
            edit(&blocks[index])
            days[day]["blocks"] = blocks
        }
    }
}
