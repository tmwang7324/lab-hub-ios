import Foundation
import Testing
@testable import LabHubCore

// Config values come from Config/Secrets.xcconfig (gitignored). Until you fill them in, they are
// placeholders. Validation says exactly which one is wrong and why, and never prints a secret.

@Suite("App config")
struct AppConfigTests {
    /// A complete, valid set of values (all fake).
    static let valid: [String: String] = [
        "APPLE_TEAM_ID": "AB12CD34EF",
        "APP_BUNDLE_ID": "com.example.labhub",
        "APP_GROUP_ID": "group.com.example.labhub",
        "KEYCHAIN_ACCESS_GROUP": "AB12CD34EF.com.example.labhub",
        "GITHUB_TOKEN": "github_pat_" + String(repeating: "x", count: 40),
    ]

    private func validate(_ values: [String: String], recorder: LogRecorder = LogRecorder()) -> [AppConfig.Issue] {
        AppConfig.validate(values, log: recorder.log)
    }

    @Test("a complete, valid set has no issues and logs nothing worse than info")
    func validIsClean() {
        let recorder = LogRecorder()
        #expect(validate(Self.valid, recorder: recorder).isEmpty)
        #expect(recorder.messages(.error).isEmpty)
        #expect(recorder.messages(.warning).isEmpty)
    }

    @Test("a missing value is reported as missing", arguments: AppConfig.Key.allCases)
    func missing(key: AppConfig.Key) {
        var values = Self.valid
        values[key.rawValue] = nil
        #expect(validate(values).map(\.key) == [key])
        #expect(validate(values).first?.reason == .missing)
    }

    @Test("an empty or whitespace value counts as missing")
    func blank() {
        var values = Self.valid
        values["GITHUB_TOKEN"] = "   "
        #expect(validate(values).first?.reason == .missing)
    }

    @Test("the shipped placeholders are reported as placeholders, not as malformed", arguments: [
        ("APPLE_TEAM_ID", "YOUR_TEAM_ID_HERE"),
        ("APP_BUNDLE_ID", "YOUR_BUNDLE_ID_HERE"),
        ("APP_GROUP_ID", "YOUR_APP_GROUP_HERE"),
        ("KEYCHAIN_ACCESS_GROUP", "YOUR_KEYCHAIN_GROUP_HERE"),
        ("GITHUB_TOKEN", "YOUR_GITHUB_TOKEN_HERE"),
    ])
    func placeholders(key: String, placeholder: String) {
        var values = Self.valid
        values[key] = placeholder
        let issues = validate(values)
        #expect(issues.map(\.key.rawValue) == [key])
        #expect(issues.first?.reason == .placeholder)
    }

    @Test("a team id must be ten letters and digits")
    func teamIdShape() {
        var values = Self.valid
        values["APPLE_TEAM_ID"] = "too-short"
        #expect(validate(values).first?.reason == .malformed)
    }

    @Test("an app group must start with `group.`")
    func appGroupShape() {
        var values = Self.valid
        values["APP_GROUP_ID"] = "com.example.labhub"
        #expect(validate(values).first?.reason == .malformed)
    }

    @Test("a GitHub token must look like a fine-grained or classic token", arguments: [
        "github_pat_" + String(repeating: "a", count: 30), "ghp_" + String(repeating: "a", count: 36),
    ])
    func goodTokens(token: String) {
        var values = Self.valid
        values["GITHUB_TOKEN"] = token
        #expect(validate(values).isEmpty)
    }

    @Test("a token that is not a GitHub token is malformed", arguments: [
        "hello", "Bearer github_pat_abc", "AB12CD34EF", "github_pat_",
    ])
    func badTokens(token: String) {
        var values = Self.valid
        values["GITHUB_TOKEN"] = token
        #expect(validate(values).first?.reason == .malformed)
    }

    @Test("every issue is logged as an error that tells you what to do")
    func issuesAreLogged() throws {
        var values = Self.valid
        values["GITHUB_TOKEN"] = "YOUR_GITHUB_TOKEN_HERE"
        let recorder = LogRecorder()
        _ = validate(values, recorder: recorder)

        let line = try #require(recorder.messages(.error, .config).first)
        #expect(line.contains("GITHUB_TOKEN"))
        #expect(line.contains("placeholder"))
        #expect(line.contains("Secrets.xcconfig"))
    }

    @Test("the token's value is never logged, only its length and prefix")
    func tokenNeverLogged() throws {
        let secret = "github_pat_SUPERSECRETVALUE1234567890"
        var values = Self.valid
        values["GITHUB_TOKEN"] = secret
        let recorder = LogRecorder()
        _ = validate(values, recorder: recorder)

        let everything = recorder.entries.map(\.message).joined(separator: "\n")
        #expect(!everything.contains("SUPERSECRETVALUE"))
        #expect(everything.contains("GITHUB_TOKEN is set"))
        #expect(everything.contains("length \(secret.count)"))
        #expect(everything.contains("github_pat_"))
    }

    @Test("a malformed token is never logged either")
    func malformedTokenNeverLogged() {
        var values = Self.valid
        values["GITHUB_TOKEN"] = "hunter2-my-password"
        let recorder = LogRecorder()
        _ = validate(values, recorder: recorder)
        #expect(!recorder.entries.map(\.message).joined().contains("hunter2"))
    }

    @Test("a token that is missing the Variables permission note appears in the hint")
    func tokenHintMentionsPermissions() throws {
        var values = Self.valid
        values["GITHUB_TOKEN"] = nil
        let recorder = LogRecorder()
        _ = validate(values, recorder: recorder)
        let line = try #require(recorder.messages(.error, .config).first)
        #expect(line.contains("Variables"))
    }

    @Test("the example file ships with exactly the keys the validator knows")
    func exampleFileMatchesKeys() throws {
        // Config/Secrets.example.xcconfig sits at the repo root, two levels above the package.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Config/Secrets.example.xcconfig"), encoding: .utf8)
        let parsed = AppConfig.parseXCConfig(text)

        #expect(Set(parsed.keys) == Set(AppConfig.Key.allCases.map(\.rawValue)))
        // And every shipped value is a placeholder, so no real secret can be committed by accident.
        let issues = AppConfig.validate(parsed, log: LabHubLog(sinks: []))
        #expect(issues.count == AppConfig.Key.allCases.count)
        #expect(issues.allSatisfy { $0.reason == .placeholder })
    }

    @Test("an xcconfig parser reads KEY = value lines and skips comments")
    func parser() {
        let parsed = AppConfig.parseXCConfig("""
        // a comment
        APPLE_TEAM_ID = AB12CD34EF   // trailing comment

        GITHUB_TOKEN=github_pat_abc
        """)
        #expect(parsed == ["APPLE_TEAM_ID": "AB12CD34EF", "GITHUB_TOKEN": "github_pat_abc"])
    }
}
