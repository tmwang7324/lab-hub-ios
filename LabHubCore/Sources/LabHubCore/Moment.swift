// The Moment: what the lock screen shows at a given instant. See CONTEXT.md.

import Foundation

/// What the lock screen shows at one instant.
///
/// `text` is the display text for the surface to show.
///
/// WARNING: until ticket #7 lands, `text` is the block's task verbatim, even for a private block
/// (`isPrivate`). Don't put a `Moment` on a surface that shows without unlocking before then.
public enum Moment: Equatable, Sendable {
    /// Inside a work block.
    case inBlock(text: String, end: Date)
    /// Inside a break.
    case inBreak(text: String, end: Date)

    /// The one entry point: feed bytes plus an instant give the Moment.
    ///
    /// Returns `nil` when no block is current. Tickets #4 to #6 replace that with the waiting,
    /// nothing-left and can't-refresh Moments.
    ///
    /// Throws if the feed can't be decoded. Everything it does is logged to `log` (block ids only, never plan text).
    public static func resolve(feedData: Data, at instant: Date, log: LabHubLog = .shared) throws -> Moment? {
        let feed = try Feed.decode(feedData, log: log)
        return resolve(feed: feed, at: instant, log: log)
    }

    static func resolve(feed: Feed, at instant: Date, log: LabHubLog) -> Moment? {
        let stamp = Self.stamp(instant)
        // A block is current from its start up to, but not including, its end. A block whose end is
        // not after its start therefore never matches. Plans are not treated separately.
        let current = feed.plans.flatMap(\.blocks).filter { $0.start <= instant && instant < $0.end }

        guard let block = current.first else {
            log.info(.moment, "resolve at \(stamp): no block is current")
            return nil
        }
        if current.count > 1 {
            // Overlap is a mistake in the vault (CONTEXT.md, Plan). Use the first, but say so.
            log.warning(.moment, "resolve at \(stamp): \(current.count) blocks overlap (\(current.map(\.id).joined(separator: ", "))); using \(block.id)")
        }
        log.info(.moment, "resolve at \(stamp): in \(block.kind.rawValue) block \(block.id) until \(Self.stamp(block.end))")

        switch block.kind {
        case .work: return .inBlock(text: block.task, end: block.end)
        case .break: return .inBreak(text: block.task, end: block.end)
        }
    }

    /// A time for the log, in the phone's own time zone with its offset, e.g. `2026-11-20T10:00:00-05:00`.
    private static func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: .current))
    }
}
