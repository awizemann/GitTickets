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

export async function latestComment(args: {
  owner: string;
  repo: string;
  issueNumber: number;
  installationToken: string;
  fetchFn?: typeof fetch;
}): Promise<{ createdAt: string } | null> {
  const fetchFn = args.fetchFn ?? fetch;
  const url =
    `https://api.github.com/repos/${encodeURIComponent(args.owner)}/${encodeURIComponent(args.repo)}/issues/${args.issueNumber}/comments` +
    `?per_page=1&sort=created&direction=desc`;
  const response = await fetchFn(url, { headers: githubHeaders(args.installationToken) });
  if (!response.ok) return null;
  const items = (await response.json()) as Array<{ created_at: string }>;
  if (items.length === 0) return null;
  return { createdAt: items[0]!.created_at };
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
