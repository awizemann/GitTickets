---
title: Footgun — Issue Forms Are Web-UI-Only
type: note
permalink: gittickets/footguns/footgun-issue-forms-are-web-ui-only
tags:
- footgun
- github-api
- roadmap
---

`.github/ISSUE_TEMPLATE/*.yml` Issue Forms are rendered ONLY by the GitHub web UI. There is no REST endpoint like "create issue from template X with field values." Forms compile to plain markdown that goes into `body`.

## Observations

- [fact] The [issue forms syntax docs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema) describe the YAML but there's no programmatic submission API. #github-api
- [decision] v1 ships a FIXED form schema (bug / featureRequest / question kinds). Does NOT parse the host repo's templates. Keeps v1 scope contained. #scope
- [roadmap] v1.1 magic move: SDK fetches `.github/ISSUE_TEMPLATE/*.yml` from the host repo via `raw.githubusercontent.com`, parses the YAML, renders matching SwiftUI form, and serializes back to the SAME markdown shape the web UI produces. This is the killer feature that makes GitTickets feel native. Documented in [[Roadmap — v1.1 Native Issue Forms]]. #roadmap

## Relations

- defers_to [[Roadmap — v1.1 Native Issue Forms]]
