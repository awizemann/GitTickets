---
title: Footgun — Multipart Header Injection via Filename and MIME
type: note
permalink: gittickets/footguns/footgun-multipart-header-injection-via-filename-and-mime
tags:
- footgun
- security
- relay
- multipart
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

Interpolating caller-supplied `filename` or `mimeType` into multipart `Content-Disposition` / `Content-Type` headers without sanitization is the same CVE class that hit Rack and Spring multipart parsers. Two vectors:

- A filename containing `\r\n` terminates the header section and lets the attacker inject additional headers or parts.
- A filename containing `"` closes the quoted-string early.
- A filename containing the boundary token (UUID-shaped — leakable via response timing) terminates the body early and drops the file.
- A MIME type containing `\r\n` (`"image/png\r\nX-Forwarded-Auth: admin"`) injects a per-part header; if the relay echoes or trusts per-part headers, the attacker controls them.

Discovered in code review of PR 8. `ReportAttachment.filename` and `.mimeType` are caller-controlled public-API fields.

## Observations

- [rule] `RelayClient.sanitizeFilename` strips control chars (CR/LF/0x00-0x1F/0x7F), quotes, and backslashes; replaces `/` and `:` with `_`; trims whitespace; caps length at 200 chars; falls back to `"attachment"` if empty. #security
- [rule] `RelayClient.validateMimeType` rejects anything outside a small allowlist (`image/png`, `image/jpeg`, `image/gif`, `image/webp`, `image/heic`, `application/octet-stream`, `text/plain`). Also explicitly refuses CR/LF as defense-in-depth in case the allowlist is widened by a future PR. #security
- [rule] Test the multipart encoder with adversarial fixtures, not just clean inputs. See `RelayClientTests.test_multipartSanitizesFilenameQuotes`, `test_multipartStripsCRLFFromFilename`, `test_multipartRejectsMimeTypeWithCRLF`. #testing
- [defense-in-depth] The relay should ALSO validate filename/MIME server-side. Don't trust client sanitization alone; the API contract is "the relay is the trust boundary." #security
- [rule] The multipart boundary is a UUID. If the boundary is ever made guessable (sequential, derived from request id, etc.), filename injection becomes exploitable even after sanitization. Keep the boundary unpredictable. #security
- [related] Any future endpoint that accepts caller-supplied bytes into a multi-line wire format (Slack-style file uploads, GitHub gist creation, email bodies) inherits this footgun shape. Apply the same allowlist + sanitize pattern.

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- prevents_recurrence_of "filename injection corrupting multipart envelope"
- prevents_recurrence_of "MIME type CRLF header injection"
