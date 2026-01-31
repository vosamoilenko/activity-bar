/**
 * GitHub provider fetch implementation
 *
 * Uses GitHub GraphQL API to fetch activity data with minimal fields.
 */

import type { UnifiedActivity, FetchWindow } from '../../schemas/index.js';
import type {
  GitHubAccountConfig,
  GitHubFetchOptions,
  GitHubContributionsResponse,
  GitHubUserEventsResponse,
  GitHubPullRequestNode,
  GitHubIssueNode,
  GitHubPullRequestReviewNode,
  GitHubIssueCommentNode,
} from './types.js';
import { CONTRIBUTIONS_QUERY, ISSUE_COMMENTS_QUERY, VIEWER_LOGIN_QUERY } from './queries.js';

const GITHUB_GRAPHQL_ENDPOINT = 'https://api.github.com/graphql';

/**
 * Execute a GraphQL query against GitHub API
 */
async function executeQuery<T>(
  token: string,
  query: string,
  variables: Record<string, unknown>
): Promise<T> {
  const response = await fetch(GITHUB_GRAPHQL_ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'User-Agent': 'ActivityDiscovery/1.0',
    },
    body: JSON.stringify({ query, variables }),
  });

  if (!response.ok) {
    throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
  }

  const json = (await response.json()) as { data?: T; errors?: Array<{ message: string }> };

  if (json.errors?.length) {
    throw new Error(`GitHub GraphQL errors: ${json.errors.map((e) => e.message).join(', ')}`);
  }

  if (!json.data) {
    throw new Error('GitHub API returned no data');
  }

  return json.data;
}

/**
 * Build time window parameters for GraphQL queries
 */
function buildTimeWindow(window: FetchWindow): { from: string; to: string } {
  if (window.timeMin && window.timeMax) {
    return { from: window.timeMin, to: window.timeMax };
  }

  const now = new Date();
  const daysBack = window.daysBack ?? 30;
  const from = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);

  return {
    from: from.toISOString(),
    to: now.toISOString(),
  };
}

/**
 * Normalize a GitHub pull request to UnifiedActivity
 */
function normalizePullRequest(
  pr: GitHubPullRequestNode,
  accountId: string
): UnifiedActivity {
  return {
    id: `github:${accountId}:pr-${pr.id}`,
    provider: 'github',
    accountId,
    sourceId: pr.id,
    type: 'pull_request',
    timestamp: pr.createdAt,
    title: pr.title,
    url: pr.url,
    participants: pr.author?.login ? [pr.author.login] : undefined,
  };
}

/**
 * Normalize a GitHub issue to UnifiedActivity
 */
function normalizeIssue(
  issue: GitHubIssueNode,
  accountId: string
): UnifiedActivity {
  return {
    id: `github:${accountId}:issue-${issue.id}`,
    provider: 'github',
    accountId,
    sourceId: issue.id,
    type: 'issue',
    timestamp: issue.createdAt,
    title: issue.title,
    url: issue.url,
    participants: issue.author?.login ? [issue.author.login] : undefined,
  };
}

/**
 * Normalize a GitHub PR review to UnifiedActivity
 */
function normalizePullRequestReview(
  review: GitHubPullRequestReviewNode,
  accountId: string
): UnifiedActivity {
  return {
    id: `github:${accountId}:review-${review.id}`,
    provider: 'github',
    accountId,
    sourceId: review.id,
    type: 'code_review',
    timestamp: review.createdAt,
    title: `Review on PR #${review.pullRequest.number}: ${review.pullRequest.title}`,
    summary: review.body?.slice(0, 200) || undefined,
    url: review.url,
    participants: review.author?.login ? [review.author.login] : undefined,
  };
}

/**
 * Normalize a GitHub issue comment to UnifiedActivity
 */
function normalizeIssueComment(
  comment: GitHubIssueCommentNode,
  accountId: string
): UnifiedActivity {
  return {
    id: `github:${accountId}:comment-${comment.id}`,
    provider: 'github',
    accountId,
    sourceId: comment.id,
    type: 'issue_comment',
    timestamp: comment.createdAt,
    title: `Comment on #${comment.issue.number}: ${comment.issue.title}`,
    summary: comment.body?.slice(0, 200) || undefined,
    url: comment.url,
    participants: comment.author?.login ? [comment.author.login] : undefined,
  };
}

/**
 * Normalize commit contribution to UnifiedActivity
 *
 * Note: GitHub's contributionsCollection provides commit counts per day per repo,
 * not individual commits. We create one activity per contribution entry.
 */
function normalizeCommitContribution(
  repoName: string,
  occurredAt: string,
  commitCount: number,
  accountId: string
): UnifiedActivity {
  // Create a deterministic ID based on repo + date
  const dateStr = occurredAt.slice(0, 10);
  const sourceId = `commits-${repoName.replace('/', '-')}-${dateStr}`;

  return {
    id: `github:${accountId}:${sourceId}`,
    provider: 'github',
    accountId,
    sourceId,
    type: 'commit',
    timestamp: occurredAt,
    title: `${commitCount} commit${commitCount > 1 ? 's' : ''} to ${repoName}`,
    summary: `Pushed ${commitCount} commit${commitCount > 1 ? 's' : ''} to ${repoName}`,
  };
}

/**
 * Fetch activities for a single GitHub account
 */
export async function fetchGitHubActivities(
  options: GitHubFetchOptions
): Promise<UnifiedActivity[]> {
  const { account, window } = options;
  const { from, to } = buildTimeWindow(window);
  const activities: UnifiedActivity[] = [];

  // Fetch contributions (commits, PRs, issues, reviews)
  const contributionsData = await executeQuery<GitHubContributionsResponse>(
    account.token,
    CONTRIBUTIONS_QUERY,
    { from, to }
  );

  const collection = contributionsData.viewer.contributionsCollection;

  // Process commit contributions
  for (const repoContrib of collection.commitContributionsByRepository) {
    for (const contrib of repoContrib.contributions.nodes) {
      if (contrib.commitCount > 0) {
        activities.push(
          normalizeCommitContribution(
            repoContrib.repository.nameWithOwner,
            contrib.occurredAt,
            contrib.commitCount,
            account.id
          )
        );
      }
    }
  }

  // Process pull request contributions
  for (const prContrib of collection.pullRequestContributions.nodes) {
    activities.push(normalizePullRequest(prContrib.pullRequest, account.id));
  }

  // Process issue contributions
  for (const issueContrib of collection.issueContributions.nodes) {
    activities.push(normalizeIssue(issueContrib.issue, account.id));
  }

  // Process PR review contributions
  for (const reviewContrib of collection.pullRequestReviewContributions.nodes) {
    activities.push(normalizePullRequestReview(reviewContrib.pullRequestReview, account.id));
  }

  // Fetch issue comments (with pagination)
  const fromDate = new Date(from);
  let commentsCursor: string | null = null;
  let commentsHasNext = true;

  while (commentsHasNext) {
    const commentsData: GitHubUserEventsResponse = await executeQuery<GitHubUserEventsResponse>(
      account.token,
      ISSUE_COMMENTS_QUERY,
      { from, first: 100, after: commentsCursor }
    );

    const viewerLogin = commentsData.viewer.login;
    for (const comment of commentsData.viewer.issueComments.nodes) {
      // Filter by time window (API doesn't support time filter directly)
      const commentDate = new Date(comment.createdAt);
      if (commentDate >= fromDate && comment.author?.login === viewerLogin) {
        activities.push(normalizeIssueComment(comment, account.id));
      }
    }

    commentsHasNext = commentsData.viewer.issueComments.pageInfo.hasNextPage;
    commentsCursor = commentsData.viewer.issueComments.pageInfo.endCursor;

    // Safety: stop after a reasonable number of pages
    if (activities.length > 10000) {
      console.warn('GitHub: Reached activity limit, stopping pagination');
      break;
    }
  }

  // Sort by timestamp descending (most recent first)
  activities.sort((a, b) => b.timestamp.localeCompare(a.timestamp));

  return activities;
}

/**
 * Fetch activities for multiple GitHub accounts
 */
export async function fetchGitHubActivitiesForAccounts(
  accounts: GitHubAccountConfig[],
  window: FetchWindow
): Promise<Map<string, UnifiedActivity[]>> {
  const results = new Map<string, UnifiedActivity[]>();

  for (const account of accounts) {
    try {
      const activities = await fetchGitHubActivities({ account, window });
      results.set(account.id, activities);
    } catch (error) {
      console.error(`GitHub: Failed to fetch activities for account ${account.id}:`, error);
      results.set(account.id, []);
    }
  }

  return results;
}

/**
 * Get the authenticated user's login
 */
export async function getViewerLogin(token: string): Promise<string> {
  const data = await executeQuery<{ viewer: { login: string } }>(
    token,
    VIEWER_LOGIN_QUERY,
    {}
  );
  return data.viewer.login;
}
