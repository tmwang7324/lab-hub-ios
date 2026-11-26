// Checks the values from Config/Secrets.xcconfig and explains, in the log, what is wrong with them.
// It never logs a secret's value: only that it is set, how long it is, and a known prefix.

import Foundation

public enum AppConfig {
    /// Every key in `Config/Secrets.example.xcconfig`.
    public enum Key: String, CaseIterable, Sendable {
        case appleTeamID = "APPLE_TEAM_ID"
        case bundleID = "APP_BUNDLE_ID"
        case appGroup = "APP_GROUP_ID"
        case keychainGroup = "KEYCHAIN_ACCESS_GROUP"
        case githubToken = "GITHUB_TOKEN"

        /// What to do to get a good value (shown in the log when the value is wrong).
        var hint: String {
            switch self {
            case .appleTeamID: "find it at developer.apple.com > Account > Membership details (10 letters/digits)"
            case .bundleID: "use the reverse-DNS id you registered, e.g. com.yourname.labhub"
            case .appGroup: "register it under Identifiers > App Groups; it must start with 'group.'"
            case .keychainGroup: "usually <APPLE_TEAM_ID>.<APP_BUNDLE_ID> (shared Keychain, ADR 0001)"
            case .githubToken: "create a fine-grained token on the vault repo with Contents: read and Variables: read+write (ADR 0002); it starts with github_pat_"
            }
        }
    }

    public struct Issue: Equatable, Sendable {
        public enum Problem: Equatable, Sendable { case missing, placeholder, malformed }
        public let key: Key
        public let problem: Problem
    }

    static let tokenPrefixes = ["github_pat_", "ghp_"]

    /// Checks `values` (key name to value) and logs every problem as an error. Returns the problems.
    @discardableResult
    public static func validate(_ values: [String: String], log: LabHubLog = .shared) -> [Issue] {
        var issues: [Issue] = []
        for key in Key.allCases {
            let value = values[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let problem: Issue.Problem?
            if value.isEmpty {
                problem = .missing
            } else if isPlaceholder(value) {
                problem = .placeholder
            } else if !isWellFormed(value, for: key) {
                problem = .malformed
            } else {
                problem = nil
            }

            guard let problem else {
                log.info(.config, "\(key.rawValue) \(describeGoodValue(value, for: key))")
                continue
            }
            issues.append(Issue(key: key, problem: problem))
            let what: String
            switch problem {
            case .missing: what = "is missing"
            case .placeholder: what = "is still the placeholder value"
            case .malformed: what = "has an unexpected format (its value is not shown)"
            }
            log.error(.config, "\(key.rawValue) \(what): \(key.hint). Set it in Config/Secrets.xcconfig (copy Config/Secrets.example.xcconfig).")
        }
        let ok = Key.allCases.count - issues.count
        log.log(issues.isEmpty ? .info : .warning, .config, "config check: \(ok) of \(Key.allCases.count) values are usable")
        return issues
    }

    /// Reads `KEY = value` lines, skipping blank lines and `//` comments (also trailing ones).
    public static func parseXCConfig(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.components(separatedBy: "//")[0].trimmingCharacters(in: .whitespaces)
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    // MARK: private

    private static func isPlaceholder(_ value: String) -> Bool {
        value.hasPrefix("YOUR_") || value.contains("CHANGEME") || value.contains("REPLACE_ME")
    }

    private static func isWellFormed(_ value: String, for key: Key) -> Bool {
        switch key {
        case .appleTeamID:
            return value.count == 10 && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        case .bundleID, .keychainGroup:
            return value.contains(".") && !value.contains(" ")
        case .appGroup:
            return value.hasPrefix("group.") && value.count > "group.".count && !value.contains(" ")
        case .githubToken:
            guard let prefix = tokenPrefixes.first(where: value.hasPrefix) else { return false }
            return value.count - prefix.count >= 10
        }
    }

    /// For the log. Secrets are summarised, never shown.
    private static func describeGoodValue(_ value: String, for key: Key) -> String {
        guard key == .githubToken else { return "= \(value)" }
        let prefix = tokenPrefixes.first(where: value.hasPrefix) ?? "?"
        return "is set (length \(value.count), starts with \(prefix))"
    }
}
