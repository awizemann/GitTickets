/**
 * Per-IP and per-deviceID rate limiting.
 *
 * Strategy: rolling hourly window using Redis INCR + EXPIRE when Upstash is
 * configured; an in-memory Map fallback for dev / single-instance use. The
 * fallback resets when the function instance recycles — fine for low-volume
 * relays, undersized for multi-region production.
 */

import type { Env } from "./env.js";

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
  env: Env;
  ip: string | null;
  deviceID: string | null;
  /** Defaults to "write" (the original, shared `ip:` / `dev:` buckets). */
  kind?: RateLimitKind;
  now: number; // unix seconds
}

export interface RateLimitResult {
  allowed: boolean;
  retryAfter?: number; // seconds
}

interface Counter {
  count: number;
  resetAt: number; // unix seconds
}

/** Per-key in-memory bucket. Cleared per function instance. */
const memoryBuckets = new Map<string, Counter>();

export async function checkRateLimits(
  args: RateLimitArgs,
): Promise<RateLimitResult> {
  const checks = bucketsFor(args);
  if (checks.length === 0) return { allowed: true };

  const upstash = await getUpstashClient(args.env);

  for (const { key, limit } of checks) {
    const counter = upstash
      ? await incrementUpstash(upstash, key, args.now)
      : incrementMemory(key, args.now);

    if (counter.count > limit) {
      return {
        allowed: false,
        retryAfter: Math.max(1, counter.resetAt - args.now),
      };
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

interface PipelineBuilder {
  incr(key: string): PipelineBuilder;
  expire(key: string, seconds: number): PipelineBuilder;
  exec<T>(): Promise<T[]>;
}

interface UpstashClient {
  pipeline(): PipelineBuilder;
  ttl(key: string): Promise<number>;
}

async function getUpstashClient(env: Env): Promise<UpstashClient | null> {
  if (!env.upstashRedisUrl || !env.upstashRedisToken) return null;
  try {
    // Dynamic import keeps Upstash optional — no runtime cost when absent.
    const mod = (await import("@upstash/redis")) as {
      Redis: new (config: { url: string; token: string }) => UpstashClient;
    };
    return new mod.Redis({ url: env.upstashRedisUrl, token: env.upstashRedisToken });
  } catch {
    return null;
  }
}

async function incrementUpstash(
  client: UpstashClient,
  key: string,
  now: number,
): Promise<Counter> {
  const namespaced = `gittickets:rl:${key}`;
  const [count] = await client
    .pipeline()
    .incr(namespaced)
    .expire(namespaced, 3600)
    .exec<number>();
  const ttl = await client.ttl(namespaced);
  return {
    count: count ?? 1,
    resetAt: now + (ttl > 0 ? ttl : 3600),
  };
}

/** Test-only — wipes the in-memory buckets. */
export function _resetRateLimitForTests(): void {
  memoryBuckets.clear();
}
