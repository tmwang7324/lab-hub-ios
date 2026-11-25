# Paid Apple Developer account from v1

v1 is built for a paid Apple Developer Program account, not a free Apple ID. The widget runs in its own process and needs the GitHub token and the cached feed, so the app and widget share a Keychain access group (the token) and an App Group container (the feed cache). The widget fetches on its own.

## Considered Options

- **Free Apple ID with a public feed:** the widget would need no token, but the app expires every 7 days and making `feed.json` public would publish the daily plan, which defeats the private-block marker.
