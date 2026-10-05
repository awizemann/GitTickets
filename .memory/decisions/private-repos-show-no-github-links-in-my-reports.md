---
title: Private repos show no GitHub links in My Reports
type: note
permalink: gittickets/decisions/private-repos-show-no-github-links-in-my-reports
tags: [my-reports, privacy, v2.6.0]
source_paths: [Sources/GitTickets/PublicAPI/AuthMode.swift, Sources/GitTickets/UI/SwiftUI/IssueDetailView.swift, Sources/GitTickets/UI/SwiftUI/IssueDetailComponents.swift, Tests/GitTicketsTests/UI/SwiftUI/IssueDetailVisibilityTests.swift]
source_paths_inferred: false
source_sha: a63732310fd71fd146bd8aeb479fa35da574801f
created: 2026-10-05
updated: 2026-10-05
---

Decided by Alan 2026-10-05 for v2.6.0 after ScarfRack (private repo, relay mode) ruled replies are in-app only.

## Observations
- [decision] When repo.visibility == .private, Issue Detail shows no GitHub link or GitHub-pointing copy, regardless of auth mode (Alan overruled a device-flow exception) #my-reports #privacy
- [convention] The public/private rule lives in one internal helper RepoVisibility.isPublic(_:) (nil config = public) used by both the form and Issue Detail — don't add a second copy #my-reports
- [convention] IssueHeader/IssueStateCard expose linkURL: URL? and the body renders `if let linkURL`; tests assert on linkURL so they run on CI — a Link built directly from issue.issueURL would only be caught by the local snapshot suite #testing
