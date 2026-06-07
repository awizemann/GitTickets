# Contributing to GitTickets

Thanks for your interest. GitTickets is an open-source Swift package that lets any app give its users a one-click "Report an Issue" surface backed by GitHub.

## Local dev

```bash
git clone https://github.com/alanw/GitTickets.git
cd GitTickets
swift build
swift test
```

Or, in Xcode:

```bash
open Package.swift
# Cmd-U to run the test suite.
```

The package builds on macOS 13+ and iOS 16+ (Swift 5.9 toolchain).

## Project structure

- `Sources/GitTickets/` — the package itself; see [wiki/Architecture.md](wiki/Architecture.md) for the module layout.
- `Tests/GitTicketsTests/` — unit and snapshot tests.
- `Examples/` — sample apps that exercise the full integration path.
- `relay/` — Vercel and Cloudflare Worker templates for the developer-hosted relay.
- `wiki/` — long-form documentation (architecture, threat model, runbooks).
- `docs/` — user-facing reference docs (built into the package for inclusion in adopter privacy policies).
- `TASKS.md` — current kanban of the v1 build plan.

## Workflow

1. Pick the lowest unstarted item from [`TASKS.md`](TASKS.md) `## Todo`. The 20-PR v1.0 build sequence has shipped (see [wiki/Build-Sequence.md](wiki/Build-Sequence.md) for the historical record); remaining items are post-v1 polish + v1.1 candidates.
2. Move it to `## Doing`.
3. Branch off `main` (`git checkout -b prN-short-description`).
4. Implement.
5. Run the baselines locally:
   - `swift test` for the SDK (~210 cases).
   - `cd relay/vercel && npm test` (~37 vitest cases).
   - `cd relay/cloudflare && npm test` (~32 vitest cases).
   - `xcodebuild -scheme GitTickets -destination 'generic/platform=iOS Simulator' build` for the iOS compile check.
6. Open a PR. Reference the task line in the description.
7. After merge, move the task to `## Done`.

## Code conventions

- Public API surface lives under `Sources/GitTickets/PublicAPI/`. Everything else is `internal` or `fileprivate`.
- No production dependencies. System frameworks only. Test-only dep is `pointfreeco/swift-snapshot-testing`.
- `Sendable` everywhere it's free; document where it isn't.
- Defer Swift 6 strict concurrency until a dedicated PR after v1.0.

## Memory system

This repo uses [Memophant](https://github.com/wizemann/memophant) for a layered memory system (`.memory/`, `wiki/`, `design/`, `code/`, `TASKS.md`). Durable decisions and learnings go in **Basic Memory notes or wiki pages**, not in agent-specific config files. The memory system is committed separately from application code via the Memophant app's commit modal (which runs a secret-scan); when you edit `wiki/` or `.memory/`, leave those files dirty rather than `git add`-ing them.

## Security

Found a vulnerability? See [SECURITY.md](SECURITY.md) for the disclosure process. Don't open a public issue.

## License

By contributing, you agree your contributions are licensed under MIT (see [LICENSE](LICENSE)).
