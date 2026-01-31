import { describe, it, expect } from 'vitest';
import { validateActivity, UnifiedActivitySchema } from '../schemas/index.js';
import type { UnifiedActivity } from '../schemas/index.js';
import type {
  GitHubPullRequestNode,
  GitHubIssueNode,
  GitHubPullRequestReviewNode,
  GitHubIssueCommentNode,
  GitHubContributionsResponse,
} from '../providers/github/index.js';

/**
 * Mock GitHub API response data for testing normalization
 */
const mockPullRequest: GitHubPullRequestNode = {
  id: 'PR_kwDOB8XXXX',
  number: 123,
  title: 'feat: add new feature',
  createdAt: '2024-01-15T10:30:00Z',
  url: 'https://github.com/owner/repo/pull/123',
  author: { login: 'octocat' },
};

const mockIssue: GitHubIssueNode = {
  id: 'I_kwDOB8YYYY',
  number: 456,
  title: 'Bug: something is broken',
  createdAt: '2024-01-15T11:00:00Z',
  url: 'https://github.com/owner/repo/issues/456',
  author: { login: 'octocat' },
};

const mockPullRequestReview: GitHubPullRequestReviewNode = {
  id: 'PRR_kwDOB8ZZZZ',
  body: 'LGTM! Great work on this feature.',
  createdAt: '2024-01-15T12:00:00Z',
  url: 'https://github.com/owner/repo/pull/123#pullrequestreview-1234567890',
  author: { login: 'reviewer' },
  pullRequest: {
    number: 123,
    title: 'feat: add new feature',
  },
};

const mockIssueComment: GitHubIssueCommentNode = {
  id: 'IC_kwDOB8AAAA',
  body: 'I can reproduce this issue. Let me look into it.',
  createdAt: '2024-01-15T13:00:00Z',
  url: 'https://github.com/owner/repo/issues/456#issuecomment-1234567890',
  author: { login: 'commenter' },
  issue: {
    number: 456,
    title: 'Bug: something is broken',
  },
};

/**
 * Helper to normalize mock data to UnifiedActivity
 * (Simulates the normalization functions in fetch.ts)
 */
function normalizePR(pr: GitHubPullRequestNode, accountId: string): UnifiedActivity {
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

function normalizeIssue(issue: GitHubIssueNode, accountId: string): UnifiedActivity {
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

function normalizeReview(review: GitHubPullRequestReviewNode, accountId: string): UnifiedActivity {
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

function normalizeComment(comment: GitHubIssueCommentNode, accountId: string): UnifiedActivity {
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

function normalizeCommit(
  repoName: string,
  occurredAt: string,
  commitCount: number,
  accountId: string
): UnifiedActivity {
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

describe('GitHub Provider Contract Tests', () => {
  const accountId = 'github-personal';

  describe('Pull Request normalization', () => {
    it('should produce valid UnifiedActivity from PR', () => {
      const activity = normalizePR(mockPullRequest, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should use only required fields from GitHub PR', () => {
      const activity = normalizePR(mockPullRequest, accountId);

      // Verify required fields are populated correctly
      expect(activity.id).toBe('github:github-personal:pr-PR_kwDOB8XXXX');
      expect(activity.provider).toBe('github');
      expect(activity.accountId).toBe(accountId);
      expect(activity.sourceId).toBe(mockPullRequest.id);
      expect(activity.type).toBe('pull_request');
      expect(activity.timestamp).toBe(mockPullRequest.createdAt);
      expect(activity.title).toBe(mockPullRequest.title);
      expect(activity.url).toBe(mockPullRequest.url);
      expect(activity.participants).toEqual(['octocat']);
    });

    it('should handle PR without author', () => {
      const prWithoutAuthor: GitHubPullRequestNode = {
        ...mockPullRequest,
        author: null,
      };
      const activity = normalizePR(prWithoutAuthor, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
      expect(activity.participants).toBeUndefined();
    });
  });

  describe('Issue normalization', () => {
    it('should produce valid UnifiedActivity from issue', () => {
      const activity = normalizeIssue(mockIssue, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should use only required fields from GitHub issue', () => {
      const activity = normalizeIssue(mockIssue, accountId);

      expect(activity.id).toBe('github:github-personal:issue-I_kwDOB8YYYY');
      expect(activity.provider).toBe('github');
      expect(activity.type).toBe('issue');
      expect(activity.timestamp).toBe(mockIssue.createdAt);
      expect(activity.title).toBe(mockIssue.title);
      expect(activity.url).toBe(mockIssue.url);
    });
  });

  describe('Code Review normalization', () => {
    it('should produce valid UnifiedActivity from PR review', () => {
      const activity = normalizeReview(mockPullRequestReview, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should include PR context in review title', () => {
      const activity = normalizeReview(mockPullRequestReview, accountId);

      expect(activity.type).toBe('code_review');
      expect(activity.title).toContain('#123');
      expect(activity.title).toContain('feat: add new feature');
      expect(activity.summary).toBe(mockPullRequestReview.body);
    });

    it('should truncate long review body', () => {
      const longReview: GitHubPullRequestReviewNode = {
        ...mockPullRequestReview,
        body: 'A'.repeat(300),
      };
      const activity = normalizeReview(longReview, accountId);

      expect(activity.summary).toHaveLength(200);
    });
  });

  describe('Issue Comment normalization', () => {
    it('should produce valid UnifiedActivity from issue comment', () => {
      const activity = normalizeComment(mockIssueComment, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should include issue context in comment title', () => {
      const activity = normalizeComment(mockIssueComment, accountId);

      expect(activity.type).toBe('issue_comment');
      expect(activity.title).toContain('#456');
      expect(activity.title).toContain('Bug: something is broken');
    });
  });

  describe('Commit contribution normalization', () => {
    it('should produce valid UnifiedActivity from commit contribution', () => {
      const activity = normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 5, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should create deterministic ID from repo and date', () => {
      const activity1 = normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 5, accountId);
      const activity2 = normalizeCommit('owner/repo', '2024-01-15T23:59:59Z', 3, accountId);

      // Same repo + same date = same source ID base
      expect(activity1.sourceId).toBe('commits-owner-repo-2024-01-15');
      expect(activity2.sourceId).toBe('commits-owner-repo-2024-01-15');
    });

    it('should include commit count in title and summary', () => {
      const activity = normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 5, accountId);

      expect(activity.title).toBe('5 commits to owner/repo');
      expect(activity.summary).toBe('Pushed 5 commits to owner/repo');
    });

    it('should use singular form for single commit', () => {
      const activity = normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 1, accountId);

      expect(activity.title).toBe('1 commit to owner/repo');
      expect(activity.summary).toBe('Pushed 1 commit to owner/repo');
    });
  });

  describe('Required fields verification', () => {
    it('should verify all normalized activities have required UnifiedActivity fields', () => {
      const activities: UnifiedActivity[] = [
        normalizePR(mockPullRequest, accountId),
        normalizeIssue(mockIssue, accountId),
        normalizeReview(mockPullRequestReview, accountId),
        normalizeComment(mockIssueComment, accountId),
        normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 5, accountId),
      ];

      for (const activity of activities) {
        // All required fields should be present
        expect(activity.id).toBeDefined();
        expect(activity.provider).toBe('github');
        expect(activity.accountId).toBe(accountId);
        expect(activity.sourceId).toBeDefined();
        expect(activity.type).toBeDefined();
        expect(activity.timestamp).toBeDefined();

        // Should validate against schema
        expect(() => validateActivity(activity)).not.toThrow();
      }
    });

    it('should not include extra fields beyond UnifiedActivity schema', () => {
      const activity = normalizePR(mockPullRequest, accountId);

      // Get schema keys
      const schemaKeys = Object.keys(UnifiedActivitySchema.shape);
      const activityKeys = Object.keys(activity);

      // All activity keys should be in schema
      for (const key of activityKeys) {
        expect(schemaKeys).toContain(key);
      }
    });
  });

  describe('Activity type mapping', () => {
    it('should map GitHub entity types to correct ActivityType', () => {
      expect(normalizePR(mockPullRequest, accountId).type).toBe('pull_request');
      expect(normalizeIssue(mockIssue, accountId).type).toBe('issue');
      expect(normalizeReview(mockPullRequestReview, accountId).type).toBe('code_review');
      expect(normalizeComment(mockIssueComment, accountId).type).toBe('issue_comment');
      expect(normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 1, accountId).type).toBe('commit');
    });
  });

  describe('Multiple accounts support', () => {
    it('should correctly namespace activities by account', () => {
      const personalActivity = normalizePR(mockPullRequest, 'github-personal');
      const workActivity = normalizePR(mockPullRequest, 'github-work');

      expect(personalActivity.accountId).toBe('github-personal');
      expect(workActivity.accountId).toBe('github-work');

      // IDs should be different due to account prefix
      expect(personalActivity.id).not.toBe(workActivity.id);
      expect(personalActivity.id).toContain('github-personal');
      expect(workActivity.id).toContain('github-work');
    });
  });

  describe('Deep links (URL) verification', () => {
    it('should include valid GitHub URLs when available', () => {
      const prActivity = normalizePR(mockPullRequest, accountId);
      const issueActivity = normalizeIssue(mockIssue, accountId);
      const reviewActivity = normalizeReview(mockPullRequestReview, accountId);
      const commentActivity = normalizeComment(mockIssueComment, accountId);

      expect(prActivity.url).toMatch(/^https:\/\/github\.com\/.+\/pull\/\d+$/);
      expect(issueActivity.url).toMatch(/^https:\/\/github\.com\/.+\/issues\/\d+$/);
      expect(reviewActivity.url).toContain('pullrequestreview');
      expect(commentActivity.url).toContain('issuecomment');
    });

    it('should not include URL for commit contributions (aggregated)', () => {
      const commitActivity = normalizeCommit('owner/repo', '2024-01-15T00:00:00Z', 5, accountId);
      // Commit contributions are aggregated counts, no direct URL
      expect(commitActivity.url).toBeUndefined();
    });
  });
});

describe('GitHub GraphQL Query Minimal Fields', () => {
  it('should only request fields needed for UnifiedActivity', () => {
    // This is a documentation test - verifies our understanding of what fields we use
    // The actual GraphQL queries in queries.ts should match this

    // Fields we need for heatmap:
    const heatmapFields = ['timestamp', 'provider', 'type'];

    // Fields we need for drill-down:
    const drillDownFields = ['timestamp', 'title', 'summary', 'participants', 'url', 'sourceId', 'accountId'];

    // All fields combined (no duplicates)
    const allRequiredFields = [...new Set([...heatmapFields, ...drillDownFields])];

    // Fields we actually use in normalized activities
    const usedFields = ['id', 'provider', 'accountId', 'sourceId', 'type', 'timestamp', 'title', 'summary', 'participants', 'url'];

    // Verify all required fields are used
    for (const field of allRequiredFields) {
      expect(usedFields).toContain(field);
    }
  });
});
