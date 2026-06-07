/**
 * POST /comments — for the SDK's "Issue detail" view.
 *
 * Returns every comment on the given issue (paged 5 × 100 = 500 max),
 * oldest first, with author login + body + created_at. Mirrors the
 * Swift-side `CommentsResponse` wire DTO.
 */

import type { IncomingMessage, ServerResponse } from "node:http";

import { CommentsRequestSchema } from "./_lib/payload.js";
import {
  authenticate,
  enforceRateLimits,
  rawBody,
  sendError,
  sendJSON,
  BodyTooLargeError,
} from "./_lib/handler.js";
import { getInstallationToken } from "./_lib/githubApp.js";
import { listComments, GitHubAPIError } from "./_lib/github.js";
import { log } from "./_lib/logger.js";

export const config = { api: { bodyParser: false } };

export default async function handler(
  req: IncomingMessage,
  res: ServerResponse,
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
      sendError(res, 413, { error: "body_too_large" });
    } else {
      sendError(res, 500, { error: "internal_error" });
    }
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  const auth = authenticate(req, res, body, now);
  if (!auth) return;

  let parsed;
  try {
    parsed = CommentsRequestSchema.parse(JSON.parse(body.toString("utf8")));
  } catch (err) {
    sendError(res, 400, {
      error: "payload_invalid",
      message: err instanceof Error ? err.message : "Could not parse request body.",
    });
    return;
  }

  if (!(await enforceRateLimits(res, auth, parsed.deviceID, now))) return;

  let token: string;
  try {
    token = await getInstallationToken({ env: auth.env, now });
  } catch (err) {
    log("error", "installation_token_failed", { error: stringifyError(err) });
    sendError(res, 500, { error: "internal_error" });
    return;
  }

  let comments;
  try {
    comments = await listComments({
      owner: auth.env.githubOwner,
      repo: auth.env.githubRepo,
      issueNumber: parsed.issueNumber,
      installationToken: token,
    });
  } catch (err) {
    if (err instanceof GitHubAPIError) {
      // GitHub returns 404 for issues that don't exist OR aren't visible to
      // the app's installation. Treat as empty rather than 502 — the SDK
      // will render "No replies yet" which is the right UX for either case.
      if (err.status === 404) {
        sendJSON(res, 200, { comments: [] });
        return;
      }
      sendError(res, 502, { error: "github_error", message: err.message });
      return;
    }
    log("error", "list_comments_failed", { error: stringifyError(err) });
    sendError(res, 500, { error: "internal_error" });
    return;
  }

  sendJSON(res, 200, { comments });
}

function stringifyError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}
