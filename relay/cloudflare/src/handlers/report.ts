/**
 * POST /report handler — Workers edition.
 *
 * Verifies HMAC, enforces rate limits, validates payload, dedupes on
 * idempotency key, mints installation token, creates issue, records
 * idempotency response.
 */

import { authenticate, enforceRateLimits } from "../lib/auth.js";
import { jsonError, jsonResponse } from "../lib/responses.js";
import { ReportRequestSchema, bodyContainsMarker } from "../lib/payload.js";
import { getInstallationToken } from "../lib/githubApp.js";
import { createIssue, GitHubAPIError } from "../lib/github.js";
import { lookup as idemLookup, record as idemRecord } from "../lib/idempotency.js";
import { log } from "../lib/logger.js";
import type { ParsedEnv } from "../lib/env.js";

const MAX_BODY_BYTES = 10 * 1024 * 1024;

export async function handleReport(
  request: Request,
  env: ParsedEnv,
): Promise<Response> {
  let raw: Uint8Array;
  try {
    raw = await readBody(request, MAX_BODY_BYTES);
  } catch {
    return jsonError(413, "body_too_large", `Request body exceeds ${MAX_BODY_BYTES} bytes.`);
  }

  const now = Math.floor(Date.now() / 1000);
  const auth = await authenticate(request, env, raw, now);
  if (!auth.ok) return auth.response;

  let parsed;
  try {
    parsed = ReportRequestSchema.parse(JSON.parse(new TextDecoder().decode(raw)));
  } catch (err) {
    return jsonError(400, "payload_invalid", err instanceof Error ? err.message : "Could not parse body.");
  }

  if (!bodyContainsMarker(parsed.body, parsed.submissionID)) {
    return jsonError(
      400,
      "payload_invalid",
      "Body is missing the <!-- gittickets-id: --> marker matching submissionID.",
    );
  }

  if (!auth.idempotencyKey) {
    return jsonError(400, "payload_invalid", "Missing X-GitTickets-Idempotency-Key header.");
  }

  const rateLimited = await enforceRateLimits(env, auth, parsed.deviceID, now);
  if (rateLimited) return rateLimited;

  const bodyHash = await sha256Hex(raw);
  const cached = await idemLookup({ env, key: auth.idempotencyKey, bodyHash });
  if (cached.status === "hit") {
    return jsonResponse(200, cached.response);
  }
  if (cached.status === "conflict") {
    return jsonError(
      409,
      "idempotency_replay_mismatch",
      "Same idempotency key, different body. Refusing to dedupe.",
    );
  }

  const labels = parsed.labels.includes(env.label) ? parsed.labels : [...parsed.labels, env.label];

  let token: string;
  try {
    token = await getInstallationToken({ env, now });
  } catch (err) {
    log("error", "installation_token_failed", { error: errString(err) });
    return jsonError(500, "internal_error", "Could not mint GitHub App installation token.");
  }

  try {
    const issue = await createIssue({
      owner: env.githubOwner,
      repo: env.githubRepo,
      installationToken: token,
      title: parsed.title,
      body: parsed.body,
      labels,
    });
    const response = {
      issueNumber: issue.number,
      issueURL: issue.htmlUrl,
      title: issue.title,
      createdAt: issue.createdAt,
      appliedLabels: issue.appliedLabels,
    };
    await idemRecord({ env, key: auth.idempotencyKey, bodyHash, response, now });
    log("info", "report_created", {
      issueNumber: issue.number,
      submissionID: parsed.submissionID,
      requestedLabels: labels.length,
      appliedLabels: issue.appliedLabels.length,
    });
    return jsonResponse(200, response);
  } catch (err) {
    if (err instanceof GitHubAPIError) {
      log("warning", "github_create_failed", { status: err.status });
      return jsonError(502, "github_error", `GitHub rejected the issue: ${err.message}`);
    }
    log("error", "create_issue_failed", { error: errString(err) });
    return jsonError(500, "internal_error");
  }
}

async function readBody(request: Request, maxBytes: number): Promise<Uint8Array> {
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maxBytes) throw new Error("body too large");
  return new Uint8Array(buffer);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function errString(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
