# The repo is public, so test fixtures are sanitized real feeds

The tests need realistic feeds: blocks that cross midnight, overlapping blocks, a mix of statuses. Hand-written feeds would miss the shapes the vault actually produces, but real feeds hold personal plan text, and this repo is public. So `Scripts/sanitize_feed.py` turns a real `feed.json` into a fixture that keeps every date, time, status and kind and replaces all text with placeholders (`Task 1`, `Done test 1`). Fixtures are only committed after a leak check against the real feeds. A real feed is never committed as is.

The feed carries a top-level `version` field, which is the schema version. The decoder and fixtures are written against version 1.

## Consequences

- A bug that depends on plan text (an odd character, a very long task) can't be reproduced from a fixture. Reproduce it locally with a real feed and add a placeholder case by hand.
- Every new fixture goes through the sanitizer and the leak check.
