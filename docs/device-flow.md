# Device Flow

OAuth Device Flow is the opt-in auth mode for apps whose end-users
already have GitHub accounts — developer tools, internal company apps,
CLI utilities. Each issue is authored by the user themselves; no relay
needed.

## When to use it

- ✅ Your users have GitHub accounts.
- ✅ You want issues attributed to specific users (replies notify them
  directly).
- ✅ You don't want to deploy or maintain a relay.

## When NOT to use it

- ❌ Consumer app where most users don't have GitHub. Use `.relay` instead.
- ❌ You need image attachments. GitHub has no public attachment upload
  API; the SDK throws `.attachmentNotSupportedInDeviceFlow` if attachments
  are present in the report. The form already hides the attachment button
  when `auth == .deviceFlow`.

## One-time GitHub OAuth App setup

1. Visit **github.com/settings/applications/new** (or your org's apps
   page → **New OAuth App**).
2. **Application name**: "<YourApp>".
3. **Homepage URL**: any URL — required but unused in Device Flow.
4. **Authorization callback URL**: any URL — required but unused.
5. **Enable Device Flow**: ✅ check.
6. Click **Register application**.
7. Copy the **Client ID** (looks like `Iv1.abc123`).

You don't need a Client Secret for Device Flow.

## Configure the SDK

```swift
GitTickets.configure(.init(
    repo: RepoCoordinate(owner: "me", name: "MyApp", visibility: .public),
    auth: .deviceFlow(clientID: "Iv1.abc123", scopes: [.publicRepo])
))
```

Use `.repo` instead of `.publicRepo` when the target repo is private.

## What the user sees

1. Tap "Report an Issue…" → form opens.
2. Fill in title + body, tap Submit.
3. SDK detects no token in the Keychain → presents `DeviceFlowSheet`.
4. Sheet shows a short user code (e.g. `ABCD-1234`) and opens
   `ASWebAuthenticationSession` to `github.com/login/device` with the code
   pre-filled. Ephemeral browser session — no cookies leak in.
5. User approves on GitHub.
6. Sheet (which has been polling) detects the token, writes it to the
   Keychain, dismisses the auth modal, and re-submits the report.

The next submission reuses the stored token — no auth flow.

## Token revocation

If the user revokes the OAuth grant from
**github.com/settings/applications**, their next submission gets a 401
from the GitHub Issues API. The SDK detects this, deletes the dead token,
and throws `.deviceFlowNotAuthorized` — which the form catches and
re-presents the auth sheet.

## Limitations

- **No image attachments.** GitHub has no public attachment upload API
  and Device Flow has no relay-side storage. The attachment UI is hidden;
  programmatic callers get `.attachmentNotSupportedInDeviceFlow`.
- **Labels may silently drop.** If the user lacks `Issues: Write` on the
  target repo, GitHub creates the issue but drops the labels from the
  request. `SubmittedIssue.missingLabels` surfaces this — callers that
  depend on labels for filtering should check it.
- **No anonymous reports.** Every issue is attributed to the user. For
  anonymous, use `.relay`.
