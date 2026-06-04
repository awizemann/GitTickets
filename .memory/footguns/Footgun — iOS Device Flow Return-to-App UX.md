---
title: Footgun — iOS Device Flow Return-to-App UX
type: note
permalink: gittickets/footguns/footgun-i-os-device-flow-return-to-app-ux
tags:
- footgun
- device-flow
- ios
---

After OAuth Device Flow approval on github.com, the user is stranded on a "you're all set" GitHub page with no automatic return to the app. The naive implementation leaves users confused.

## Observations

- [pattern] Use `ASWebAuthenticationSession` with `verificationURIComplete` (which has the user code pre-filled) and `prefersEphemeralWebBrowserSession = true`. #ios #pattern
- [pattern] Our SwiftUI device-flow sheet stays open in-app the whole time. While the user is in the browser, the sheet polls the token endpoint. When the token arrives, the sheet auto-dismisses and the report posts. User does NOT need to manually return to the app; the system browser modal dismisses itself when authorization completes. #ux
- [decision] No Universal Links needed for v1 — the polling loop is the return mechanism. #decision
- [verification] §13.5 of the plan requires real-iPhone verification — simulator behavior for ASWebAuthSession is unreliable. #testing

## Relations

- documented_in [[Wiki — Device Flow]]
