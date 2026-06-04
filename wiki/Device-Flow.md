---
title: Device-Flow
type: note
permalink: gittickets-wiki/device-flow
---

# Device Flow

The opt-in auth mode where end-users sign in with their own GitHub account. Issues are authored by the user, not by an App bot.

## When to use it

- **Developer-targeted apps** (CLIs, dev tools, beta utilities) where users having GitHub accounts is reasonable.
- **Internal tools** for small teams where every user is a repo collaborator.
- **Apps with very low submission volume** where running a relay feels like overkill.

When to use **Relay** instead: consumer apps. Anyone without a GitHub account can't use Device Flow.

## Limitations

- **No image attachments.** GitHub has no public attachment upload API and Device Flow has no relay-side storage. UI hides the attach button when `auth == .deviceFlow`; programmatic submission throws `.attachmentNotSupportedInDeviceFlow`.
- **Labels may silently fail** for non-collaborator users (push access requirement on `POST /issues`). The SDK detects this and surfaces a warning in the `SubmittedIssue` response.
- **Token persistence is per-device.** A user who switches devices re-authenticates.

## Setup

1. Create a [GitHub OAuth App](https://github.com/settings/developers) (not a GitHub App — Device Flow uses OAuth Apps).
2. Enable **Device Flow** in the app's settings (checkbox at the bottom).
3. **Authorization callback URL**: anything; not used by Device Flow but the form requires one. `https://localhost` is fine.
4. Note the **Client ID**.

No client secret needed — Device Flow doesn't use one.

## Swift configuration

```swift
GitTickets.configure(.init(
  repo: .init(owner: "alanw", name: "MyDevTool", visibility: .public),
  auth: .deviceFlow(clientID: "Iv1.abcdef1234567890", scopes: [.publicRepo]),
  theme: .default
))
```

For private repos, request `.repo` instead of `.publicRepo`. Note that `.repo` is broad — granting access to all the user's private repos. There's no fine-grained scope for "just this one repo" via OAuth.

## The state machine

```
[User taps "Report an Issue"]
            │
            ▼
[POST github.com/login/device/code]
            │
            ▼
[Show user_code + "Open GitHub" button in SwiftUI sheet]
            │
   (user taps Open GitHub)
            │
            ▼
[ASWebAuthenticationSession opens verification_uri_complete
 with code pre-filled, prefersEphemeralWebBrowserSession=true]
            │                                              │
            │       (background: sheet polls               │
            │        POST github.com/login/oauth/access_token
            │        every interval seconds)
            │                                              │
   (user approves)                                         │
            │                                              │
            ▼                                              ▼
[github.com confirms]                          [Polling receives token]
                                                          │
                                                          ▼
                                          [Store in Keychain, dismiss sheet,
                                           continue with submission]
```

## Polling behavior

- Initial `interval` from the device-code response is the floor between polls (typically 5 seconds).
- `authorization_pending` → keep polling at `interval`.
- `slow_down` → increase `interval` by 5 seconds and continue.
- `expired_token` → surface `.deviceFlowExpired`; user can retry.
- `access_denied` → surface `.deviceFlowDenied`; sheet dismisses.
- Network error → exponential backoff up to 30 seconds.

## Token storage

OAuth user tokens land in Keychain under `com.gittickets.devicetoken.<bundleID>` with `kSecAttrAccessibleAfterFirstUnlock`. Survives reboots, doesn't sync to iCloud.

Subsequent submissions reuse the cached token. If a `401 Bad credentials` comes back, we clear the cache and re-run the Device Flow (one-shot prompt; no silent retries on auth failure).

## iOS UX gotcha

The user does NOT need to manually return to your app after approving on github.com. `ASWebAuthenticationSession` running in our sheet polls in the background while the browser modal is open; when the token arrives, the sheet auto-dismisses and the report posts. This is the magic that makes Device Flow feel like one continuous flow rather than two disconnected apps.

`prefersEphemeralWebBrowserSession = true` is mandatory — without it, the system browser persists a cookie that defeats account-switching across apps.

## macOS UX

Same as iOS but `ASWebAuthenticationSession` opens a system Safari sheet. Behavior is identical from the polling perspective.

## Verification

§13.5 of the v1 plan requires **real iPhone** verification — simulator behavior for ASWebAuthSession is unreliable for the URL handoff. Test path:

1. Reconfigure sample app with `.deviceFlow`.
2. Build to a real iPhone.
3. Tap "Report an Issue".
4. Device Flow sheet appears, user code visible, monospaced, copy-on-tap.
5. Tap "Open GitHub" — Safari opens, GitHub login, code pre-filled, user approves.
6. Sheet flips to "Posting your report…"; issue appears on GitHub authored by the user's GitHub account.
7. Quit + relaunch + report again — no re-auth prompt (token reused).

---
_Last updated: 2026-06-04 — initial device flow guide_
