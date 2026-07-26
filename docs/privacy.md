# Privacy

The SDK ships [`PrivacyInfo.xcprivacy`](../Sources/GitTickets/PrivacyInfo.xcprivacy)
as a target resource. When you embed the SDK in your app, Apple's build
tools merge our manifest with your app's. This page covers what we
declare, what you (the adopter) need to add to your own manifest, and
the opt-outs available if you want to drop any of our claims.

## What the SDK declares

| Declaration                                       | Why                                                                                |
| ------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `NSPrivacyTracking = false`                       | We never combine data with third-party data to identify a user.                    |
| `NSPrivacyTrackingDomains = []`                   | The relay (if used) is your first-party server, not a third-party tracking domain. |
| `OtherDiagnosticData` (Linked: no, Tracking: no)  | The diagnostics blob — OS version, app version, device model, free disk, OSLog.    |
| `DeviceID` (Linked: no, Tracking: no)             | The per-install UUID `DeviceIdentity` generates and stores in the Keychain. NOT IDFA or `identifierForVendor`. |
| `PhotosorVideos` (Linked: no, Tracking: no)       | User-attached images. Only when your UI presents the attachment button.            |
| `DiskSpace` API category, reason `85F4.1`         | `DiagnosticsCollector.freeDiskDescription` displays free disk to the user.         |

All collected data types declare a single purpose: **App Functionality**
(the report itself is the feature).

## What your app must add

Apple's review wants the app-level manifest to declare what the app does
too. Add to your own `PrivacyInfo.xcprivacy`:

- The `PhotosorVideos` data type if your app's UI surfaces the attachment
  button. Even though the SDK declares it, your manifest needs to as well.
- Any other data types your app collects outside the SDK.
- Any required-reasons API categories your app uses outside the SDK.

If your app does NOT present attachments (or you've hidden the attachment
UI on a custom form), you can drop the `PhotosorVideos` claim from your
own manifest.

## Opting out

- **No attachments**: Build your own form on top of `GitTickets.submit(_:)`
  with empty `attachments`. Then drop `PhotosorVideos` from your manifest.
- **No diagnostics**: Pass `includeDiagnostics: false` to `Report`. Then
  you can argue down the `OtherDiagnosticData` claim if every report
  omits it.
- **No `DeviceID`**: Use `Report.deviceID = ""` for every submission. The
  SDK normally generates a per-install UUID for rate-limit / "My Issues"
  correlation; passing an empty string opts out, at the cost of losing
  per-device features.
- **No `DiskSpace` API**: Pass `DiagnosticsPolicy(includeFreeDisk: false)`.

If you opt out across the board, you can argue the SDK collects nothing
and drop all four declarations — but you've also lost most of what makes
the diagnostics blob useful for actual support.

## Attachment filenames

By default an attachment renders in the issue body as a markdown link whose
text is the user's actual filename. On a public repository that publishes
the document's name — "Tax Return 2024.png" tells a reader plenty, even
though the bytes themselves sit behind an unguessable upload URL.

If your app handles documents whose *names* are sensitive, render generic
labels instead:

```swift
GitTickets.configure(.init(
    repo: /* … */,
    auth: /* … */,
    privacy: PrivacyPolicy(attachmentNames: .generic)
))
```

Links then read "image 1", "attachment 2", numbered by a single index across
the whole list so the Nth link is the Nth attachment. The uploaded object
still keeps its real filename — only the link text changes — and the upload
URL never contains the filename in either mode.

This governs metadata the SDK injects. Text the user types into their own
description is theirs and is submitted as written; if they name a file in
their own prose, that is their choice and the SDK does not rewrite it.

## Submission review

Apple's privacy nutrition labels (the App Store Connect form) and the
privacy manifest are two different documents. The manifest informs the
nutrition labels but doesn't auto-fill them — fill out your nutrition
labels by hand to match what the SDK + your app together collect.
