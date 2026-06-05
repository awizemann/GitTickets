/**
 * Structured-ish logger. Outputs JSON lines to stdout so Vercel surfaces
 * them in the dashboard with searchable fields.
 *
 * Never log:
 * - The GitHub App private key.
 * - The shared secret.
 * - Installation tokens.
 * - Full request bodies (they may contain user PII the redaction pipeline
 *   stripped from diagnostics but couldn't strip from user-typed body text).
 */

export type LogLevel = "info" | "warning" | "error";

export function log(
  level: LogLevel,
  event: string,
  fields: Record<string, unknown> = {},
): void {
  // eslint-disable-next-line no-console
  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level,
      event,
      ...fields,
    }),
  );
}
