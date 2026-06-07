---
title: Getting-Started
type: note
permalink: gittickets-wiki/getting-started
---

# Getting Started

The polished adopter walkthrough lives in [`docs/getting-started.md`](../docs/getting-started.md) — that's the file that ships with the SDK and is authoritative for integrators. This wiki page is a contributor-facing pointer.

## TL;DR for new contributors

If you've just cloned the repo and want to understand the integration surface:

1. Read [`docs/getting-started.md`](../docs/getting-started.md) — the adopter onboarding flow.
2. Read [`docs/architecture.md`](../docs/architecture.md) — the data flow + module map.
3. Read [`Examples/README.md`](../Examples/README.md) — three reference integrations (SwiftUI macOS, SwiftUI iOS, AppKit) you can paste into a project to see the SDK working end-to-end.
4. Skim [Patterns & Gotchas](Patterns-and-Gotchas) — the durable rules + footgun index every PR touching auth / HMAC / Keychain / multipart should respect.

For the design tier:

- [`design/design_handoff_gittickets_views_generic/reference/GitTickets Redesign (Generic).html`](../design/design_handoff_gittickets_views_generic/reference/) — open in a browser to see the macOS + iOS frames the SwiftUI is designed to reproduce. Toggle Light/Dark top-right.

For the relay tier:

- [`relay/vercel/README.md`](../relay/vercel/README.md) and [`relay/cloudflare/README.md`](../relay/cloudflare/README.md) — full deploy walkthroughs.
- [`relay/shared/payload-schema.md`](../relay/shared/payload-schema.md) — the wire contract both templates implement.

## Quick smoke-test

After cloning:

```bash
swift test                        # macOS unit tests (~200 cases)
xcodebuild -scheme GitTickets \
  -destination 'generic/platform=iOS Simulator' build   # iOS compile check
cd relay/vercel && npm test       # 37 vitest cases
cd ../cloudflare && npm test      # 32 vitest cases
```

All four should be green on `main`.

---
_Last updated: 2026-06-06 — converted from stub to pointer + smoke-test recipe_
