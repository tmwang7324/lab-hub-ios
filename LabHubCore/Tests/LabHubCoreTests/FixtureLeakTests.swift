import Foundation
import Testing

// ADR 0004: this repo is public, so every fixture must hold only placeholder text. This is the leak check
// the ADR asks for. Every free-text field must match what `Scripts/sanitize_feed.py` writes, and a field the
// check doesn't know about fails, so a new generator field can't slip real text in unnoticed.

@Suite("Fixtures hold only placeholder text")
struct FixtureLeakTests {
    static let fixtures = ["feed-2026-11-10", "feed-2026-11-20", "feed-2026-11-23"]

    /// Free-text fields mapped to the only shape they may have. `nil` (JSON null) is always fine.
    static let dayRules: [String: String] = [
        "p1": #"^Project [A-Z]$"#,
        "p2": #"^Project [A-Z]$"#,
        "note_path": #"^Plans/\d{4}-\d{2}-\d{2} Plan\.md$"#,
        // Clock times and separators only: no words.
        "window": #"^[0-9:apm ;,\-–~]+$"#,
    ]
    static let blockRules: [String: String] = [
        "task": #"^(Task|Break) \d+$"#,
        "priority": #"^(P\d · Project|Priority)$"#,
        "done_test": #"^Done test \d+$"#,
        "status_raw": #"^(planned|done|failed|skipped|missed|free text)$"#,
        "actual_end": #"^((~|By )?\d{1,2}:\d{2} ?[AP]M( Nov \d+)?|—|Not recorded)$"#,
    ]
    /// Fields that carry no free text (dates, numbers, flags, enums).
    static let safeDayKeys: Set<String> = ["date", "blocks", "parking_lot_count", "non_negotiables"]
    static let safeBlockKeys: Set<String> = ["row", "start", "end", "kind", "status", "time_uncertain", "tips"]

    private func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    @Test("no free text in the fixture is anything but a placeholder", arguments: fixtures)
    func noRealText(fixture: String) throws {
        let json = try #require(JSONSerialization.jsonObject(with: Fixture.data(fixture)) as? [String: Any])
        var leaks: [String] = []

        #expect(json["source_commit"] as? String == "0000000")
        for warning in json["warnings"] as? [String] ?? [] where !matches(#"^Warning \d+$"#, warning) {
            leaks.append("warning: \(warning)")
        }

        for day in json["days"] as? [[String: Any]] ?? [] {
            let date = day["date"] as? String ?? "?"
            for (key, value) in day {
                if let pattern = Self.dayRules[key] {
                    if let text = value as? String, !matches(pattern, text) { leaks.append("\(date) \(key): \(text)") }
                } else if !Self.safeDayKeys.contains(key) {
                    leaks.append("\(date): unknown day field '\(key)'")
                }
            }
            for item in day["non_negotiables"] as? [[String: Any]] ?? [] {
                if let text = item["text"] as? String, !matches(#"^Non-negotiable \d+$"#, text) {
                    leaks.append("\(date) non_negotiable: \(text)")
                }
            }
            for block in day["blocks"] as? [[String: Any]] ?? [] {
                let id = "\(date)#\(block["row"] ?? "?")"
                for (key, value) in block {
                    if let pattern = Self.blockRules[key] {
                        if let text = value as? String, !matches(pattern, text) { leaks.append("\(id) \(key): \(text)") }
                    } else if !Self.safeBlockKeys.contains(key) {
                        leaks.append("\(id): unknown block field '\(key)'")
                    }
                }
                for tip in block["tips"] as? [String] ?? [] where !matches(#"^Tip \d+\.\d+$"#, tip) {
                    leaks.append("\(id) tip: \(tip)")
                }
            }
        }
        #expect(leaks.isEmpty, "unsanitized text in \(fixture): \(leaks)")
    }
}
