/**
 * POST /comments handler — Workers edition.
 *
 * Returns every comment on the given issue (paged 5 × 100 = 500 max),
 * oldest first. Parity with the Vercel template.
 */

import { authenticate, enforceRateLimits } from "../lib/auth.js";
import { jsonError, jsonResponse } from "../lib/responses.js";
import { CommentsRequestSchema } from "../lib/payload.js";
import { getInstallationToken } from "../lib/githubApp.js";
import { listComments, GitHubAPIError } from "../lib/github.js";
import { log } from "../lib/logger.js";
import type { ParsedEnv } from "../lib/env.js";

const MAX_BODY_BYTES = 64 * 1024;

export async function handleComments(
  request: Request,
  env: ParsedEnv,
): Promise<Response> {
  let raw: Uint8Array;
  try {
    raw = await readBody(request, MAX_BODY_BYTES);
  } catch {
    return jsonError(413, "body_too_large");
  }

  const now = Math.floor(Date.now() / 1000);
  const auth = await authenticate(request, env, raw, now);
  if (!auth.ok) return auth.response;

  let parsed;
  try {
    parsed = CommentsRequestSchema.parse(JSON.parse(new TextDecoder().decode(raw)));
  } catch (err) {
    return jsonError(400, "payload_invalid", err instanceof Error ? err.message : "Could not parse body.");
  }

  const rateLimited = await enforceRateLimits(env, auth, parsed.deviceID, now);
  if (rateLimited) return rateLimited;

  let token: string;
  try {
    token = await getInstallationToken({ env, now });
  } catch (err) {
    log("error", "installation_token_failed", { error: errString(err) });
    return jsonError(500, "internal_error");
  }

  let comments;
  try {
    comments = await listComments({
      owner: env.githubOwner,
      repo: env.githubRepo,
      issueNumber: parsed.issueNumber,
      installationToken: token,
    });
  } catch (err) {
    if (err instanceof GitHubAPIError) {
      // 404 = issue doesn't exist or isn't visible to this installation —
      // treat as empty so the SDK renders the "no replies yet" state
      // rather than a hard error.
      if (err.status === 404) {
        return jsonResponse(200, { comments: [] });
      }
      return jsonError(502, "github_error", err.message);
    }
    log("error", "list_comments_failed", { error: errString(err) });
    return jsonError(500, "internal_error");
  }

  return jsonResponse(200, { comments });
}

async function readBody(request: Request, maxBytes: number): Promise<Uint8Array> {
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maxBytes) throw new Error("body too large");
  return new Uint8Array(buffer);
}

function errString(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
