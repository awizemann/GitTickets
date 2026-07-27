# Threat model

What the SDK and relay protect against, what they don't, and where
adopters need to fill in the gaps.

## The threat we DO protect against

### Token extraction from the binary

The relay model exists because GitHub has no anonymous write surface — a
naive design would ship a Personal Access Token or App installation token
inside the app binary. Anyone with `strings` would pull it out, hand it to
their friend, and the only fix is rotating the token and re-shipping every
prior version of your app.

The relay holds the token. The SDK only knows the relay URL and an HMAC
shared secret. Compromise of the SDK side gets the attacker exactly two
things: the ability to post issues to your repo (rate-limited at the
relay) and the ability to read past submissions tagged with the same
`deviceID`.

### Forged submissions

Every relay request carries `X-GitTickets-Signature: sha256=<hex>` and
`X-GitTickets-Timestamp: <unix>`. The signature is HMAC-SHA256 over
`"<timestamp>.<body>"` with the shared secret. The relay rejects:

- Signatures that don't validate (`401 signatureMismatch`).
- Timestamps outside a ±5-minute window (replay defense).

An attacker who doesn't have the shared secret can't post anything.

### Replays of the same submission

The relay enforces idempotency on `POST /report` via the
`X-GitTickets-Idempotency-Key` header (the SDK uses the report's
`submissionID`). Posting the same `(submissionID, body)` twice returns
the original issue. Posting the same `submissionID` with a different body
returns 409.

### Rate-limit abuse

The relay rate-limits per `deviceID` (default 5 reports/hour) and per
client IP (default 50/hour). Adjustable via env vars.

### MITM tampering with the body

HMAC over the raw body bytes means a MITM that modifies the body invalidates
the signature. The relay rejects. (TLS handles confidentiality.)

## The threats we do NOT cover

### Compromise of the relay host

If an attacker pwns your Vercel / Cloudflare account, they have the
shared secret AND the GitHub App installation token. Mitigation: rotate
both, redeploy, and audit recent issues.

### Compromise of the shared secret in your build pipeline

The shared secret needs to be in the SDK at build time. If you commit it
to the public repo by accident, attackers can post arbitrary issues until
you rotate. Mitigations:

- Use a build-time substitution (xcconfig + env var) so the secret isn't
  in source.
- Set the secret as a host-bundle UserDefault populated by an installer or
  first-launch config, not as a literal in `Configuration`.
- Either way: assume the secret is "moderately confidential," not
  "secret-secret."

### Compromise of the user's machine

The SDK stores the per-install `deviceID` and (in Device Flow mode) the
OAuth token in the Keychain. The Keychain is unreadable to other apps
from the same team only because we set `kSecAttrAccessibleAfterFirstUnlock`,
`kSecAttrSynchronizable = false` (so the item doesn't sync via iCloud
Keychain), and namespace the service identifier by host bundle ID so
two same-team apps don't share an item. Root access to the device
defeats this.

### A compromised GitHub issue body

GitHub renders markdown. The SDK's `IssueBodyBuilder` doesn't escape user
input — a hostile user can write arbitrary markdown, including images
loaded from external URLs. For most apps this is low-impact (the audience
is the maintainer, not other users), but consider sanitizing if your repo
is widely read.

### Side-channel data in screenshots

`ScreenshotCapture` renders whatever is on screen — including any sensitive
content the user happens to have there. Capture is always user-initiated; the
SDK never captures in the background.

The form's "Add screenshot" button captures **your application only**, minus the
report window. On macOS the ScreenCaptureKit filter is scoped to the host
process's own windows; on iOS the root view is rendered rather than the whole
window, so a modally presented form and its dimming are left out.

Scoping to the application is a **privacy** decision, not just a usability one.
Excluding one window from the whole display — which is what v2.4.0 did, and what
`SCContentFilter(display:excludingWindows:)` means — still photographs every
other running app, the desktop, and anything else on screen, and that content can
end up attached to a public issue. Reported by an adopter and fixed in v2.5.0.

The shot still contains your own app's real screen, which is the content worth
thinking about below.

**To remove the control entirely**, set
`PrivacyPolicy(allowsScreenshotCapture: false)`. It defaults to `true`. Users can
still attach an image by hand, so this narrows what the SDK can put on screen
without removing the ability to include a picture.

Adopters should:

- Show the screenshot thumbnail before submission (the form does this) and
  offer a full-size preview (it does this too).
- Let the user clear it if they don't want it included (Remove on the tile).
- Consider hiding sensitive subviews while the reporting UI is up.
- Remember the public `ScreenshotCapture.capture()` deliberately captures
  everything, including your own UI — it is for hosts capturing *before* they
  present a reporting surface.

On macOS a capture needs Screen Recording permission. The SDK does not ask for
it and does not nag: if it is missing, the button reports that screenshots
aren't available, points the user at manual image attachment, and submission
proceeds unaffected. The real reason is logged through `Configuration.logger`
for the adopter.

## Compliance posture

- **GDPR / CCPA**: The SDK is "data processor" — the adopter (you, the app
  developer) is the "data controller." You decide what's collected via
  `DiagnosticsPolicy` and what relay/region serves it.
- **App Store Privacy Manifest**: see [`privacy.md`](privacy.md).
- **App Tracking Transparency**: the SDK does not track. `NSPrivacyTracking = false`.

## Audit trail

The repo's `.memory/footguns/` directory carries the full historical
footgun history for this codebase — HMAC re-sign on retry, multipart
header injection, idempotency-key requirements, markdown rendering on the
GitHub side, Keychain iCloud sync default, and others. Browse the
directory directly when doing a threat-model review.
