# A scheduled Action moves the Live Activity between blocks

The lock screen's big view is a Live Activity, which, unlike a widget, cannot be given a timeline in advance. Each update sets its stale date to the current block's end, so the phone redraws it as "Ended · next: <task> · <time>" on the dot with no network. The start of the next block needs a push: a scheduled Action runs every 20 minutes from 7 AM to 1 AM, reads the feed, and resends the current state every run (stateless: high priority at a block boundary, `apns-priority: 5` otherwise), so a skipped run or a dropped push heals itself and the Action needs no storage. It also restarts the activity before iOS's 8-hour limit. The next block can appear up to about 20 minutes late, plus GitHub's cron delay; tapping an end reminder opens the app, which updates the activity at once.

## Considered Options

- **App and feed-changed push only:** free, but the activity could sit on "Next: …" for hours.
- **Outside scheduler every minute (e.g. a Cloudflare Worker cron):** near-exact, but new infrastructure and a second home for the APNs key. Moving the same logic there later is a small change if the delay bothers in practice.

## Consequences

- About 1,500 Actions minutes a month on a private repo; check the plan's included minutes.
- The app also writes its Live Activity push-to-start and update tokens to repo variables, as with the device token (ADR 0002).
- Spike: check whether iOS 26 can schedule a Live Activity to start at a future time, which would make this Action unnecessary.
- Pushes carry only block IDs (`<date>#<row>`) and times, never plan text. The Live Activity view looks the text up in the App Group feed cache and applies the same lock screen text rule as the widget, so the private rule lives only in `LabHubCore`. If the cached block's times don't match the push (the plan changed and the phone hasn't fetched yet), the view shows "Block · until <end>" and the phone fetches. Spike: confirm a Live Activity view can read the App Group cache.
