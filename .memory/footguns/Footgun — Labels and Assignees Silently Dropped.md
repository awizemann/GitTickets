---
title: Footgun — Labels and Assignees Silently Dropped
type: note
permalink: gittickets/footguns/footgun-labels-and-assignees-silently-dropped
tags:
- footgun
- github-api
---

`POST /repos/{owner}/{repo}/issues` silently drops `labels`, `assignees`, and `milestone` fields unless the token has push access to the repo. No error — they just don't apply.

## Observations

- [fact] Documented (subtly) in [GitHub Issues REST API docs](https://docs.github.com/en/rest/issues/issues). #github-api
- [requirement] GitHub App `Issues: Read & write` permission DOES include push access — our relay path is fine. #relay
- [requirement] Device Flow with `public_repo` scope MAY or MAY NOT have push access depending on whether the user is a repo collaborator. For consumer apps using Device Flow, expect labels to fail silently for non-collaborator users — fall back to title-prefix conventions (e.g., "[Bug] ...") and detect the dropped label in `SubmittedIssue` to surface a warning. #device-flow
- [verification] PR 8 (Relay submitter) tests MUST verify labels round-trip on the App token path. #testing

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
