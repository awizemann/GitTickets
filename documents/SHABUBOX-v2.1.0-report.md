# GitTickets v2.1.0 — report for the ShabuBox team

**Released:** 2026-07-26 · **Tag:** `v2.1.0` → commit `0041739` · **Repo:** https://github.com/awizemann/GitTickets

v2.1.0 is tagged and pushed. It answers all six of your requests. Five needed
code; one turned out to already exist in 2.0.0 and needed only documentation.

---

## 1. Repin

```swift
.package(url: "https://github.com/awizemann/GitTickets.git", from: "2.1.0")
```

If you already use `upToNextMajorVersion` from 2.0.0, **you get 2.1.0
automatically** — no manifest change needed. This is unlike the 1.x → 2.0.0
jump, which required a deliberate bump because the platform floor moved.

**Platform floor is unchanged: macOS 14 / iOS 18.** Nothing about your
deployment target needs to move.

**No public API was removed or changed in signature.** We proved this rather
than asserting it: a throwaway consumer package resolves `from: "2.1.0"`
against the public remote and compiles every call site you named as a
non-goal — `GitTickets.configure`, `.relay(url:sharedSecret:)`,
`GitTicketsCommands`, `DiagnosticsPolicy(redactors:)` with an explicit array,
`PrivacyPolicy(bannerText:requireExplicitConsent:)`, and an exhaustive
`switch` over `AuthMode`. It builds and runs green.

---

## 2. What to change on your side

Four changes, in descending order of value to you.

### 2.1 Turn on generic attachment names — your top priority

```swift
let privacy = PrivacyPolicy(
    bannerText: "Reports are filed to a public repository.",
    requireExplicitConsent: true,
    attachmentNames: .generic          // ← new
)
```

Attachment links now render as `image 1` / `attachment 2` instead of
`Tax Return 2024.png`. Numbering is a single 1-based index across the whole
list, so the Nth link corresponds to the Nth attachment — triage still works.

**Default is `.filename`** (existing behavior), so this is opt-in and nothing
changes for you until you set it.

**This gives real assurance, not cosmetic assurance.** We verified the
filename does not reach the public URL either: both relay templates build the
object key as `gittickets/<random-uuid>.<ext>` and discard the submitted name
(`relay/cloudflare/src/lib/r2.ts:30-32`, `relay/vercel/api/_lib/blob.ts:38-39`).

**One honest caveat.** The SDK still sends the real filename to *your relay*
in the multipart `Content-Disposition` header
(`Sources/GitTickets/Auth/Relay/RelayClient.swift:216`) — the relay's parser
requires it. Neither relay template logs it, and both throw it away when
building the key. But it does transit your infrastructure, so if you have
added your own request logging, check that it does not capture
`Content-Disposition`. Nothing public exposes it.

### 2.2 Drop your custom path redactor — and read this about ordering

`DiagnosticsRedactor.absolutePath` is now built in **and on by default**. It
replaces `/Users/...`, `~/...`, `/Volumes`, `/private`, `/var`, `/tmp`,
`/Applications` and `/Library` paths — **including the trailing filename** —
with `[path redacted]`. If you rely on the default `DiagnosticsPolicy`, you
get it with no code change.

**Two things you need to know before you delete your own redactor:**

**(a) `.absolutePath` is a floor, not a guarantee. A space terminates the
match.**

```
/Users/ana/Documents/Tax Return.pdf   →   [path redacted] Return.pdf
```

The account name always goes. A filename *containing spaces* partially
survives. Your own examples ("Tax Return 2024.png") have spaces, so this
will affect you. Allowing spaces in the pattern would let the match run off
into surrounding log text and eat the triage information, which we judged
worse. Backslash-escaped separators (`\/Users\/...`) are not matched either.
Both limits are pinned by tests so they stay visible rather than silently
regressing.

If that residue matters to you, keep a custom redactor for your own filename
patterns — but see (b) for where to put it.

**(b) Redactor order is load-bearing, and appending is the wrong instinct.**

Redactors run in sequence over already-redacted text. A replacement that
inserts spaces (`[ip redacted]`, `[email redacted]`) can truncate a later
pattern mid-match. So **do not** write:

```swift
// WRONG — yours runs last, after .absolutePath has already truncated the match
DiagnosticsPolicy(redactors: DiagnosticsRedactor.recommended + [myRedactor])
```

If your redactor must win against a built-in, construct the array manually
and place yours **before** that built-in:

```swift
DiagnosticsPolicy(redactors: [.bearerToken, myRedactor, .absolutePath, .email, .ipv4, .ipv6])
```

`DiagnosticsRedactor.recommended` is now public so you can see the exact
ordered built-in set rather than guessing. Full detail in `docs/diagnostics.md`.

**To opt out entirely**, pass the old explicit array:
`DiagnosticsPolicy(redactors: [.bearerToken, .email, .ipv4, .ipv6])`.

### 2.3 Move the shared secret out of source

```swift
guard let secret = SharedSecret(
    infoPlistKey: "GitTicketsSharedSecret",
    encoding: .hex
) else {
    fatalError("Shared secret missing or malformed — fix the build, not the runtime.")
}
```

Intended setup is a **gitignored `.xcconfig`** feeding an `Info.plist` build
setting. `encoding` is deliberately required rather than sniffed: a string
like `abcdef` is valid as *both* hex and base64, and guessing would silently
derive the wrong key.

**Be clear-eyed about what this buys.** It keeps the secret out of git. It
does **not** keep it out of an attacker's hands — `Info.plist` ships as
plaintext in the app bundle and `plutil -p` reads it in one command. It gates
casual relay abuse; it guards nothing against a motivated attacker. Treat the
relay secret as a rate-limiting measure, not a security boundary.

### 2.4 Delete your manual label-checking runbook step

See §3 below — this capability already shipped in 2.0.0.

---

## 3. Ask #5 was already built — you can delete a manual process today

You asked us to detect labels GitHub silently drops. **v2.0.0 already does
this, on both auth paths.** We verified the whole chain in the shipped code:

| Step | Location (at v2.1.0) |
|---|---|
| Relay response parses `appliedLabels` | `Auth/Relay/RelayPayload.swift:58` |
| Requested vs applied compared, case-insensitively | `Auth/Relay/RelaySubmitter.swift:314-319` |
| `.warning` logged naming the dropped labels | `Auth/Relay/RelaySubmitter.swift:106-113` |
| Public `SubmittedIssue.missingLabels` | `PublicAPI/Models.swift:177` |
| Device-flow path mirrors all of it | `Auth/DeviceFlow/DeviceFlowSubmitter.swift:97-115` |

All three mechanisms you asked for — a log line, a warning, and a non-fatal
response field — exist today. The comparison is case-insensitive because
GitHub normalizes label case server-side.

**The real gap was discoverability, not capability.** It was documented in
`docs/device-flow.md` and the wiki, but *not* in the relay docs — and you are
a relay adopter, so you never saw it. v2.1.0 cross-references it from
`docs/relay-deployment.md` under troubleshooting. That is the only change
this ask produced.

**To wire it up:**

```swift
let config = Configuration(repo: repo, auth: auth, logger: myLogger)
// ...
let issue = try await submit(report)
if let missing = issue.missingLabels, !missing.isEmpty {
    // GitHub dropped these — fall back to a title prefix, or surface a warning
}
```

**Treat `nil` as *unknown*, not as *all applied*.** `nil` means the relay did
not report `appliedLabels` at all — usually an older relay deployment. An
empty array means "we checked, nothing was dropped." Conflating the two is
the one way to misuse this API.

The usual cause of dropped labels is the GitHub App lacking push permission
on the target repo; GitHub accepts the issue and silently discards the labels
rather than erroring.

---

## 4. Three corrections to premises in your request

We are flagging these because acting on the original assumptions would waste
your time.

**(a) Your line reference was wrong.** You cited `GitTicketsView.swift:135`
as the attachment cell. At v2.0.0 that line is the header icon
(`theme.headerIcon().frame(width: 26, height: 26)`). The actual pending-
attachment cell is `ScreenshotThumbnail`, a **48pt** tile
(`UI/SwiftUI/ScreenshotThumbnail.swift:83`). The feature request was still
justified — 48pt is genuinely too small to confirm what you are about to
publish — but the premise was inaccurate, so v2.1.0's preview sheet is built
against the real cell.

**(b) `.absolutePath` will not fully redact your example filenames.** Covered
in §2.2(a). We are repeating it here because your request implied it would.

**(c) A 2.1.0 pin auto-resolves.** Covered in §1. If you were budgeting time
for a migration like the 1.x → 2.0.0 one, you do not need it.

---

## 5. Security fix worth your attention

`SharedSecret(hex:)` and `SharedSecret(base64:)` previously turned malformed
input into a **usable-but-wrong HMAC key**. Confirmed against the shipped
2.0.0 tag; present since 1.x. Three cases:

| Input | Old behavior |
|---|---|
| `SharedSecret(hex: "")`, `"   "`, `"0x"` | non-nil, **zero-byte key** — zero digits satisfied the even-length check |
| `SharedSecret(hex: "+1+1")` | bytes `01 01` — `UInt8(_:radix:)` honours a leading `+` |
| `SharedSecret(base64: "====")` | **one-byte `0x00` key** — `Data(base64Encoded:)` decodes padding-only input to a single zero byte, which is non-empty and passed the guard |

**No secret leaked.** The risk is that a misconfiguration produced a
degenerate, publicly-guessable signing key that **failed silently rather than
loudly**. If only the app side is degenerate, submissions simply break — you
would notice. **The dangerous case is both sides degenerate:** the relay
appears to work while providing no authentication at all, so the shared
secret stops gating relay abuse entirely.

All such inputs now return `nil`. No legitimate secret is newly rejected —
verified that `0b11`, `0xdeadbeef` and `3q2+7w==` still decode unchanged.

**Action for you:** if you construct a `SharedSecret` from a build variable,
check that your failure path is `fatalError`/loud rather than a silent
fallback. After upgrading, a previously-degenerate config becomes `nil` — you
want that to be obvious at launch, not a mystery 401 later.

Also fixed: attachment link text could break out of its markdown link via
newlines. APFS permits newlines in filenames, and `escapeMarkdownLinkText`
escaped `\`, `[` and `]` but nothing for CR/LF — so a crafted filename
containing a blank line ended the link early and let injected markdown render
as real formatting. CR/LF now fold to spaces. Relevant to you specifically
because your users' filenames become public content.

---

## 6. Verification behind this release

- Local: `swift build` **0 warnings**; `swift test` **290 executed, 0 failures**.
- CI run `30214507209` on `0041739`, both jobs green:
  **macOS** 290 executed / 6 skipped / 0 failures;
  **iOS** 278 executed / 30 skipped / 0 failures (Xcode 26.3, iOS 18.6 simulator).
- Tag proved after pushing: a throwaway consumer resolved `from: "2.1.0"`
  from the **public** remote with a cold SPM cache → version 2.1.0 @
  `004173971607eae2`, then built **and ran** assertions against the published
  artifact.

Order was deliberate: merge → push → wait for CI green → tag → prove the tag.

---

## 7. Known gaps — things this release does *not* fix

Listed so you do not discover them yourself.

- **The built-in form cannot add a screenshot.** `GitTicketsView` holds
  screenshot state, renders it, offers Remove, and submits it — but nothing
  assigns it, and there is no "Add Screenshot" button. `ScreenshotCapture.capture()`
  is public and works if you drive it from your own UI. If you were relying on
  the built-in form for this, you cannot yet. Tracked internally.
- **`SharedSecret` has no minimum-length or entropy check.** A one-byte valid
  hex secret is still accepted. Tightening this is a major-version policy call.
- Three known UI defects in the attachment list (an index-identity `ForEach`
  crash edge on removal, per-keystroke re-decode of every attachment, and a
  sub-44pt Remove target). None are new in 2.1.0.

---

## Questions

Open an issue on the GitTickets repo, or reply through the usual channel.
