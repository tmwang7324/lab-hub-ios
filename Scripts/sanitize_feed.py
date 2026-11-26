#!/usr/bin/env python3
"""Turn a real feed.json into a test fixture that is safe for this public repo.

Keeps everything the tests depend on: dates, times, statuses, kinds, rows,
private flags, block counts, and blocks that cross midnight.
Replaces every piece of personal text with a placeholder.

Usage:
  python3 -I Scripts/sanitize_feed.py real-feed.json > LabHubCore/Tests/LabHubCoreTests/Fixtures/feed-2026-11-20.json

Standard library only.
"""
from __future__ import annotations

import json
import re
import sys

PRIORITY_LEVEL = re.compile(r"^\s*(P\d)\b")
# A time range such as "10:30am-4:15pm" or "9:30 PM-12:30 AM". Anything around it is free text and is dropped.
TIME_RANGE = re.compile(r"\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*[-–]\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?", re.IGNORECASE)
# actual_end is free text. Only a clock time, a dash or "Not recorded" may pass.
SAFE_ACTUAL_END = re.compile(r"^(?:(?:~|By )?\d{1,2}:\d{2} ?[AP]M(?: Nov \d+)?|—|Not recorded)$")

# Every field the sanitizer knows how to handle. A field not listed here stops the script, because
# `dict(block)` below would copy it through unchanged and leak whatever text it holds (ADR 0004).
KNOWN_DAY_KEYS = {"date", "p1", "p2", "window", "note_path", "parking_lot_count", "non_negotiables", "blocks"}
KNOWN_BLOCK_KEYS = {"row", "start", "end", "kind", "status", "status_raw", "task", "priority", "done_test",
                    "actual_end", "time_uncertain", "tips"}


def require_known(keys, known: set, where: str) -> None:
    unknown = set(keys) - known
    if unknown:
        sys.exit(f"{where} has fields the sanitizer doesn't know: {sorted(unknown)}. "
                 "Teach sanitize_feed.py to replace their text (and add them to the leak check test) first.")


def sanitize_window(window):
    """Keep the time ranges, drop every word: 'Acme; 4:30-6:30pm bus' becomes '4:30-6:30pm'."""
    if not window:
        return window
    return "; ".join(m.group(0).strip() for m in TIME_RANGE.finditer(window)) or "Window"


def sanitize_actual_end(value):
    if not value or SAFE_ACTUAL_END.match(value):
        return value
    return "Not recorded"


def sanitize_block(block: dict) -> dict:
    require_known(block, KNOWN_BLOCK_KEYS, f"block {block.get('row')}")
    row = block["row"]
    out = dict(block)
    out["task"] = f"Break {row}" if block["kind"] == "break" else f"Task {row}"
    match = PRIORITY_LEVEL.match(block.get("priority") or "")
    out["priority"] = f"{match.group(1)} · Project" if match else ("Priority" if block.get("priority") else block.get("priority"))
    out["done_test"] = f"Done test {row}" if block.get("done_test") else block.get("done_test")
    out["actual_end"] = sanitize_actual_end(block.get("actual_end"))
    out["tips"] = [f"Tip {row}.{i + 1}" for i in range(len(block.get("tips") or []))]
    # status_raw is free text when status is null; keep it only when it is a known status word
    out["status_raw"] = block["status"] if block.get("status") else ("free text" if block.get("status_raw") else None)
    return out


def sanitize_day(day: dict, index: int) -> dict:
    require_known(day, KNOWN_DAY_KEYS, f"day {day.get('date')}")
    out = dict(day)
    out["window"] = sanitize_window(day.get("window"))
    out["p1"] = "Project A" if day.get("p1") else day.get("p1")
    out["p2"] = "Project B" if day.get("p2") else day.get("p2")
    out["note_path"] = f"Plans/{day['date']} Plan.md"
    out["non_negotiables"] = [
        {"text": f"Non-negotiable {i + 1}", "done": item.get("done", False)}
        for i, item in enumerate(day.get("non_negotiables") or [])
    ]
    out["blocks"] = [sanitize_block(b) for b in day["blocks"]]
    return out


def sanitize(feed: dict) -> dict:
    out = dict(feed)
    # a fixed, realistic build time: 6:00 AM New York on the feed's "today"
    out["generated_at"] = f"{feed['today']}T06:00:00-05:00"
    out["source_commit"] = "0000000"
    out["days"] = [sanitize_day(d, i) for i, d in enumerate(feed["days"])]
    out["warnings"] = [f"Warning {i + 1}" for i in range(len(feed.get("warnings") or []))]
    return out


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.dumps(sanitize(json.load(f)), indent=2, ensure_ascii=False))
