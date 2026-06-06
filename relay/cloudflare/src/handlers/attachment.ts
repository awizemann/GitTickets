/**
 * POST /attachment handler — Workers edition.
 *
 * HMAC over the full multipart envelope, MIME whitelist, per-file size cap,
 * R2 upload. Returns the public URL the SDK inlines into the issue body.
 */

import { authenticate, enforceRateLimits } from "../lib/auth.js";
import { jsonError, jsonResponse } from "../lib/responses.js";
import { ALLOWED_MIME_TYPES } from "../lib/payload.js";
import { extractFilePart, MultipartError } from "../lib/multipart.js";
import { r2BlobUploader, type Uploader, R2Error } from "../lib/r2.js";
import { log } from "../lib/logger.js";
import type { ParsedEnv } from "../lib/env.js";

const MAX_BODY_BYTES = 10 * 1024 * 1024;

export async function handleAttachment(
  request: Request,
  env: ParsedEnv,
  uploader: Uploader = r2BlobUploader,
): Promise<Response> {
  let raw: Uint8Array;
  try {
    raw = await readBody(request, MAX_BODY_BYTES);
  } catch {
    // Envelope-level rejection — the request body exceeds the hard ceiling
    // before we even parse multipart. Use `body_too_large` (matching Vercel)
    // and DO NOT report `byteLimit`: that field is contractually the
    // configured per-attachment cap, and surfacing the 10 MB envelope here
    // would mislead clients into believing the per-file cap is also 10 MB.
    return jsonError(413, "body_too_large", `Request body exceeds ${MAX_BODY_BYTES} bytes.`);
  }

  const now = Math.floor(Date.now() / 1000);
  const auth = await authenticate(request, env, raw, now);
  if (!auth.ok) return auth.response;

  const rateLimited = await enforceRateLimits(env, auth, null, now);
  if (rateLimited) return rateLimited;

  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
    return jsonError(400, "payload_invalid", "Content-Type must be multipart/form-data.");
  }

  let part;
  try {
    part = extractFilePart(raw, contentType);
  } catch (err) {
    if (err instanceof MultipartError) {
      return jsonError(400, "payload_invalid", err.message);
    }
    return jsonError(500, "internal_error");
  }

  const normalizedMime = part.mimeType.toLowerCase();
  if (!ALLOWED_MIME_TYPES.has(normalizedMime)) {
    return jsonError(415, "unsupported_media_type", `MIME type '${part.mimeType}' is not allowed.`);
  }

  if (part.data.byteLength > env.attachmentByteLimit) {
    return jsonError(
      413,
      "attachment_too_large",
      `Attachment exceeds the ${env.attachmentByteLimit}-byte limit.`,
      env.attachmentByteLimit,
    );
  }

  try {
    const result = await uploader({ bytes: part.data, mimeType: normalizedMime, env });
    log("info", "attachment_uploaded", { mimeType: normalizedMime, bytes: result.byteCount });
    return jsonResponse(200, {
      url: result.url,
      mimeType: normalizedMime,
      byteCount: result.byteCount,
    });
  } catch (err) {
    if (err instanceof R2Error) {
      log("error", "r2_not_bound", { message: err.message });
      return jsonError(500, "internal_error", "R2 binding not configured.");
    }
    log("error", "r2_upload_failed", { error: err instanceof Error ? err.message : String(err) });
    return jsonError(500, "internal_error", "Attachment upload failed.");
  }
}

async function readBody(request: Request, maxBytes: number): Promise<Uint8Array> {
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maxBytes) throw new Error("body too large");
  return new Uint8Array(buffer);
}
