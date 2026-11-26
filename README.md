# Lab Hub iOS

iPhone app and lock screen widget for the vault's daily plan. It reads `feed.json` from the `feed` branch of `tmwang7324/Obsidian-Notes`.

Spec: `Projects/Lab Hub/Ideas/Feed Generator Spec.md` in the vault.

## Learning Swift here

Ask Claude Code to **explain** any commit, file or folder. The `explain-code` skill (`.claude/skills/explain-code/`) builds an HTML page with background, diagrams, a walkthrough and a quiz.

## Running it

All the logic lives in `LabHubCore/` and runs without a phone or Xcode project:

```sh
cd LabHubCore
swift test                       # all unit, component, integration and end-to-end tests
swift run labhub-moment Tests/LabHubCoreTests/Fixtures/feed-2026-11-20.json --at 2026-11-20T10:00:00-05:00
```

`labhub-moment` prints the answer on stdout and the full log on stderr. Add `--quiet` to hide the log.

## Your Apple and GitHub values

Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored) and replace every `YOUR_..._HERE`
(team id, bundle id, app group, keychain group, GitHub token). `AppConfig.validate` checks each one and the log says which
is missing, still a placeholder, or the wrong shape. It never prints the token. The APNs `.p8` key is not part of this app:
it lives in the vault repo's Actions secrets (ADR 0002).

## Reading the log when something goes wrong

Every line is `[LEVEL] [category] message`. Categories: `feed` (decoding), `moment` (which block is current),
`config` (your Secrets values), and `network` and `push`, which are reserved for the parts not built yet.

| Where you run it | How to see the log |
| --- | --- |
| Xcode | the debug console |
| Console.app | filter by subsystem `com.labhub.core`, then a category |
| Terminal | `LABHUB_LOG_STDERR=1` prints every line to stderr |

Log lines carry block ids such as `2026-11-20#1`, never plan text (private blocks, ADR 0003) and never a secret.
A "CORS" error can't come from this app: that is a browser rule. Its closest equivalents here are an HTTP 401 or 403
(a bad or under-permissioned token) and an App Transport Security block, and both will show up under `network`.
