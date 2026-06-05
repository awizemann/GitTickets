/**
 * Response envelope helpers. Mirror the JSON shape the Vercel template
 * returns so the SDK's error parsing is runtime-agnostic.
 */

export interface ErrorEnvelope {
  error: string;
  message?: string;
  byteLimit?: number;
}

export function jsonResponse(status: number, body: unknown, extraHeaders?: HeadersInit): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(body), { status, headers });
}

export function jsonError(status: number, error: string, message?: string, byteLimit?: number): Response {
  const envelope: ErrorEnvelope = { error };
  if (message) envelope.message = message;
  if (byteLimit !== undefined) envelope.byteLimit = byteLimit;
  return jsonResponse(status, envelope);
}

export function rateLimitedResponse(retryAfter: number): Response {
  const headers = new Headers();
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Retry-After", `${retryAfter}`);
  return new Response(JSON.stringify({ error: "rate_limited", message: "Hourly limit exceeded." }), {
    status: 429,
    headers,
  });
}
