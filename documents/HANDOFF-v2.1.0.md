# GitTickets v2.1.0 — session handoff

**Written:** 2026-07-26 · **Repo:** `/Users/awizemann/Developer/GitTickets`
**Branch:** `release/v2.1.0` at `e1e361a` · **Not pushed. Not tagged.**

Paste this whole file into the new session as context.

---

## 1. Where we are in one paragraph

GitTickets v2.1.0 is an additive minor answering six requests from the
ShabuBox integration (a privacy-first macOS document vault whose in-app
reports file to a **public** repo). All four code phases are written,
merged into `release/v2.1.0`, and verified. Version metadata and all docs
are written but **uncommitted**. What remains is: commit the docs, push
`main`, wait for CI to go green, then tag `v2.1.0` — in that order, for
reasons in §5.

**Alan has NOT yet authorized the push or the tag.** Ask before either.

---

## 2. The six asks and their status

| # | Ask | Status |
|---|-----|--------|
| 1 | Suppress attachment display names (**their top priority**) | ✅ Done — `PrivacyPolicy.attachmentNames = .generic` |
| 2 | Shared secret without committing it | ✅ Done — `SharedSecret(infoPlistKey:encoding:bundle:)` |
| 3 | Built-in absolute-path redactor + safe ordering | ✅ Done — `.absolutePath`, on by default |
| 4 | Full-size preview of pending attachment | ✅ Done — `AttachmentPreviewSheet` |
| 5 | Detect labels GitHub silently dropped | ✅ **Already existed in 2.0.0** — docs only |
| 6 | Actually tag and push 2.1.0 | ⏳ **OUTSTANDING — this is the remaining work** |

### Ask #5 needed no code — say this to ShabuBox

v2.0.0 already does all of it, on both auth paths. Verified:
`RelayPayload.swift:58` parses `appliedLabels`; `RelaySubmitter.swift:105`
compares case-insensitively; `:106-112` logs `.warning` naming the drops;
`Models.swift:177` exposes public `SubmittedIssue.missingLabels`;
`DeviceFlowSubmitter.swift:97-114` mirrors it. The only real gap was
**discoverability** — it was documented in `docs/device-flow.md` and the
wiki but not the relay docs, and ShabuBox is a relay adopter. Now
cross-referenced in `docs/relay-deployment.md`. **They can delete their
manual runbook step today**: wire `Configuration.logger`, read
`SubmittedIssue.missingLabels`, treat `nil` as *unknown* not *all applied*.

---

## 3. Exact repo state

**Committed on `release/v2.1.0`** (7 commits ahead of `main`):

```
e1e361a Merge P3 (attachment preview)
59c68e2 fix(ui): preview honesty + accessibility
d11ee38 Merge P4 (attachment names)
b0f79b3 feat(privacy): AttachmentNameDisplay
1f21eba Merge P2 (SharedSecret Info.plist)
ef74e22 feat(auth): SharedSecret(infoPlistKey:)
... plus P1 (absolutePath redactor)
```

**Uncommitted — my P5 work, needs one commit:**

- `Sources/GitTickets/Networking/UserAgent.swift` — sdkVersion 2.0.0 → 2.1.0 (+ doc example)
- `CHANGELOG.md` — full `[2.1.0]` entry + link refs
- `README.md` — status section
- `docs/diagnostics.md` — `.absolutePath`, `.recommended`, ordering hazard, limitations
- `docs/getting-started.md` — Info.plist secret pattern
- `docs/privacy.md` — attachment filenames section
- `docs/relay-deployment.md` — missing-labels troubleshooting (ask #5)

**Do NOT commit** (Memophant-managed, Alan commits these himself):
`.memory/`, `TASKS.md`, `tasks/`, `wiki/`, `design/`, `documents/`.
Also leave the pre-existing modifications to `AGENTS.md`, `CLAUDE.md`,
`GEMINI.md`, `.cursor/`, `.claude/`, `.github/copilot-instructions.md`.

Suggested commit:

```bash
git add CHANGELOG.md README.md docs/ Sources/GitTickets/Networking/UserAgent.swift
git commit -m "docs(release): prep v2.1.0"
```

---

## 4. Verification already done — don't redo it

All run by the orchestrator, not merely claimed by agents:

- `swift build` → **0 warnings**; `swift test` → **290 tests, 0 failures**
- `xcodebuild` generic iOS Simulator → **BUILD SUCCEEDED**
- **Source compatibility proven by building**, not by reading the diff: a
  throwaway consumer package compiles every call site the request named as
  a non-goal — `GitTickets.configure`, `.relay(url:sharedSecret:)`,
  `GitTicketsCommands`, `DiagnosticsPolicy(redactors:)` with the old
  explicit array, `PrivacyPolicy(bannerText:requireExplicitConsent:)`, and
  an exhaustive `switch` over `AuthMode`. Output: `v2.0.0-era call sites
  still compile: 4 true relay`.
- `AuthMode` cases unchanged (`.relay`, `.deviceFlow`, `.mock` — `.mock`
  already existed at v2.0.0 line 94). `GitTicketsCommands.swift` is
  **byte-identical** to v2.0.0.
- Platform floor **unchanged** at macOS 14 / iOS 18, as required.
- Both relays verified: the filename never reaches the upload URL.
  Cloudflare `relay/cloudflare/src/lib/r2.ts:30` →
  `gittickets/${crypto.randomUUID()}.${extensionForMime(mimeType)}`;
  Vercel equivalent. So `.generic` gives **real** assurance, not false.

---

## 5. The remaining work — order matters

```bash
git checkout main && git merge --no-ff release/v2.1.0 && git push origin main
gh run watch <run-id>            # wait for green
git tag -a v2.1.0 -m "..." && git push origin v2.1.0
```

**Push and wait for CI BEFORE tagging.** This is the lesson from v1.1.0,
which was announced in the README and CHANGELOG but never tagged, so
`from: "1.1.0"` failed SPM resolution outright and ShabuBox had to pin
1.0.0. It is also how v2.0.0 was done: CI green first, so the tag
annotation contains measured facts rather than intentions. Ask #6 exists
precisely because this was got wrong once.

**Then prove the tag** with a throwaway consumer using
`from: "2.1.0"` against the public remote — build it and run it. That one
check would have caught v1.1.0's failure instantly.

CI: `.github/workflows/swift.yml`, `macos-15`, Xcode pinned `26.3`,
iOS destination `iPhone 16, OS=18.6`. It went green on the 2.0.0 merge —
macOS 210 executed / 6 skipped, iOS 198 / 30 skipped.

---

## 6. Things to tell ShabuBox

1. **Their line reference was wrong.** `GitTicketsView.swift:135` is the
   header icon (`theme.headerIcon().frame(width: 26, height: 26)`), not the
   attachment cell. The real pending-attachment cell is `ScreenshotThumbnail`
   at **48pt**. Feature still justified; premise inaccurate.
2. **`.absolutePath` is a floor, not a guarantee.** A space ends the match:
   `/Users/ana/Documents/Tax Return.pdf` → `[path redacted] Return.pdf`. The
   account name always goes; a spaced filename partially survives. Their own
   examples ("Tax Return 2024.png") have spaces, so this matters to them.
   **Their custom redactor must go BEFORE `.absolutePath`**, constructed
   manually — *not* `recommended + [theirs]`, since appending puts it last
   where `.absolutePath` has already truncated the match. Documented in
   `docs/diagnostics.md`.
3. **A 2.1.0 pin auto-resolves** for anyone already on `upToNextMajor` from
   2.0.0 — unlike the 1.x → 2.0.0 jump.
4. **Security fix worth their attention:** `SharedSecret(hex:)` /
   `(base64:)` previously turned malformed input into a usable-but-wrong
   HMAC key (`""`/`"0x"` → 0-byte key; `"+1+1"` → `01 01`; `"===="` → 1-byte
   `0x00`). Confirmed against the shipped 2.0.0 tag. Present since 1.x.

---

## 7. Open items NOT in this release

- **`t-66c07278` — the built-in form cannot add a screenshot.**
  `GitTicketsView` holds `screenshot` state, renders it, offers Remove, and
  submits it, but nothing ever assigns it non-nil and there is no "Add
  Screenshot" button. `ScreenshotCapture.capture()` is public and works for
  hosts with their own UI, so this is an unimplemented affordance, not dead
  code — but its doc comment implies the form does it. **Consequence: the
  v2.0.0 ScreenCaptureKit rewrite is still unexercised at runtime.** A prior
  hand-off told Alan to test via "Report an Issue → Add Screenshot"; that
  instruction was wrong. Recommendation: at minimum fix the doc comment.
- Three pre-existing UI defects filed as background task chips by the P3
  agent: index-identity `ForEach` + `remove(at:)` crash edge, per-keystroke
  re-decode of every attachment, sub-44pt Remove target.
- `SharedSecret` has no minimum-length/entropy check — a major-version
  policy call.
- Misnamed test `test_sharedSecretBase64ToleratesEmbeddedWhitespace`
  (`GitTicketsTests.swift:82`) actually tests *surrounding* whitespace.

---

## 8. Process notes that saved this release

- **Three of four sub-agents were handed a stale worktree base** (HEAD at
  the v2.0.0 tag instead of the branch tip). Each caught it only because the
  brief said "verify your base before starting". Keep that instruction in
  every future brief — without it, P4 would have clobbered P1's
  `Policies.swift` work silently.
- **The first `swift test` in a fresh worktree reports 6 failures.** Those
  are the 6 macOS-only snapshot tests recording their gitignored baselines;
  `swift-snapshot-testing` reports a fresh recording as a failure.
  Subsequent runs pass. Two agents burned time misdiagnosing this as
  Keychain/CoreData noise. Pre-empt it in briefs.
- **Treat agent self-reports as claims to verify, not conclusions.** Every
  significant claim in this release was re-checked independently, and doing
  so found: the wrong line reference, the unwired screenshot path, and the
  fact that the relay does *not* leak filenames via the URL (which one agent
  believed unverifiable from this repo — the relay templates are in it).

---

## 9. Memophant note

The Memophant MCP server disconnected mid-session, so the last few task
updates could not be written through the tools. Task files under `tasks/`
may be slightly behind: `t-7a4acd7f`, `t-56dc81bf`, `t-91462076`,
`t-732afe87` are all **done**; `t-9493d988` (this release's final phase) is
still **todo** and is the work in §5.
