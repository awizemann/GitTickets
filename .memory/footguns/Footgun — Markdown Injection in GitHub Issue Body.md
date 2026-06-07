---
title: Footgun — Markdown Injection in GitHub Issue Body
type: note
permalink: gittickets/footguns/footgun-markdown-injection-in-git-hub-issue-body
tags:
- footgun
- markdown
- bodybuilder
- gfm
---

Two injection vectors in the assembled GitHub issue body when we naively interpolate user-supplied (or relay-supplied) strings into markdown:

1. **Triple-backtick fence collapse.** Wrapping the diagnostics blob in a static ` ```text ` fence assumes the inner content has no `` ``` `` sequences. If any log line or redaction replacement contains a triple backtick, GFM closes the outer fence early and the rest of the diagnostics renders as prose. Worse: the correlation marker after the diagnostics section gets misparsed too.
2. **Markdown link grammar breakage.** `![screenshot](\(url))` with an unescaped `url` whose query string contains a literal `)` truncates the link target: `?key=a)b` makes the markdown link `?key=a` and leaves `b)` dangling outside. Same applies to filename text inside `[\(name)](...)` with `[` or `]` in it.

Discovered in code review of PR 8. R2 / Vercel Blob presigned URLs can legitimately contain `)`; OSLog entries can quote code blocks.

## Observations

- [rule] `IssueBodyBuilder.fenceFor(_:)` scans the content for the longest run of backticks and picks a fence one longer. Three is the minimum; we go higher when needed. GFM closes a fence on the first run of equal or greater length, so the outer must always be strictly longer. #markdown
- [rule] URLs in markdown link targets are percent-encoded for `(` and `)` via `IssueBodyBuilder.escapeURLForMarkdown(_:)`. Use it for every URL that lands inside a markdown link parenthetical. #markdown
- [rule] Markdown link display text is escaped for `[`, `]`, and `\` via `IssueBodyBuilder.escapeMarkdownLinkText(_:)`. Use it for every caller-controlled string that lands inside markdown brackets. #markdown
- [rule] When the issue body contains the correlation marker (or any other parser anchor) at the end, treat that as a contract — test that adversarial inputs upstream don't move or hide the marker. See `IssueBodyBuilderTests.test_diagnosticsContainingBackticksKeepsFenceClosed`. #testing
- [related] Same pattern applies to any text that ends up in a Slack message, a notification body, a chat client, an email — anywhere markdown or markdown-like grammar parses caller-controlled content.

## Relations

- affects [[Wiki — Diagnostics and Screenshots]]
- prevents_recurrence_of "diagnostics ``` collapsing the outer fence"
- prevents_recurrence_of "markdown link broken by `)` in URL"
