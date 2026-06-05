/**
 * Idempotency-key dedup store.
 *
 * Used by POST /report to ensure a repeated request with the same
 * `X-GitTickets-Idempotency-Key` returns the original response without
 * creating a duplicate GitHub issue. Window: 24 hours.
 *
 * Upstash Redis when available; in-memory Map fallback otherwise.
 */

import type { Env } from "./env.js";

const TTL_SECONDS = 60 * 60 * 24; // 24 hours

const memoryStore = new Map<string, { recordedAt: number; response: unknown; bodyHash: string }>();

interface UpstashClient {
  set(
    key: string,
    value: string,
    opts: { ex: number; nx?: boolean },
  ): Promise<"OK" | null>;
  get(key: string): Promise<string | null>;
}

async function getUpstash(env: Env): Promise<UpstashClient | null> {
  if (!env.upstashRedisUrl || !env.upstashRedisToken) return null;
  try {
    const mod = (await import("@upstash/redis")) as {
      Redis: new (config: { url: string; token: string }) => UpstashClient;
    };
    return new mod.Redis({ url: env.upstashRedisUrl, token: env.upstashRedisToken });
  } catch {
    return null;
  }
}

export interface RecordedResponse {
  response: unknown;
  bodyHash: string;
  recordedAt: number;
}

export interface LookupArgs {
  env: Env;
  key: string;
  bodyHash: string;
}

export type LookupResult =
  | { status: "miss" }
  | { status: "hit"; response: unknown }
  | { status: "conflict" };

/** Looks up a prior response. `conflict` means same key but different body
 *  hash — the relay should return 409 to make the client surface the bug
 *  rather than silently masking duplicate-submission state. */
export async function lookup(args: LookupArgs): Promise<LookupResult> {
  const client = await getUpstash(args.env);
  const namespaced = `gittickets:idem:${args.key}`;
  if (client) {
    const raw = await client.get(namespaced);
    if (!raw) return { status: "miss" };
    const parsed = JSON.parse(raw) as { bodyHash: string; response: unknown };
    if (parsed.bodyHash !== args.bodyHash) return { status: "conflict" };
    return { status: "hit", response: parsed.response };
  }
  const stored = memoryStore.get(args.key);
  if (!stored) return { status: "miss" };
  if (stored.bodyHash !== args.bodyHash) return { status: "conflict" };
  return { status: "hit", response: stored.response };
}

export interface RecordArgs extends LookupArgs {
  response: unknown;
  now: number;
}

export async function record(args: RecordArgs): Promise<void> {
  const client = await getUpstash(args.env);
  const namespaced = `gittickets:idem:${args.key}`;
  const payload = JSON.stringify({ bodyHash: args.bodyHash, response: args.response });
  if (client) {
    // nx: true so a winning request gets recorded; duplicates won't overwrite.
    await client.set(namespaced, payload, { ex: TTL_SECONDS, nx: true });
    return;
  }
  if (!memoryStore.has(args.key)) {
    memoryStore.set(args.key, {
      recordedAt: args.now,
      bodyHash: args.bodyHash,
      response: args.response,
    });
    pruneMemoryStore(args.now);
  }
}

function pruneMemoryStore(now: number): void {
  for (const [key, entry] of memoryStore) {
    if (now - entry.recordedAt > TTL_SECONDS) memoryStore.delete(key);
  }
}

export function _resetIdempotencyForTests(): void {
  memoryStore.clear();
}
