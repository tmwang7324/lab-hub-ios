# Server push says "feed changed"; reminders stay local

Plans are often written on short notice, so waiting for the widget's next refresh (15–60 min) is too slow. After the feed Action force-pushes a new `feed.json`, it sends one APNs push to the phone. The push carries no plan data: it only makes the phone fetch the feed, rebuild the widget timeline and reschedule its local end reminders. Reminders are scheduled on the phone, not sent by the server, because GitHub's scheduled runs can start 5–15+ minutes late. App and widget refreshes stay as the backup when a push is dropped.

## Considered Options

- **Refresh only (no push):** a plan edited minutes before a block may not reach the phone in time.
- **Server sends each reminder:** reminder timing would depend on GitHub's cron delays.

## Consequences

- The vault repo holds an APNs auth key (`.p8`) as a secret, and the Action needs the phone's push token.
- The widget-push mechanism (iOS widget push updates versus a silent push to the app) is confirmed in an early spike.
- The app writes its push token to a repo Actions variable (`APNS_DEVICE_TOKEN`, plus `APNS_ENV` = `sandbox` or `production`) whenever iOS issues one, so a reinstall or new phone fixes itself. The phone's GitHub token therefore needs **Variables: read and write** on this repo. A device token alone can't send pushes; the `.p8` key never leaves the repo secrets.
