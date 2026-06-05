/**
 * Idempotency-Key dedup store backed by KV (24-hour window).
 *
 * Mirrors the Vercel implementation. Without a KV binding, falls back to
 * per-isolate in-memory state.
 */

import type { ParsedEnv } from "./env.js";

const TTL_SECONDS = 60 * 60 * 24;

const memoryStore = new Map<string, { recordedAt: number; bodyHash: string; response: unknown }>();

export interface LookupArgs {
  env: ParsedEnv;
  key: string;
  bodyHash: string;
}

export type LookupResult =
  | { status: "miss" }
  | { status: "hit"; response: unknown }
  | { status: "conflict" };

export async function lookup(args: LookupArgs): Promise<LookupResult> {
  if (args.env.idempotencyKV) {
    const raw = await args.env.idempotencyKV.get(`gittickets:idem:${args.key}`);
    if (!raw) return { status: "miss" };
    const parsed = JSON.parse(raw) as { bodyHash: string; response: unknown };
    if (parsed.bodyHash !== args.bodyHash) return { status: "conflict" };
    return { status: "hit", response: parsed.response };
  }
  const entry = memoryStore.get(args.key);
  if (!entry) return { status: "miss" };
  if (entry.bodyHash !== args.bodyHash) return { status: "conflict" };
  return { status: "hit", response: entry.response };
}

export interface RecordArgs extends LookupArgs {
  response: unknown;
  now: number;
}

export async function record(args: RecordArgs): Promise<void> {
  const payload = JSON.stringify({ bodyHash: args.bodyHash, response: args.response });
  if (args.env.idempotencyKV) {
    await args.env.idempotencyKV.put(`gittickets:idem:${args.key}`, payload, {
      expirationTtl: TTL_SECONDS,
    });
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
