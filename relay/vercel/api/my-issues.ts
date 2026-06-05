/**
 * POST /my-issues — for the SDK's "My Reports" view.
 *
 * Lists issues labelled `gittickets` in the configured repo, matches the
 * `<!-- gittickets-id: -->` markers against the client-supplied submission
 * ID list, and returns one entry per match (with comment metadata).
 *
 * The relay does the listing rather than the SDK so the GitHub installation
 * token never leaves the server.
 */

import type { IncomingMessage, ServerResponse } from "node:http";

import { MyIssuesRequestSchema } from "./_lib/payload.js";
import {
  authenticate,
  enforceRateLimits,
  rawBody,
  sendError,
  sendJSON,
  BodyTooLargeError,
} from "./_lib/handler.js";
import { getInstallationToken } from "./_lib/githubApp.js";
import {
  listLabeledIssues,
  latestComment,
  GitHubAPIError,
} from "./_lib/github.js";
import { log } from "./_lib/logger.js";

export const config = { api: { bodyParser: false } };

const MARKER_REGEX = /<!--\s*gittickets-id:\s*([0-9a-fA-F-]{36})\s*-->/;

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
    parsed = MyIssuesRequestSchema.parse(JSON.parse(body.toString("utf8")));
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

  let issues;
  try {
    issues = await listLabeledIssues({
      owner: auth.env.githubOwner,
      repo: auth.env.githubRepo,
      installationToken: token,
      label: auth.env.label,
    });
  } catch (err) {
    if (err instanceof GitHubAPIError) {
      sendError(res, 502, { error: "github_error", message: err.message });
      return;
    }
    log("error", "list_issues_failed", { error: stringifyError(err) });
    sendError(res, 500, { error: "internal_error" });
    return;
  }

  const requested = new Set(parsed.submissionIDs);
  const matches = [] as Array<{
    submissionID: string;
    issueNumber: number;
    issueURL: string;
    title: string;
    state: string;
    createdAt: string;
    updatedAt: string;
    replyCount: number;
    latestReplyAt: string | null;
  }>;

  for (const issue of issues) {
    const m = MARKER_REGEX.exec(issue.body);
    if (!m) continue;
    const submissionID = m[1]!.toUpperCase();
    if (!requested.has(submissionID)) continue;

    let latestReplyAt: string | null = null;
    if (issue.comments > 0) {
      const latest = await latestComment({
        owner: auth.env.githubOwner,
        repo: auth.env.githubRepo,
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

  sendJSON(res, 200, { issues: matches });
}

function stringifyError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}
