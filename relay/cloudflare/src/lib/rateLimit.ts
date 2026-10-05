/**
 * Per-IP and per-deviceID hourly rate limits backed by Cloudflare KV.
 *
 * Without a KV binding the relay falls back to an in-memory Map per isolate
 * (acceptable for low traffic, undersized for production).
 *
 * KV is eventually consistent across regions but each datacenter reads its
 * local replica immediately — fine for an hourly bucket where occasional
 * over-grant by a small margin is acceptable.
 */

import type { ParsedEnv } from "./env.js";

/**
 * Which budget a request draws from. Writes (`/report`, `/attachment`) and
 * reads (`/my-issues`, `/comments`) use disjoint buckets so polling for
 * replies can never exhaust the budget a user needs to file a report.
 */
export type RateLimitKind = "write" | "read";

/**
 * The single source of truth for which budget each endpoint draws from.
 * Handlers pass their route here (via `enforceRateLimits`) rather than a kind,
 * so the mapping is data the tests can pin down.
 */
export const ENDPOINT_RATE_LIMIT_KIND = {
  "/report": "write",
  "/attachment": "write",
  "/my-issues": "read",
  "/comments": "read",
} as const satisfies Record<string, RateLimitKind>;

export type RateLimitedEndpoint = keyof typeof ENDPOINT_RATE_LIMIT_KIND;

export interface RateLimitArgs {
  env: ParsedEnv;
  ip: string | null;
  deviceID: string | null;
  /** Defaults to "write" (the original, shared `ip:` / `dev:` buckets). */
  kind?: RateLimitKind;
  now: number;
}

export interface RateLimitResult {
  allowed: boolean;
  retryAfter?: number;
}

interface Counter {
  count: number;
  resetAt: number;
}

const memoryBuckets = new Map<string, Counter>();

export async function checkRateLimits(args: RateLimitArgs): Promise<RateLimitResult> {
  const checks = bucketsFor(args);
  if (checks.length === 0) return { allowed: true };

  for (const { key, limit } of checks) {
    const counter = args.env.rateLimitKV
      ? await incrementKV(args.env.rateLimitKV, key, args.now)
      : incrementMemory(key, args.now);
    if (counter.count > limit) {
      return { allowed: false, retryAfter: Math.max(1, counter.resetAt - args.now) };
    }
  }
  return { allowed: true };
}

/**
 * Bucket keys + limits for a request. Write keys (`ip:`, `dev:`) are unchanged
 * from earlier releases so existing deployments keep their counters and limits;
 * reads get their own `rip:` / `rdev:` keys and `GITTICKETS_READ_*` limits.
 */
export function bucketsFor(
  args: Pick<RateLimitArgs, "env" | "ip" | "deviceID" | "kind">,
): Array<{ key: string; limit: number }> {
  const read = args.kind === "read";
  const ipPrefix = read ? "rip" : "ip";
  const devPrefix = read ? "rdev" : "dev";
  const ipLimit = read ? args.env.readIpHourlyLimit : args.env.ipHourlyLimit;
  const devLimit = read ? args.env.readDeviceHourlyLimit : args.env.deviceHourlyLimit;
  const checks: Array<{ key: string; limit: number }> = [];
  if (args.ip) checks.push({ key: `${ipPrefix}:${args.ip}`, limit: ipLimit });
  if (args.deviceID) checks.push({ key: `${devPrefix}:${args.deviceID}`, limit: devLimit });
  return checks;
}

function incrementMemory(key: string, now: number): Counter {
  const existing = memoryBuckets.get(key);
  if (!existing || existing.resetAt <= now) {
    const fresh: Counter = { count: 1, resetAt: now + 3600 };
    memoryBuckets.set(key, fresh);
    return fresh;
  }
  existing.count += 1;
  return existing;
}

async function incrementKV(kv: KVNamespace, key: string, now: number): Promise<Counter> {
  const namespaced = `gittickets:rl:${key}`;
  // KV doesn't have atomic INCR — fetch, increment, put. The race window is
  // accepted: under a flood, occasional double-grant is preferable to
  // shedding all traffic on contention.
  const existing = (await kv.get(namespaced, "json")) as Counter | null;
  let next: Counter;
  if (!existing || existing.resetAt <= now) {
    next = { count: 1, resetAt: now + 3600 };
  } else {
    next = { count: existing.count + 1, resetAt: existing.resetAt };
  }
  await kv.put(namespaced, JSON.stringify(next), {
    expirationTtl: Math.max(60, next.resetAt - now),
  });
  return next;
}

export function _resetRateLimitForTests(): void {
  memoryBuckets.clear();
}
