// labhub-moment: print the Moment for a feed file at an instant, with the full log on stderr.
//
//   swift run labhub-moment <feed.json> [--at 2026-11-20T10:00:00-05:00] [--quiet]
//
// stdout: one line with the answer, exactly the text the lock screen would show: a private block prints as "Busy".
// stderr: the log (what was decoded, which block, what went wrong). It never has plan text.
// Exit codes: 0 answered, 1 failed (unreadable or invalid feed), 2 bad command line.

import Foundation
import LabHubCore

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let usage = "usage: labhub-moment <feed.json> [--at <ISO-8601 instant, e.g. 2026-11-20T10:00:00-05:00>] [--quiet]"

var path: String?
var instant = Date()
var quiet = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--quiet":
        quiet = true
    case "--at":
        guard let text = arguments.popFirst() else { fail("--at needs a value\n\(usage)", code: 2) }
        guard let parsed = ISO8601DateFormatter().date(from: text) else {
            fail("can't read '\(text)' as a time; use ISO-8601 with an offset, e.g. 2026-11-20T10:00:00-05:00", code: 2)
        }
        instant = parsed
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard path == nil, !argument.hasPrefix("--") else { fail("unexpected argument '\(argument)'\n\(usage)", code: 2) }
        path = argument
    }
}
guard let path else { fail(usage, code: 2) }

let log = LabHubLog(minimumLevel: quiet ? .error : .debug, sinks: [StderrSink()])

let data: Data
do {
    data = try Data(contentsOf: URL(fileURLWithPath: path))
} catch {
    log.error(.feed, "can't read feed file '\(path)': \(error.localizedDescription)")
    exit(1)
}

do {
    let localTimeFormatter = ISO8601DateFormatter()
    localTimeFormatter.timeZone = .current
    let staleNote = { (isStale: Bool) in isStale ? " [stale feed]" : "" }
    switch try Moment.resolve(feedData: data, at: instant, log: log) {
    case .inBlock(let text, let until, let isStale): print("in a block: \(text) (until \(localTimeFormatter.string(from: until)))\(staleNote(isStale))")
    case .inBreak(let text, let until, let isStale): print("in a break: \(text) (until \(localTimeFormatter.string(from: until)))\(staleNote(isStale))")
    case .waiting(let text, let start, _, let isStale): print("waiting: next is \(text) at \(localTimeFormatter.string(from: start))\(staleNote(isStale))")
    case .nothingLeft: print("nothing left")
    case .cantRefresh: print("can't refresh: the feed is stale and has nothing current or still to come")
    }
} catch {
    // The decoder has already logged exactly which field failed.
    exit(1)
}
