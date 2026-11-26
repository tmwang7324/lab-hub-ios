// The feed model and decoder. See CONTEXT.md for Feed, Plan and Block.

import Foundation

/// The whole `feed.json`: one `Plan` per day.
struct Feed: Decodable, Equatable, Sendable {
    let version: Int
    let plans: [Plan]

    private enum CodingKeys: String, CodingKey {
        case version
        case plans = "days"
    }

    /// The schema version this decoder and the fixtures are written against (ADR 0004).
    static let supportedVersion = 1

    /// Decodes feed bytes, logging what it found or exactly which field failed (never plan text).
    static func decode(_ data: Data, log: LabHubLog = .shared) throws -> Feed {
        log.debug(.feed, "decoding feed: \(data.count) bytes")
        if data.isEmpty {
            log.error(.feed, "feed data is empty (0 bytes): the download probably failed or returned nothing")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let feed = try decoder.decode(Feed.self, from: data)
            let blockCount = feed.plans.reduce(0) { $0 + $1.blocks.count }
            log.info(.feed, "feed decoded: version=\(feed.version) plans=\(feed.plans.count) blocks=\(blockCount) dates=\(feed.plans.map(\.date))")
            if feed.version > supportedVersion {
                log.warning(.feed, "feed is schema version \(feed.version) but this build understands version \(supportedVersion); fields may be misread, update the app")
            }
            return feed
        } catch {
            log.error(.feed, "feed decode failed (\(data.count) bytes): \(describe(error))")
            throw error
        }
    }

    /// A one-line, plain-language reason for a decoding failure, with the path to the broken field.
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        func path(_ keys: [any CodingKey]) -> String {
            keys.reduce("") { $0 + ($1.intValue.map { "[\($0)]" } ?? ($0.isEmpty ? "" : ".") + $1.stringValue) }
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing field '\(key.stringValue)' at \(path(context.codingPath + [key]))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "wrong or null value at \(path(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            let at = context.codingPath.isEmpty ? "the top level (is it JSON at all?)" : path(context.codingPath)
            return "bad data at \(at): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}

/// One "day's" plan. Its blocks carry the plan's date in their `id`.
struct Plan: Decodable, Equatable, Sendable {
    let date: String
    let blocks: [Block]

    private enum CodingKeys: String, CodingKey {
        case date, blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(String.self, forKey: .date)
        self.date = date
        blocks = try container.decode([Block.Wire].self, forKey: .blocks)
            .map { Block(wire: $0, date: date) }
    }
}

/// One scheduled block of time within a plan.
struct Block: Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case work
        case `break`
    }

    enum Status: String, Decodable, Sendable {
        case planned, done, failed, skipped, missed
    }

    let date: String
    let row: Int
    let start: Date
    let end: Date
    let task: String
    let priority: String
    let doneTest: String
    let actualEnd: String?
    /// `nil` when the feed's status is missing, `null` or not one we know.
    let status: Status?
    let kind: Kind
    /// Defaults to `false`: the generator doesn't write `private` yet.
    let isPrivate: Bool

    var id: String { "\(date)#\(row)" }

    /// The block as it appears in `feed.json`, before the plan's date is attached.
    struct Wire: Decodable {
        let row: Int
        let start: Date
        let end: Date
        let task: String
        let priority: String
        let doneTest: String
        let actualEnd: String?
        let status: Status?
        let kind: Kind
        let isPrivate: Bool

        private enum CodingKeys: String, CodingKey {
            case row, start, end, task, priority, status, kind
            case doneTest = "done_test"
            case actualEnd = "actual_end"
            case isPrivate = "private"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            row = try c.decode(Int.self, forKey: .row)
            start = try c.decode(Date.self, forKey: .start)
            end = try c.decode(Date.self, forKey: .end)
            task = try c.decode(String.self, forKey: .task)
            priority = try c.decode(String.self, forKey: .priority)
            doneTest = try c.decode(String.self, forKey: .doneTest)
            actualEnd = try c.decodeIfPresent(String.self, forKey: .actualEnd)
            status = try? c.decode(Status.self, forKey: .status)
            kind = try c.decode(Kind.self, forKey: .kind)
            isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        }
    }

    init(wire: Wire, date: String) {
        self.date = date
        row = wire.row
        start = wire.start
        end = wire.end
        task = wire.task
        priority = wire.priority
        doneTest = wire.doneTest
        actualEnd = wire.actualEnd
        status = wire.status
        kind = wire.kind
        isPrivate = wire.isPrivate
    }
}
