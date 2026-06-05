/**
 * GitTickets relay — Cloudflare Worker entry.
 *
 * Routes POSTs on /report, /attachment, /my-issues to their handlers.
 * The /api/* prefix is also accepted so a single curl recipe works against
 * both Vercel and Cloudflare deployments.
 */

import { parseEnv, EnvError, type WorkerEnv } from "./lib/env.js";
import { handleReport } from "./handlers/report.js";
import { handleAttachment } from "./handlers/attachment.js";
import { handleMyIssues } from "./handlers/myIssues.js";
import { jsonError } from "./lib/responses.js";
import { log } from "./lib/logger.js";

export default {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    if (request.method !== "POST") {
      return jsonError(405, "method_not_allowed");
    }

    let parsed;
    try {
      parsed = parseEnv(env);
    } catch (err) {
      if (err instanceof EnvError) {
        log("error", "env_invalid", { message: err.message });
        return jsonError(500, "internal_error", "Relay misconfigured. Check secrets and bindings.");
      }
      throw err;
    }

    const url = new URL(request.url);
    try {
      switch (url.pathname) {
        case "/report":
        case "/api/report":
          return await handleReport(request, parsed);
        case "/attachment":
        case "/api/attachment":
          return await handleAttachment(request, parsed);
        case "/my-issues":
        case "/api/my-issues":
          return await handleMyIssues(request, parsed);
        default:
          return jsonError(404, "not_found");
      }
    } catch (err) {
      log("error", "uncaught", { message: err instanceof Error ? err.message : String(err) });
      return jsonError(500, "internal_error");
    }
  },
} satisfies ExportedHandler<WorkerEnv>;
