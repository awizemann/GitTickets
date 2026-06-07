---
title: Footgun — Vercel Function File-System Routing Has No Bare-Path Alias
type: note
permalink: gittickets/footguns/footgun-vercel-function-file-system-routing-has-no-bare-path-alias
tags:
- footgun
- vercel
- relay
- routing
---

Vercel routes API Functions by file-system layout: `api/report.ts` is reachable ONLY at `/api/report` unless the project adds explicit rewrites. The Swift SDK and the wire spec post to the bare path `<base>/report` (matching the Cloudflare Worker, which accepts both forms). Without rewrites, every real client submission to a Vercel relay 404s while curl smoke tests against `/api/report` still pass — the gap stays hidden until a real adopter integrates.

## Observations

- [fact] `vercel.json` rewrites at the project root are the canonical fix: map `/report` → `/api/report`, `/attachment` → `/api/attachment`, `/my-issues` → `/api/my-issues`. #vercel
- [contract] The wire spec in `relay/shared/payload-schema.md` documents bare paths. SDK `RelayClient.postSigned(path: "report", …)` calls `baseURL.appendingPathComponent("report")`. Cloudflare's `src/worker.ts` switch matches both `/report` and `/api/report`. Vercel without rewrites only matches `/api/report`. #wire-format
- [discovery] Caught by the live Memophant integration submitting and surfacing `GitTicketsError.relayRejected(statusCode: 404)`. Manual curl smoke tests had been hitting `/api/report` directly and reporting success, masking the bug for three days. #lessons
- [verification] After rewrite: bare `POST /report` returned 200 with `issueNumber: 4`. Issue #4 visible on github.com/awizemann/Memophant/issues/4. #verification
- [pattern] Shape-match: like the openssl `-hmac` footgun, this was a docs-and-CLI-recipe blind spot. The CLI recipe worked because we knew to add `/api/`; SDK callers didn't. When validating a deploy with curl, ALSO hit the bare path the SDK uses — not just the file-system path that "obviously" exists. #review-pattern
- [shape-match] Third bug of the "infrastructure built, public-API dispatch never reached it" family this session (after the submit() stub and RelaySubmitter.fetchMyIssues). Vercel ROUTING built, SDK PATH never reached it. Add this lens to future audits. #pattern

## Relations

- affects [[Wiki — Relay Deployment]]
- documented_in [[Audit Pass 2 — Post-Submit-Wiring Sweep]]
