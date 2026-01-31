/**
 * GitHub provider configuration and API types
 */

import type { FetchWindow } from '../../schemas/index.js';

/**
 * GitHub account configuration
 */
export interface GitHubAccountConfig {
  /** Unique identifier for this account */
  id: string;
  /** GitHub personal access token with appropriate scopes */
  token: string;
  /** Optional description for this account */
  description?: string;
}

/**
 * GitHub provider configuration
 */
export interface GitHubProviderConfig {
  accounts: GitHubAccountConfig[];
}

/**
 * Options for fetching GitHub activities
 */
export interface GitHubFetchOptions {
  /** Account configuration to use */
  account: GitHubAccountConfig;
  /** Time window for fetching activities */
  window: FetchWindow;
}

/**
 * Minimal fields from GitHub GraphQL API for contributions
 * Only fields needed for UnifiedActivity + minimal drill-down
 */

export interface GitHubCommitNode {
  oid: string;
  message: string;
  committedDate: string;
  url: string;
  author: {
    user: {
      login: string;
    } | null;
  } | null;
}

export interface GitHubPullRequestNode {
  id: string;
  number: number;
  title: string;
  createdAt: string;
  url: string;
  author: {
    login: string;
  } | null;
}

export interface GitHubIssueNode {
  id: string;
  number: number;
  title: string;
  createdAt: string;
  url: string;
  author: {
    login: string;
  } | null;
}

export interface GitHubIssueCommentNode {
  id: string;
  body: string;
  createdAt: string;
  url: string;
  author: {
    login: string;
  } | null;
  issue: {
    number: number;
    title: string;
  };
}

export interface GitHubPullRequestReviewNode {
  id: string;
  body: string;
  createdAt: string;
  url: string;
  author: {
    login: string;
  } | null;
  pullRequest: {
    number: number;
    title: string;
  };
}

/**
 * GraphQL response types for contributions query
 */
export interface GitHubContributionsResponse {
  viewer: {
    contributionsCollection: {
      commitContributionsByRepository: Array<{
        repository: {
          nameWithOwner: string;
        };
        contributions: {
          nodes: Array<{
            commitCount: number;
            occurredAt: string;
          }>;
        };
      }>;
      pullRequestContributions: {
        nodes: Array<{
          pullRequest: GitHubPullRequestNode;
        }>;
      };
      issueContributions: {
        nodes: Array<{
          issue: GitHubIssueNode;
        }>;
      };
      pullRequestReviewContributions: {
        nodes: Array<{
          pullRequestReview: GitHubPullRequestReviewNode;
        }>;
      };
    };
  };
}

/**
 * GraphQL response for user events
 */
export interface GitHubUserEventsResponse {
  viewer: {
    login: string;
    issueComments: {
      nodes: GitHubIssueCommentNode[];
      pageInfo: {
        hasNextPage: boolean;
        endCursor: string | null;
      };
    };
  };
}
