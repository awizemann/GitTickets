/**
 * POST /my-issues handler — Workers edition.
 *
 * Lists labelled issues, matches embedded UUID markers, returns matched
 * entries with comment counts.
 */

import { authenticate, enforceRateLimits } from "../lib/auth.js";
import { jsonError, jsonResponse } from "../lib/responses.js";
import { MyIssuesRequestSchema } from "../lib/payload.js";
import { getInstallationToken } from "../lib/githubApp.js";
import {
  listLabeledIssues,
  latestComment,
  GitHubAPIError,
} from "../lib/github.js";
import { log } from "../lib/logger.js";
import type { ParsedEnv } from "../lib/env.js";

const MAX_BODY_BYTES = 64 * 1024;
const MARKER_REGEX = /<!--\s*gittickets-id:\s*([0-9a-fA-F-]{36})\s*-->/;

export async function handleMyIssues(
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
    parsed = MyIssuesRequestSchema.parse(JSON.parse(new TextDecoder().decode(raw)));
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

  let issues;
  try {
    issues = await listLabeledIssues({
      owner: env.githubOwner,
      repo: env.githubRepo,
      installationToken: token,
      label: env.label,
    });
  } catch (err) {
    if (err instanceof GitHubAPIError) {
      return jsonError(502, "github_error", err.message);
    }
    log("error", "list_issues_failed", { error: errString(err) });
    return jsonError(500, "internal_error");
  }

  const requested = new Set(parsed.submissionIDs);
  const matches: Array<{
    submissionID: string;
    issueNumber: number;
    issueURL: string;
    title: string;
    state: string;
    createdAt: string;
    updatedAt: string;
    replyCount: number;
    latestReplyAt: string | null;
  }> = [];

  for (const issue of issues) {
    const m = MARKER_REGEX.exec(issue.body);
    if (!m) continue;
    const submissionID = m[1]!.toUpperCase();
    if (!requested.has(submissionID)) continue;

    let latestReplyAt: string | null = null;
    if (issue.comments > 0) {
      const latest = await latestComment({
        owner: env.githubOwner,
        repo: env.githubRepo,
        issueNumber: issue.number,
        installationToken: token,
      });
      latestReplyAt = latest?.createdAt ?? null;
    }

    matches.push({
      submissionID,
      issueNumber: issue.number,
      issueURL: issue.htmlUrl,
      title: issue.title,
      state: issue.state,
      createdAt: issue.createdAt,
      updatedAt: issue.updatedAt,
      replyCount: issue.comments,
      latestReplyAt,
    });
  }

  return jsonResponse(200, { issues: matches });
}

async function readBody(request: Request, maxBytes: number): Promise<Uint8Array> {
  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maxBytes) throw new Error("body too large");
  return new Uint8Array(buffer);
}

function errString(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
