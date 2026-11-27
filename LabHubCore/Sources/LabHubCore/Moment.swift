// The Moment: what the lock screen shows at a given instant. See CONTEXT.md.

import Foundation

/// What the lock screen shows at one instant.
///
/// `text` is the lock screen text for the block the Moment names. For a private block it is always
/// `Moment.busyText`, never the task, so any surface (widget, Live Activity, app) can show a Moment
/// without unlocking and leak nothing. The private rule lives here and nowhere else (ADR 0003).
public enum Moment: Equatable, Sendable {
    /// Inside a work block.
    case inBlock(text: String, end: Date)
    /// Inside a break.
    case inBreak(text: String, end: Date)
    /// No block is current, but one is still to come: the Next block (CONTEXT.md), with its times.
    case waiting(text: String, start: Date, end: Date)
    /// No block is current or still to come (CONTEXT.md, Nothing left). It covers both "done for
    /// today" and "no plan today".
    case nothingLeft
    /// The feed is stale and has no current or future block. A stale feed never claims nothing is
    /// left, because the phone may simply have failed to fetch today's plan: the surface should send
    /// the user to the app instead.
    case cantRefresh

    /// What a private block shows instead of its task (CONTEXT.md, Private block).
    public static let busyText = "Busy"

    /// The one entry point: feed bytes plus an instant give the Moment.
    ///
    /// Throws if the feed can't be decoded. Everything it does is logged to `log` (block ids only, never plan text).
    public static func resolve(feedData: Data, at instant: Date, log: LabHubLog = .shared) throws -> Moment {
        let feed = try Feed.decode(feedData, log: log)
        return resolve(feed: feed, at: instant, log: log)
    }

    static func resolve(feed: Feed, at instant: Date, log: LabHubLog) -> Moment {
        let instantText = Self.formattedForLog(instant)
        // Plans are not treated separately: a block from yesterday's or tomorrow's plan counts the same.
        let blocks = feed.plans.flatMap(\.blocks)

        // A stale feed still shows its blocks; it only changes what "nothing left" becomes.
        let isStale = feed.isStale(at: instant)
        if isStale {
            let hours = Int(feed.age(at: instant) / 3600)
            log.warning(.moment, "resolve at \(instantText): feed is stale, generated \(Self.formattedForLog(feed.generatedAt)) (\(hours)h ago, limit \(Int(Feed.staleAfter / 3600))h)")
        }

        if let block = currentBlock(in: blocks, at: instant, instantText: instantText, log: log) {
            log.info(.moment, "resolve at \(instantText): in \(block.kind.rawValue) block \(block.id)\(Self.privateNote(block)) until \(Self.formattedForLog(block.end))")
            switch block.kind {
            case .work: return .inBlock(text: displayText(for: block), end: block.end)
            case .break: return .inBreak(text: displayText(for: block), end: block.end)
            }
        }

        if let next = nextBlock(in: blocks, after: instant) {
            log.info(.moment, "resolve at \(instantText): no block is current; waiting for \(next.id)\(Self.privateNote(next)) at \(Self.formattedForLog(next.start))")
            return .waiting(text: displayText(for: next), start: next.start, end: next.end)
        }

        if isStale {
            log.info(.moment, "resolve at \(instantText): no block is current and none is still to come, and the feed is stale; can't refresh")
            return .cantRefresh
        }
        log.info(.moment, "resolve at \(instantText): no block is current and none is still to come; nothing left")
        return .nothingLeft
    }

    /// The lock screen text for a block: its task, or "Busy" if it is private. Every Moment that names
    /// a block gets its text from here, so no path can skip the private rule.
    private static func displayText(for block: Block) -> String {
        block.isPrivate ? busyText : block.task
    }

    /// Marks a private block in the log, so "why does it say Busy?" has an answer there.
    private static func privateNote(_ block: Block) -> String {
        block.isPrivate ? " (private)" : ""
    }

    /// The block whose range holds the instant. A block is current from its start up to, but not
    /// including, its end, so a block whose end is not after its start never matches.
    private static func currentBlock(in blocks: [Block], at instant: Date, instantText: String, log: LabHubLog) -> Block? {
        let current = blocks.filter { $0.start <= instant && instant < $0.end }
        guard let block = current.first else { return nil }
        if current.count > 1 {
            // Overlap is a mistake in the vault (CONTEXT.md, Plan). Use the first, but say so.
            log.warning(.moment, "resolve at \(instantText): \(current.count) blocks overlap (\(current.map(\.id).joined(separator: ", "))); using \(block.id)")
        }
        return block
    }

    /// The Next block: the earliest block that hasn't started yet, whichever plan it belongs to.
    ///
    /// A block whose end is not after its start can never be current, so it is never next either.
    /// When two blocks start at the same instant (an overlap), the first in feed order wins.
    private static func nextBlock(in blocks: [Block], after instant: Date) -> Block? {
        blocks
            .filter { instant < $0.start && $0.start < $0.end }
            .min { $0.start < $1.start }
    }

    /// A time for the log, in the phone's own time zone with its offset, e.g. `2026-11-20T10:00:00-05:00`.
    private static func formattedForLog(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: .current))
    }
}
