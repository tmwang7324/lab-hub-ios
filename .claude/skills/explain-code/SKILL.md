---
name: explain-code
description: Build a self-contained interactive HTML page that teaches a piece of code or a code change, with background, intuition diagrams, a guided walkthrough and a 5-question quiz. Use when Thomas asks to "explain this", "explain the diff/commit/PR", "teach me this file", "make an explainer", or right after Claude writes new Swift in this repo, since he is learning Swift here.
---

# Explain Code

Adapted from Geoffrey Litt's `explain-diff` skill (https://gist.github.com/geoffreylitt/a29df1b5f9865506e8952488eac3d524). Changes from the original: it also explains whole files or folders, not just diffs, and it teaches Swift to someone who already knows Python, TypeScript and Java.

## Input

One of:
- a commit, range, branch or PR → explain the **change** (`git diff`, `git show`)
- a file or folder → explain the **code as it is now**
- nothing → the last commit

Read the surrounding code before writing, so the explanation matches what the code actually does. Never describe behavior you didn't verify in the source.

## The reader

Thomas: a full-stack developer (Python, TypeScript/React, Java) who is **new to Swift, SwiftUI and WidgetKit**. Map each Swift idea to the closest one he knows, for example:
- `struct` value semantics vs. Java objects
- optionals (`?`, `if let`, `guard let`) vs. TypeScript `undefined` checks
- `async`/`await` and `Task` vs. JS promises
- `@State` / `@Observable` vs. React state
- protocols vs. Java interfaces
- `Codable` vs. `JSON.parse` plus a type

Say plainly when Swift has no close equivalent.

## Page structure

One long page with a table of contents at the top. No tabs.

1. **Background.** Skippable, beginner-friendly context: what this part of the app is for and where it sits (app, widget extension, or shared code). Then the narrower context for this code or change.
2. **Intuition.** The core idea before any code. Use a concrete example with toy data, for instance a two-block `feed.json` traced through the code. Include at least one diagram built in HTML/CSS (boxes and arrows, a timeline, a state flow). No ASCII art.
3. **Code walkthrough.** The important parts in an order that builds understanding, not file order. For each part: a short excerpt, what it does, and a **Swift note** for any syntax that is new to him. Group trivial code (imports, boilerplate) into one line.
4. **Quiz.** 5 multiple-choice questions of medium difficulty that test understanding, not recall. At least 2 should be about Swift itself, for example "what happens if this optional is nil?". Clicking an answer immediately shows right/wrong and a one-to-two-sentence explanation.

## Format

- One self-contained `.html` file: inline CSS and JS, no external dependencies, readable on a phone.
- Code blocks are `<pre><code>` with `white-space: pre` (or `pre-wrap`) set. Check every block before saving.
- Use callouts for key concepts, definitions and edge cases.
- Save to `explanations/YYYY-MM-DD-<short-slug>.html` in this repo (the folder is gitignored). If an artifact tool is available, publish the page as an artifact as well so it opens on his phone.
- End by telling him the file path or link, plus one sentence on the most important idea to take away.

## Length

Prefer clarity over coverage. A single commit should come out to a page he can read in about 10 minutes. If the code is large, explain the main path and list the rest under "Not covered here".
