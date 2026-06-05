/**
 * Structured logger — JSON lines to stdout. Cloudflare collects these via
 * `wrangler tail` and the Workers dashboard.
 *
 * Never log: private key, shared secret, installation tokens, full request
 * bodies.
 */

export type LogLevel = "info" | "warning" | "error";

export function log(level: LogLevel, event: string, fields: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level,
      event,
      ...fields,
    }),
  );
}
