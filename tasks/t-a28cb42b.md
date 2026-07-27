---
id: t-a28cb42b
title: Detect dropped labels at fetch time, not just at submit
status: done
added: 2026-07-26
priority: high
---

## Description

From ShabuBox (their t-adf29b42). Verified against the code 2026-07-26.

My Reports narrows twice: the relay calls listLabeledIssues with env.label (GitHub ?labels=&state=all) at relay/cloudflare/src/handlers/myIssues.ts:58, then matches embedded UUID markers against the requested submission IDs. An issue whose label was dropped never survives the first narrowing, so it can never match the second. The relay returns 200 with zero matches — not an error — and GitTickets.refreshMyIssues() returns an empty array, so the view renders its ordinary empty state. My Reports goes permanently empty and nothing says why.

SubmittedIssue.missingLabels already detects this AT SUBMIT TIME on both auth paths. That is necessary but NOT sufficient: it cannot catch a label removed from existing issues in bulk, a changed env.label on the relay, or a swapped repo. In all three the user makes no new submission, so nothing fires, yet every past report vanishes.

The detectable signal is at fetch time and the SDK already holds both numbers: refreshMyIssues reads N cached submission IDs (GitTickets.swift:96) and the relay reports how many matched. N > 0 with 0 matched is a cheap, strong inconsistency that nothing currently checks.

## Plan

Goal: let a host distinguish "you have no reports" from "we could not find your reports". Do NOT hardcode user-facing warning UI — hand the host the signal and let it decide.

1. In refreshMyIssues (Sources/GitTickets/PublicAPI/GitTickets.swift:92-100), compare requested cached ID count against matched count.
2. On a shortfall, log .warning naming the counts, matching the existing missingLabels warning style in RelaySubmitter.swift:106-113.
3. Expose the shortfall so the empty state can be honest. Prefer a non-breaking shape — the return type is [SubmittedIssue] and changing it is source-breaking, so consider a companion accessor or a richer result type behind a new method rather than altering the existing signature.
4. Decide deliberately whether a partial shortfall (some matched, some missing) warns too, or only a total wipeout. A partial shortfall is normal if an issue was deleted, so weigh the false-positive cost.
5. Mirror on the Device Flow path, which already has a cached-projection fallback at DeviceFlowSubmitter.swift:242.
6. Tell ShabuBox they can act TODAY with no SDK change: wire Configuration.logger, read SubmittedIssue.missingLabels, treat nil as unknown rather than as all-applied.

## Artifacts



