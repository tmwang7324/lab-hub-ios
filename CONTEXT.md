# Lab Hub iOS

An iPhone app and lock screen widget that show where you are in your daily plan. They read a feed that a GitHub Action builds from the vault.

## Language

**Feed**:
The `feed.json` file the Action builds. It covers whichever of yesterday's, today's and tomorrow's plans exist, and it is the only thing the app and widget read.
_Avoid_: data, JSON, schedule

**Stale feed**:
A feed whose `generated_at` is more than 26 hours old. Its blocks still show, each marked stale in the Moment so a surface can say it may be out of date, but it never claims nothing is left.
_Avoid_: old data, expired feed

**Feed-changed push**:
The one push the server sends when a new feed is built. It carries no plan data, only the signal to fetch again.
_Avoid_: sync push, update notification

**Plan**:
One day's planning note in the vault, as it appears in the feed: a date, priorities, and an ordered list of blocks. Its blocks never overlap in time; a plan where they do is a mistake in the vault, not something the app has to interpret.
_Avoid_: day, schedule

**Block**:
One row of a plan's table: a task with a start and end time. A block is either a work block or a break.
_Avoid_: event, slot, item

**Break**:
A block for rest or slack (lunch, dinner, buffer, close), not for work.
_Avoid_: gap, free time

**Private block**:
A block whose task is marked `[private]` in the plan. Anywhere that can be seen without unlocking the phone, it shows only as "Busy" and its end time.
_Avoid_: hidden block, secret block

**End reminder**:
The notification that buzzes you a few minutes before a work block ends.
_Avoid_: alert, alarm

**Missed block**:
A work block still marked planned an hour after it ended, because you never responded to its end reminder. It counts as not finished and is recorded with its own status, `missed`, which only the system sets.
_Avoid_: stale block, expired block, dropped block

**Moment**:
What the lock screen shows at a given instant: in a block, in a break, waiting for the next block, nothing left, or can't refresh. The three that show a block also say whether the feed is stale. Nothing left only comes from a fresh feed; a stale one gives can't refresh instead.
_Avoid_: state, status (status is a block's own outcome)

**Next block**:
The earliest block that hasn't started yet, across every plan in the feed. The plan it belongs to doesn't matter, so after a late block ends, the next block can be tomorrow's first one.
_Avoid_: upcoming task

**Nothing left**:
The moment when the feed has no current or future block. It replaces both "Done for today" and "No plan today".
_Avoid_: done for today, no plan today
