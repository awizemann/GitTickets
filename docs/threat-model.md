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

The SDK's `ScreenshotCapture` (on iOS) renders the key window — including
any sensitive content the user has on screen. Adopters should:

- Show the screenshot thumbnail before submission (the form does this).
- Let the user clear it if they don't want it included.
- Consider using `UIView.isHidden` on sensitive subviews when offering the
  attach button.

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
