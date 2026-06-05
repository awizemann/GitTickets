/**
 * POST /attachment — upload a single file part to Vercel Blob, return the
 * public URL.
 *
 * Signed and rate-limited like /report. Defense-in-depth MIME whitelist
 * matches the Swift SDK. Body size is enforced both against the request
 * envelope (hard 10 MB) and the configured attachment byte limit (default
 * 5 MB).
 */

import type { IncomingMessage, ServerResponse } from "node:http";

import {
  authenticate,
  enforceRateLimits,
  rawBody,
  sendError,
  sendJSON,
  BodyTooLargeError,
} from "./_lib/handler.js";
import { ALLOWED_MIME_TYPES } from "./_lib/payload.js";
import { extractFilePart, MultipartError } from "./_lib/multipart.js";
import { vercelBlobUploader, type Uploader } from "./_lib/blob.js";
import { log } from "./_lib/logger.js";

export const config = { api: { bodyParser: false } };

export default async function handler(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  return run(req, res, vercelBlobUploader);
}

/** Test-friendly entry that lets callers inject a fake uploader. */
export async function run(
  req: IncomingMessage,
  res: ServerResponse,
  uploader: Uploader,
): Promise<void> {
  if (req.method !== "POST") {
    sendError(res, 405, { error: "method_not_allowed" });
    return;
  }

  let body: Buffer;
  try {
    body = await rawBody(req);
  } catch (err) {
    if (err instanceof BodyTooLargeError) {
      sendError(res, 413, {
        error: "attachment_too_large",
        message: err.message,
      });
    } else {
      sendError(res, 500, { error: "internal_error" });
    }
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  const auth = authenticate(req, res, body, now);
  if (!auth) return;

  if (!(await enforceRateLimits(res, auth, /* deviceID */ null, now))) return;

  const contentType = headerValue(req, "content-type");
  if (!contentType || !contentType.toLowerCase().startsWith("multipart/form-data")) {
    sendError(res, 400, { error: "payload_invalid", message: "Content-Type must be multipart/form-data." });
    return;
  }

  let part;
  try {
    part = extractFilePart(body, contentType);
  } catch (err) {
    if (err instanceof MultipartError) {
      sendError(res, 400, { error: "payload_invalid", message: err.message });
    } else {
      sendError(res, 500, { error: "internal_error" });
    }
    return;
  }

  const normalizedMime = part.mimeType.toLowerCase();
  if (!ALLOWED_MIME_TYPES.has(normalizedMime)) {
    sendError(res, 415, {
      error: "unsupported_media_type",
      message: `MIME type '${part.mimeType}' is not allowed.`,
    });
    return;
  }

  if (part.data.byteLength > auth.env.attachmentByteLimit) {
    sendError(res, 413, {
      error: "attachment_too_large",
      message: `Attachment exceeds the ${auth.env.attachmentByteLimit}-byte limit.`,
      byteLimit: auth.env.attachmentByteLimit,
    });
    return;
  }

  try {
    const result = await uploader({
      bytes: part.data,
      mimeType: normalizedMime,
      token: auth.env.blobReadWriteToken,
    });
    log("info", "attachment_uploaded", {
      mimeType: normalizedMime,
      bytes: result.byteCount,
    });
    sendJSON(res, 200, {
      url: result.url,
      mimeType: normalizedMime,
      byteCount: result.byteCount,
    });
  } catch (err) {
    log("error", "blob_upload_failed", { error: err instanceof Error ? err.message : String(err) });
    sendError(res, 500, { error: "internal_error", message: "Blob upload failed." });
  }
}

function headerValue(req: IncomingMessage, key: string): string | undefined {
  const value = req.headers[key];
  if (Array.isArray(value)) return value[0];
  return value;
}
