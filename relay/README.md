# GitTickets Relay Templates

This folder holds reference implementations of the [GitTickets relay wire spec](shared/payload-schema.md). Pick one, deploy it, and point the Swift SDK at its URL.

| Template | Runtime | Storage | Rate-limit backend |
| --- | --- | --- | --- |
| [`vercel/`](vercel/) | Node 20 Vercel Functions | Vercel Blob | Upstash Redis or in-memory |
| `cloudflare/` _(ships in PR 10)_ | Cloudflare Workers (V8 isolates) | R2 | KV or Durable Objects |

Both implement the same endpoints, the same HMAC signing scheme, the same idempotency semantics, and the same error envelope. Switching between them is a configuration change, not a re-integration.

For the language-agnostic wire spec see [`shared/payload-schema.md`](shared/payload-schema.md).

For the trust boundary discussion (what the HMAC does and does not protect against, why an extractable shared secret is OK) see [`../wiki/Threat-Model.md`](../wiki/Threat-Model.md).
