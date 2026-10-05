/**
 * Thin GitHub REST API client — identical contract to the Vercel template.
 */

export interface GitHubIssueCreateArgs {
  owner: string;
  repo: string;
  installationToken: string;
  title: string;
  body: string;
  labels: string[];
  fetchFn?: typeof fetch;
}

export interface GitHubIssueCreateResult {
  number: number;
  htmlUrl: string;
  title: string;
  createdAt: string;
  appliedLabels: string[];
}

export async function createIssue(args: GitHubIssueCreateArgs): Promise<GitHubIssueCreateResult> {
  const fetchFn = args.fetchFn ?? fetch;
  const url = `https://api.github.com/repos/${encodeURIComponent(args.owner)}/${encodeURIComponent(args.repo)}/issues`;
  const response = await fetchFn(url, {
    method: "POST",
    headers: githubHeaders(args.installationToken),
    body: JSON.stringify({ title: args.title, body: args.body, labels: args.labels }),
  });
  if (!response.ok) {
    throw new GitHubAPIError(response.status, await response.text());
  }
  const payload = (await response.json()) as {
    number: number;
    html_url: string;
    title: string;
    created_at: string;
    labels: Array<{ name: string } | string>;
  };
  return {
    number: payload.number,
    htmlUrl: payload.html_url,
    title: payload.title,
    createdAt: payload.created_at,
    appliedLabels: payload.labels.map((label) =>
      typeof label === "string" ? label : label.name,
    ),
  };
}

export interface GitHubListIssuesArgs {
  owner: string;
  repo: string;
  installationToken: string;
  label: string;
  fetchFn?: typeof fetch;
}

export interface GitHubIssueListItem {
  number: number;
  htmlUrl: string;
  title: string;
  state: string;
  createdAt: string;
  updatedAt: string;
  body: string;
  comments: number;
}

export async function listLabeledIssues(
  args: GitHubListIssuesArgs,
): Promise<GitHubIssueListItem[]> {
  const fetchFn = args.fetchFn ?? fetch;
  const all: GitHubIssueListItem[] = [];
  for (let page = 1; page <= 5; page += 1) {
    const url =
      `https://api.github.com/repos/${encodeURIComponent(args.owner)}/${encodeURIComponent(args.repo)}/issues` +
      `?labels=${encodeURIComponent(args.label)}&state=all&per_page=100&page=${page}`;
    const response = await fetchFn(url, { headers: githubHeaders(args.installationToken) });
    if (!response.ok) {
      throw new GitHubAPIError(response.status, await response.text());
    }
    const items = (await response.json()) as Array<{
      number: number;
      html_url: string;
      title: string;
      state: string;
      created_at: string;
      updated_at: string;
      body: string | null;
      comments: number;
      pull_request?: unknown;
    }>;
    for (const item of items) {
      if (item.pull_request) continue;
      all.push({
        number: item.number,
        htmlUrl: item.html_url,
        title: item.title,
        state: item.state,
        createdAt: item.created_at,
        updatedAt: item.updated_at,
        body: item.body ?? "",
        comments: item.comments,
      });
    }
    if (items.length < 100) break;
  }
  return all;
}

export interface GitHubFullComment {
  id: number;
  author: string;
  body: string;
  createdAt: string;
}

/**
 * Pages through up to 5 pages × 100 = 500 comments on the given issue,
 * oldest first. Bound mirrors the Vercel template — well above any
 * realistic UI need.
 */
export async function listComments(args: {
  owner: string;
  repo: string;
  issueNumber: number;
  installationToken: string;
  fetchFn?: typeof fetch;
}): Promise<GitHubFullComment[]> {
  const fetchFn = args.fetchFn ?? fetch;
  const all: GitHubFullComment[] = [];
  for (let page = 1; page <= 5; page += 1) {
    const url =
      `https://api.github.com/repos/${encodeURIComponent(args.owner)}/${encodeURIComponent(args.repo)}/issues/${args.issueNumber}/comments` +
      `?per_page=100&page=${page}`;
    const response = await fetchFn(url, { headers: githubHeaders(args.installationToken) });
    if (!response.ok) {
      throw new GitHubAPIError(response.status, await response.text());
    }
    const items = (await response.json()) as Array<{
      id: number;
      body: string | null;
      created_at: string;
      user: { login: string } | null;
    }>;
    for (const item of items) {
      all.push({
        id: item.id,
        author: item.user?.login ?? "",
        body: item.body ?? "",
        createdAt: item.created_at,
      });
    }
    if (items.length < 100) break;
  }
  return all;
}

/**
 * Returns the newest comment's `created_at` for an issue, or null.
 *
 * The per-issue "List issue comments" endpoint only accepts `since`,
 * `per_page` and `page` and always returns comments in ascending ID order
 * (`sort`/`direction` exist only on the repo-wide `/issues/comments`
 * endpoint and are silently ignored here). So the newest comment is page
 * N of size 1, where N is the issue's comment count — one request in the
 * normal case.
 *
 * `commentCount` comes from the issue object and can be stale. If it
 * over-counts (a comment was deleted), page N is past the end and returns
 * `[]`; we then make exactly one fallback request for the 100-comment page
 * that holds comment `commentCount - 1` and take its last entry, which
 * covers any deficit that still lands on that page. If it under-counts (a
 * comment arrived after the issue list was fetched), page N is a slightly
 * older comment — acceptable for a "last reply" hint.
 */
export async function latestComment(args: {
  owner: string;
  repo: string;
  issueNumber: number;
  /** The issue's `comments` count, from the issue list response. */
  commentCount: number;
  installationToken: string;
  fetchFn?: typeof fetch;
}): Promise<{ createdAt: string } | null> {
  if (args.commentCount <= 0) return null;
  const fetchFn = args.fetchFn ?? fetch;
  const base =
    `https://api.github.com/repos/${encodeURIComponent(args.owner)}/${encodeURIComponent(args.repo)}/issues/${args.issueNumber}/comments`;
  const fetchPage = async (
    perPage: number,
    page: number,
  ): Promise<Array<{ created_at: string }> | null> => {
    const response = await fetchFn(`${base}?per_page=${perPage}&page=${page}`, {
      headers: githubHeaders(args.installationToken),
    });
    if (!response.ok) return null;
    return (await response.json()) as Array<{ created_at: string }>;
  };

  const exact = await fetchPage(1, args.commentCount);
  if (exact === null) return null;
  if (exact.length > 0) return { createdAt: exact[0]!.created_at };

  // Stale (over-counted) issue.comments — one fallback request.
  if (args.commentCount <= 1) return null;
  const fallbackPage = Math.max(1, Math.ceil((args.commentCount - 1) / 100));
  const items = await fetchPage(100, fallbackPage);
  if (items === null || items.length === 0) return null;
  return { createdAt: items[items.length - 1]!.created_at };
}

function githubHeaders(token: string): Record<string, string> {
  return {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "gittickets-relay",
    "Content-Type": "application/json",
  };
}

export class GitHubAPIError extends Error {
  readonly status: number;
  constructor(status: number, body: string) {
    super(`GitHub API ${status}: ${body.slice(0, 200)}`);
    this.status = status;
    this.name = "GitHubAPIError";
  }
}
