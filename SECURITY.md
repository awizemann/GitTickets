# Security Policy

GitTickets is a Swift package and a serverless relay. Vulnerabilities in either are in scope.

## Reporting a vulnerability

**Please do not open a public GitHub issue.** Email `security@wizemann.com` with:

- A description of the vulnerability and impact.
- Steps to reproduce, ideally with a minimal sample.
- The affected component (`Sources/GitTickets/...` or `relay/vercel/...` or `relay/cloudflare/...`) and version (tag or commit).

We respond within 5 business days with an acknowledgement and a triage timeline.

## In scope

- The Swift SDK in `Sources/GitTickets/`.
- The Vercel relay template in `relay/vercel/`.
- The Cloudflare Worker relay template in `relay/cloudflare/`.
- Documented integration patterns in `wiki/` and `docs/`.

## Out of scope

- Vulnerabilities in adopter apps embedding GitTickets — report to the app's maintainer.
- Issues with the GitHub platform itself — report via [github.com/security](https://github.com/security).
- Self-inflicted misconfiguration (e.g., shipping a relay with no rate limit) — see [wiki/Relay-Deployment.md](wiki/Relay-Deployment.md) for guidance.

## Threat model

The full threat model is in [wiki/Threat-Model.md](wiki/Threat-Model.md). Key points:

- The HMAC shared secret IS extractable from the app binary. Per-IP rate limiting on the relay is the real wall against abuse.
- The relay is the trust boundary. The GitHub App private key lives only there and must never appear in logs.
- End-user diagnostics run through a redaction pipeline (email / IP / bearer-token) before display AND before send. The user sees what gets sent.

## Disclosure timeline

We aim for coordinated disclosure within 90 days of report, sooner if the fix is straightforward. Reporters are credited in the release notes unless they request otherwise.
