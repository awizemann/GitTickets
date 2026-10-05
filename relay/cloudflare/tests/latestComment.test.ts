import { describe, expect, it } from "vitest";

import { latestComment } from "../src/lib/github.js";

/** Simulates GitHub's per-issue comments endpoint: ascending order, ignores sort/direction. */
function mockGitHub(createdAts: string[]) {
  const urls: string[] = [];
  const fetchFn = (async (input: string | URL | Request) => {
    const url = new URL(String(input));
    urls.push(url.toString());
    const perPage = Number(url.searchParams.get("per_page") ?? "30");
    const page = Number(url.searchParams.get("page") ?? "1");
    const slice = createdAts
      .slice((page - 1) * perPage, page * perPage)
      .map((created_at) => ({ created_at }));
    return new Response(JSON.stringify(slice), { status: 200 });
  }) as typeof fetch;
  return { fetchFn, urls };
}

const base = { owner: "o", repo: "r", issueNumber: 7, installationToken: "t" };
const dates = ["2026-01-01T00:00:00Z", "2026-02-01T00:00:00Z", "2026-03-01T00:00:00Z"];

describe("latestComment", () => {
  it("requests page=<count> with per_page=1 and no sort/direction, returning the newest date", async () => {
    const { fetchFn, urls } = mockGitHub(dates);
    const result = await latestComment({ ...base, commentCount: 3, fetchFn });
    expect(result).toEqual({ createdAt: "2026-03-01T00:00:00Z" });
    expect(urls).toHaveLength(1);
    const url = new URL(urls[0]!);
    expect(url.pathname).toBe("/repos/o/r/issues/7/comments");
    expect(url.searchParams.get("per_page")).toBe("1");
    expect(url.searchParams.get("page")).toBe("3");
    expect(url.searchParams.has("sort")).toBe(false);
    expect(url.searchParams.has("direction")).toBe(false);
  });

  it("falls back to one 100-page request when the count is stale-high", async () => {
    const { fetchFn, urls } = mockGitHub(dates);
    const result = await latestComment({ ...base, commentCount: 5, fetchFn });
    expect(result).toEqual({ createdAt: "2026-03-01T00:00:00Z" });
    expect(urls).toHaveLength(2);
    const fallback = new URL(urls[1]!);
    expect(fallback.searchParams.get("per_page")).toBe("100");
    expect(fallback.searchParams.get("page")).toBe("1");
  });

  it("stale-high fallback picks the right page past 100 comments", async () => {
    const many = Array.from({ length: 150 }, (_, i) => `2026-01-01T00:00:${String(i).padStart(3, "0")}Z`);
    const { fetchFn, urls } = mockGitHub(many);
    const result = await latestComment({ ...base, commentCount: 151, fetchFn });
    expect(result).toEqual({ createdAt: many[149] });
    expect(new URL(urls[1]!).searchParams.get("page")).toBe("2");
  });

  it("stale-high fallback at the N-1 page boundary (count 101, actual 100) uses page 1", async () => {
    const many = Array.from({ length: 100 }, (_, i) => `2026-01-01T00:00:${String(i).padStart(3, "0")}Z`);
    const { fetchFn, urls } = mockGitHub(many);
    const result = await latestComment({ ...base, commentCount: 101, fetchFn });
    expect(result).toEqual({ createdAt: many[99] });
    expect(urls).toHaveLength(2);
    const fallback = new URL(urls[1]!);
    expect(fallback.searchParams.get("per_page")).toBe("100");
    expect(fallback.searchParams.get("page")).toBe("1");
  });

  it("returns null without fetching when the count is zero", async () => {
    const { fetchFn, urls } = mockGitHub([]);
    expect(await latestComment({ ...base, commentCount: 0, fetchFn })).toBeNull();
    expect(urls).toHaveLength(0);
  });

  it("returns null when the only comment was deleted (no fallback)", async () => {
    const { fetchFn, urls } = mockGitHub([]);
    expect(await latestComment({ ...base, commentCount: 1, fetchFn })).toBeNull();
    expect(urls).toHaveLength(1);
  });

  it("returns null on a non-OK response without a fallback request", async () => {
    let calls = 0;
    const fetchFn = (async () => {
      calls += 1;
      return new Response("nope", { status: 500 });
    }) as typeof fetch;
    expect(await latestComment({ ...base, commentCount: 2, fetchFn })).toBeNull();
    expect(calls).toBe(1);
  });
});
