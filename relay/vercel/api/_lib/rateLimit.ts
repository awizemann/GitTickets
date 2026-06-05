/**
 * Per-IP and per-deviceID rate limiting.
 *
 * Strategy: rolling hourly window using Redis INCR + EXPIRE when Upstash is
 * configured; an in-memory Map fallback for dev / single-instance use. The
 * fallback resets when the function instance recycles — fine for low-volume
 * relays, undersized for multi-region production.
 */

import type { Env } from "./env.js";

export interface RateLimitArgs {
  env: Env;
  ip: string | null;
  deviceID: string | null;
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
  const checks: Array<{ key: string; limit: number }> = [];
  if (args.ip) {
    checks.push({ key: `ip:${args.ip}`, limit: args.env.ipHourlyLimit });
  }
  if (args.deviceID) {
    checks.push({
      key: `dev:${args.deviceID}`,
      limit: args.env.deviceHourlyLimit,
    });
  }
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
