---
title: Footgun — No Public GitHub Attachment API
type: note
permalink: gittickets/footguns/footgun-no-public-git-hub-attachment-api
tags:
- footgun
- github-api
- attachments
---

GitHub has no public REST or GraphQL endpoint for uploading images to issues or comments. The web UI uploads to a private S3-backed CDN.

## Observations

- [fact] Confirmed in GitHub community discussions [#46951](https://github.com/orgs/community/discussions/46951) and [#157555](https://github.com/orgs/community/discussions/157555). #github-api
- [consequence] The relay must own attachment storage (Vercel Blob / R2 / S3) and the SDK inlines the returned public URL into the issue body markdown. #relay
- [consequence] The Device Flow auth path CANNOT attach images — no public upload endpoint, no relay-side storage. UI must hide the attach button when `auth == .deviceFlow`, and surface `.attachmentNotSupportedInDeviceFlow` if attempted programmatically. #device-flow #limitation
- [warning] Vercel Blob URLs are time-limited on the free tier (90 days). For permanence recommend Cloudflare R2 with a public bucket, or v1.1 contents-API write into a sibling `*-attachments` repo. #relay #durability

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- documented_in [[Wiki — Threat Model]]
