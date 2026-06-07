# GitTickets Relay — Wire Format Specification

Language-agnostic specification for the relay's HTTP API. The Vercel and Cloudflare Worker templates in `/relay/vercel/` and `/relay/cloudflare/` implement this. Any other server implementation must match it exactly to be compatible with the Swift SDK.

**Versioning.** Every request body carries a `schemaVersion: <int>` field. Current: **1**. Bumped only on breaking changes; SDK and relay templates version together.

---

## Authentication

Every request is signed with HMAC-SHA256 using a shared secret known to both the SDK and the relay (`GITTICKETS_SHARED_SECRET` env var). The signing input is the byte concatenation of:

```
<unix-seconds-timestamp> + "." + <raw-request-body>
```

The period (`0x2E`) separates the timestamp from the body. The body is the raw bytes as transmitted on the wire — for JSON requests, the bytes of the serialized JSON; for multipart requests, the entire multipart envelope.

**Headers (every request):**

| Header | Format | Required |
|---|---|---|
| `X-GitTickets-Timestamp` | Unix seconds as decimal string, e.g. `1717545600` | yes |
| `X-GitTickets-Signature` | `sha256=<lowercase-64-char-hex>` | yes |
| `X-GitTickets-Idempotency-Key` | Opaque string ≤ 128 chars (for POST `/report` only) | yes for `/report` |

**Replay window:** the relay rejects requests where `\|now - timestamp\| > 300` seconds (5 minutes; configurable via `GITTICKETS_REPLAY_WINDOW_SECONDS`).

**Status code on signature failure:** `401`.

---

## `POST /report`

Submits a new issue.

### Request body (JSON)

```jsonc
{
  "schemaVersion": 1,
  "title": "Crash on launch",
  "body": "Tap the icon and the app crashes.\n\n…<!-- gittickets-id: UUID -->",
  "labels": ["bug", "gittickets"],
  "submissionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "deviceID": "device-1",
  "attachmentURLs": ["https://relay/blob/screenshot-abc.png"]
}
```

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | `int` | Must be `1`. Relay rejects with `400` otherwise. |
| `title` | `string` | Required, trimmed length 1–256. |
| `body` | `string` | Required, ≥ 50 chars after trim (spam-heuristic floor). Must contain the `<!-- gittickets-id: UUID -->` marker matching `submissionID`. |
| `labels` | `string[]` | Applied to the created issue. The relay should also append its configured label (default `"gittickets"`) if not already present. |
| `submissionID` | `string` | UUID. Used as the idempotency key value. |
| `deviceID` | `string` | Caller-supplied stable identifier. Used for per-device rate limiting. |
| `attachmentURLs` | `string[]` | URLs the relay returned from prior `/attachment` POSTs. Informational; the actual URLs are also inlined in `body`. |

### Response body (JSON, HTTP 200)

```jsonc
{
  "issueNumber": 42,
  "issueURL": "https://github.com/owner/repo/issues/42",
  "title": "Crash on launch",
  "createdAt": "2026-06-04T12:00:00Z",
  "appliedLabels": ["bug", "gittickets"]
}
```

`appliedLabels` is the list of labels GitHub actually applied (per the Issues API response). The SDK diffs this against the requested labels and surfaces any drops via `SubmittedIssue.missingLabels`. May be `null` if the relay cannot determine it.

### Idempotency

The relay MUST remember every `(idempotencyKey → response)` mapping for at least 24 hours. On a repeat request with the same key, it returns the cached response (HTTP 200) without re-creating an issue on GitHub. This protects against:

- UI double-tap.
- Cold-start retry after a network blip when the response was lost in flight.
- Replay within the timestamp window from a misbehaving client.

The idempotency key value comes from the `X-GitTickets-Idempotency-Key` header. The SDK uses the submission's UUID.

---

## `POST /attachment`

Uploads a single image or text-log file to the relay's object storage. Returns a public URL that the SDK inlines into the issue body before the `/report` call.

### Request

Content-Type: `multipart/form-data; boundary=...`. Exactly one part:

- name: `file`
- filename: caller-sanitized (CR/LF stripped, quotes stripped, 200-char cap)
- Content-Type: must be in the whitelist:
  - `image/png`, `image/jpeg`, `image/gif`, `image/webp`, `image/heic`
  - `application/octet-stream`, `text/plain`

The HMAC signs the **entire multipart envelope** (including headers and boundaries).

### Response body (JSON, HTTP 200)

```jsonc
{
  "url": "https://relay/blob/abc.png",
  "mimeType": "image/png",
  "byteCount": 12345
}
```

### Size limit

Default 5 MB per attachment (configurable via `GITTICKETS_ATTACHMENT_BYTE_LIMIT`). Exceed → HTTP 413 with envelope:

```jsonc
{
  "error": "attachment_too_large",
  "message": "Attachment exceeds the 5242880-byte limit.",
  "byteLimit": 5242880
}
```

Operators that raise the limit should set `byteLimit` so client error messages report the real cap.

---

## `POST /my-issues`

Lists past submissions for a device. Used by the SDK's "My Issues" view.

### Request body (JSON)

```jsonc
{
  "schemaVersion": 1,
  "submissionIDs": ["UUID-1", "UUID-2", "..."],
  "deviceID": "device-1"
}
```

### Response body (JSON, HTTP 200)

```jsonc
{
  "issues": [
    {
      "submissionID": "UUID-1",
      "issueNumber": 42,
      "issueURL": "https://github.com/owner/repo/issues/42",
      "title": "Crash on launch",
      "state": "open",
      "createdAt": "2026-06-04T12:00:00Z",
      "updatedAt": "2026-06-04T13:30:00Z",
      "replyCount": 3,
      "latestReplyAt": "2026-06-04T13:30:00Z"
    }
  ]
}
```

Only matched submissions are returned. The relay lists issues with the `gittickets` label and matches the `<!-- gittickets-id: -->` marker in each body against `submissionIDs`.

---

## `POST /comments`

Returns every comment on one GitHub issue, oldest first. Backs the
SDK's `IssueDetailView` reply thread.

### Request body (JSON)

```jsonc
{
  "schemaVersion": 1,
  "issueNumber": 42,
  "deviceID": "stable-per-install-id"
}
```

### Response body (JSON, HTTP 200)

```jsonc
{
  "comments": [
    {
      "id": 1234567890,
      "author": "alanw",
      "body": "Thanks — can you share your OS version?",
      "createdAt": "2026-06-04T13:30:00Z"
    }
  ]
}
```

Implementations page through GitHub's `GET /repos/:owner/:name/issues/:n/comments`
up to 5 pages × 100 (= 500 comments). A 404 from GitHub (issue gone or
not visible to the installation) is mapped to `200` with an empty
`comments` array — the SDK renders "no replies yet" rather than a hard
error, which is the right UX for either case.

---

## Error envelope (non-2xx)

When the relay returns a non-2xx status with a JSON body, the body MUST conform to:

```jsonc
{
  "error": "snake_case_code",
  "message": "Human-readable description for logs/UI.",
  "byteLimit": null  // Only for 413; null/omitted otherwise.
}
```

| Status | `error` value | Meaning |
|---|---|---|
| `400` | `payload_invalid` | Zod / schema validation failed. |
| `401` | `signature_mismatch` | HMAC didn't verify (or replay window exceeded). |
| `409` | `idempotency_replay_mismatch` | Same idempotency key, different body. Relay refuses to dedupe. |
| `413` | `attachment_too_large` | Body exceeds the configured byte limit. `byteLimit` field is REQUIRED here. |
| `415` | `unsupported_media_type` | Attachment MIME not in whitelist. |
| `429` | `rate_limited` | Per-IP or per-device hourly limit hit. `Retry-After` header included. |
| `5xx` | `internal_error` / `github_error` | Server bug or GitHub API failure. |

---

## Reference implementations

- **Vercel**: `/relay/vercel/api/`
- **Cloudflare Worker**: `/relay/cloudflare/src/` (PR 10)

Each ships a `tests/` directory that exercises the wire contract against the Swift SDK's HMAC vector (`Tests/GitTicketsTests/Auth/RelaySignatureTests.swift` → `test_signMatchesIndependentHmacComputation`). Run those tests before deploying any relay change.
