/**
 * POST /report — create a GitHub issue from a signed SDK submission.
 *
 * 1. Read raw body (we need the exact bytes for HMAC).
 * 2. Verify HMAC + replay window.
 * 3. Enforce per-IP + per-device rate limits.
 * 4. Validate payload with zod.
 * 5. Check Idempotency-Key — on hit return cached response, on conflict 409.
 * 6. Mint installation token + create issue.
 * 7. Record idempotency response.
 * 8. Return {issueNumber, issueURL, title, createdAt, appliedLabels}.
 */

import { createHash } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";

import {
  ReportRequestSchema,
  bodyContainsMarker,
} from "./_lib/payload.js";
import {
  authenticate,
  enforceRateLimits,
  rawBody,
  sendError,
  sendJSON,
  BodyTooLargeError,
} from "./_lib/handler.js";
import { getInstallationToken } from "./_lib/githubApp.js";
import { createIssue, GitHubAPIError } from "./_lib/github.js";
import { lookup as idempotencyLookup, record as idempotencyRecord } from "./_lib/idempotency.js";
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
    parsed = ReportRequestSchema.parse(JSON.parse(body.toString("utf8")));
  } catch (err) {
    sendError(res, 400, {
      error: "payload_invalid",
      message: err instanceof Error ? err.message : "Could not parse request body.",
    });
    return;
  }

  if (!bodyContainsMarker(parsed.body, parsed.submissionID)) {
    sendError(res, 400, {
      error: "payload_invalid",
      message: "Body is missing the <!-- gittickets-id: --> marker matching submissionID.",
    });
    return;
  }

  if (!auth.idempotencyKey) {
    sendError(res, 400, {
      error: "payload_invalid",
      message: "Missing X-GitTickets-Idempotency-Key header.",
    });
    return;
  }

  if (!(await enforceRateLimits(res, auth, parsed.deviceID, now))) return;

  const bodyHash = createHash("sha256").update(body).digest("hex");
  const cached = await idempotencyLookup({
    env: auth.env,
    key: auth.idempotencyKey,
    bodyHash,
  });
  if (cached.status === "hit") {
    sendJSON(res, 200, cached.response);
    return;
  }
  if (cached.status === "conflict") {
    sendError(res, 409, {
      error: "idempotency_replay_mismatch",
      message:
        "An earlier request used this idempotency key with a different body. Refusing to dedupe.",
    });
    return;
  }

  // Ensure the configured label is present (the SDK adds it but trust no-one).
  const labels = parsed.labels.includes(auth.env.label)
    ? parsed.labels
    : [...parsed.labels, auth.env.label];

  let token: string;
  try {
    token = await getInstallationToken({ env: auth.env, now });
  } catch (err) {
    log("error", "installation_token_failed", { error: stringifyError(err) });
    sendError(res, 500, {
      error: "internal_error",
      message: "Could not mint GitHub App installation token.",
    });
    return;
  }

  let issue;
  try {
    issue = await createIssue({
      owner: auth.env.githubOwner,
      repo: auth.env.githubRepo,
      installationToken: token,
      title: parsed.title,
      body: parsed.body,
      labels,
    });
  } catch (err) {
    if (err instanceof GitHubAPIError) {
      log("warning", "github_create_failed", { status: err.status });
      sendError(res, 502, {
        error: "github_error",
        message: `GitHub rejected the issue: ${err.message}`,
      });
      return;
    }
    log("error", "create_issue_failed", { error: stringifyError(err) });
    sendError(res, 500, { error: "internal_error" });
    return;
  }

  const response = {
    issueNumber: issue.number,
    issueURL: issue.htmlUrl,
    title: issue.title,
    createdAt: issue.createdAt,
    appliedLabels: issue.appliedLabels,
  };

  await idempotencyRecord({
    env: auth.env,
    key: auth.idempotencyKey,
    bodyHash,
    response,
    now,
  });

  log("info", "report_created", {
    issueNumber: issue.number,
    submissionID: parsed.submissionID,
    requestedLabels: labels.length,
    appliedLabels: issue.appliedLabels.length,
  });

  sendJSON(res, 200, response);
}

function stringifyError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}
