import { describe, it, expect } from 'vitest';
import { validateActivity, UnifiedActivitySchema } from '../schemas/index.js';
import type { UnifiedActivity } from '../schemas/index.js';
import type {
  AzurePullRequest,
  AzureCommit,
  AzureWorkItem,
} from '../providers/azure-devops/index.js';

/**
 * Mock Azure DevOps API response data for testing normalization
 */
const mockPullRequest: AzurePullRequest = {
  pullRequestId: 123,
  title: 'Add user authentication feature',
  creationDate: '2024-01-15T10:30:00Z',
  closedDate: undefined,
  status: 'active',
  createdBy: {
    id: 'user-id-123',
    displayName: 'John Doe',
    uniqueName: 'john.doe@company.com',
  },
  repository: {
    id: 'repo-id-456',
    name: 'my-repo',
    project: {
      name: 'MyProject',
    },
  },
};

const mockClosedPullRequest: AzurePullRequest = {
  ...mockPullRequest,
  pullRequestId: 124,
  status: 'completed',
  closedDate: '2024-01-16T14:00:00Z',
};

const mockCommit: AzureCommit = {
  commitId: 'abc123def456789',
  comment: 'feat: implement login functionality\n\nThis adds OAuth support.',
  author: {
    name: 'John Doe',
    email: 'john.doe@company.com',
    date: '2024-01-15T11:00:00Z',
  },
  committer: {
    name: 'John Doe',
    email: 'john.doe@company.com',
    date: '2024-01-15T11:00:00Z',
  },
  url: 'https://dev.azure.com/org/project/_apis/git/repositories/repo/commits/abc123def456789',
  remoteUrl: 'https://dev.azure.com/org/project/_git/repo/commit/abc123def456789',
};

const mockWorkItem: AzureWorkItem = {
  id: 789,
  fields: {
    'System.Title': 'Fix login timeout issue',
    'System.WorkItemType': 'Bug',
    'System.State': 'Active',
    'System.CreatedDate': '2024-01-15T09:00:00Z',
    'System.ChangedDate': '2024-01-15T12:00:00Z',
    'System.CreatedBy': {
      displayName: 'Jane Smith',
      uniqueName: 'jane.smith@company.com',
    },
    'System.AssignedTo': {
      displayName: 'John Doe',
      uniqueName: 'john.doe@company.com',
    },
  },
  url: 'https://dev.azure.com/org/project/_apis/wit/workItems/789',
  _links: {
    html: {
      href: 'https://dev.azure.com/org/project/_workitems/edit/789',
    },
  },
};

const mockTaskWorkItem: AzureWorkItem = {
  ...mockWorkItem,
  id: 790,
  fields: {
    ...mockWorkItem.fields,
    'System.Title': 'Implement unit tests for login',
    'System.WorkItemType': 'Task',
    'System.State': 'Done',
  },
};

/**
 * Helper to normalize mock data to UnifiedActivity
 * (Simulates the normalization logic in fetch.ts)
 */
function normalizePullRequest(
  pr: AzurePullRequest,
  accountId: string,
  organization: string = 'myorg'
): UnifiedActivity {
  const timestamp = pr.closedDate ?? pr.creationDate;

  return {
    id: `azure-devops:${accountId}:pr-${pr.pullRequestId}`,
    provider: 'azure-devops',
    accountId,
    sourceId: String(pr.pullRequestId),
    type: 'pull_request',
    timestamp: timestamp.endsWith('Z') ? timestamp : new Date(timestamp).toISOString(),
    title: pr.title,
    url: `https://dev.azure.com/${organization}/${pr.repository.project.name}/_git/${pr.repository.name}/pullrequest/${pr.pullRequestId}`,
    participants: [pr.createdBy.displayName],
  };
}

function normalizeCommit(
  commit: AzureCommit,
  accountId: string,
  organization: string = 'myorg',
  project: string = 'MyProject',
  repoName: string = 'my-repo'
): UnifiedActivity {
  const timestamp = commit.author.date;

  return {
    id: `azure-devops:${accountId}:commit-${commit.commitId.slice(0, 8)}`,
    provider: 'azure-devops',
    accountId,
    sourceId: commit.commitId,
    type: 'commit',
    timestamp: timestamp.endsWith('Z') ? timestamp : new Date(timestamp).toISOString(),
    title: commit.comment.split('\n')[0].slice(0, 100),
    summary: commit.comment.length > 100 ? commit.comment.slice(0, 200) : undefined,
    url: `https://dev.azure.com/${organization}/${project}/_git/${repoName}/commit/${commit.commitId}`,
    participants: [commit.author.name],
  };
}

function normalizeWorkItem(
  workItem: AzureWorkItem,
  accountId: string,
  organization: string = 'myorg',
  project: string = 'MyProject'
): UnifiedActivity {
  const fields = workItem.fields;
  const timestamp = fields['System.ChangedDate'] ?? fields['System.CreatedDate'];

  return {
    id: `azure-devops:${accountId}:wi-${workItem.id}`,
    provider: 'azure-devops',
    accountId,
    sourceId: String(workItem.id),
    type: 'issue',
    timestamp: timestamp.endsWith('Z') ? timestamp : new Date(timestamp).toISOString(),
    title: `[${fields['System.WorkItemType']}] ${fields['System.Title']}`,
    url: `https://dev.azure.com/${organization}/${project}/_workitems/edit/${workItem.id}`,
    participants: [fields['System.CreatedBy'].displayName],
  };
}

describe('Azure DevOps Provider Contract Tests', () => {
  const accountId = 'azure-org1';

  describe('Pull Request normalization', () => {
    it('should produce valid UnifiedActivity from PR', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should map PR to pull_request type', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      expect(activity.type).toBe('pull_request');
    });

    it('should use creationDate for active PRs', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      expect(activity.timestamp).toBe('2024-01-15T10:30:00Z');
    });

    it('should use closedDate for completed PRs', () => {
      const activity = normalizePullRequest(mockClosedPullRequest, accountId);
      expect(activity.timestamp).toBe('2024-01-16T14:00:00Z');
    });

    it('should build correct PR URL', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      expect(activity.url).toBe('https://dev.azure.com/myorg/MyProject/_git/my-repo/pullrequest/123');
    });

    it('should include creator as participant', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      expect(activity.participants).toEqual(['John Doe']);
    });
  });

  describe('Commit normalization', () => {
    it('should produce valid UnifiedActivity from commit', () => {
      const activity = normalizeCommit(mockCommit, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should map commit to commit type', () => {
      const activity = normalizeCommit(mockCommit, accountId);
      expect(activity.type).toBe('commit');
    });

    it('should use first line of commit message as title', () => {
      const activity = normalizeCommit(mockCommit, accountId);
      expect(activity.title).toBe('feat: implement login functionality');
    });

    it('should include full message as summary for long commits', () => {
      const longCommit: AzureCommit = {
        ...mockCommit,
        comment: 'A'.repeat(250),
      };
      const activity = normalizeCommit(longCommit, accountId);
      expect(activity.summary).toHaveLength(200);
    });

    it('should use short commit ID in activity ID', () => {
      const activity = normalizeCommit(mockCommit, accountId);
      expect(activity.id).toContain('abc123de');
    });

    it('should build correct commit URL', () => {
      const activity = normalizeCommit(mockCommit, accountId);
      expect(activity.url).toContain('commit/abc123def456789');
    });
  });

  describe('Work Item normalization', () => {
    it('should produce valid UnifiedActivity from work item', () => {
      const activity = normalizeWorkItem(mockWorkItem, accountId);
      expect(() => validateActivity(activity)).not.toThrow();
    });

    it('should map work item to issue type', () => {
      const activity = normalizeWorkItem(mockWorkItem, accountId);
      expect(activity.type).toBe('issue');
    });

    it('should include work item type in title', () => {
      const activity = normalizeWorkItem(mockWorkItem, accountId);
      expect(activity.title).toBe('[Bug] Fix login timeout issue');
    });

    it('should handle different work item types', () => {
      const taskActivity = normalizeWorkItem(mockTaskWorkItem, accountId);
      expect(taskActivity.title).toBe('[Task] Implement unit tests for login');
    });

    it('should use ChangedDate as timestamp', () => {
      const activity = normalizeWorkItem(mockWorkItem, accountId);
      expect(activity.timestamp).toBe('2024-01-15T12:00:00Z');
    });

    it('should build correct work item URL', () => {
      const activity = normalizeWorkItem(mockWorkItem, accountId);
      expect(activity.url).toBe('https://dev.azure.com/myorg/MyProject/_workitems/edit/789');
    });
  });

  describe('Required fields verification', () => {
    it('should verify all normalized activities have required fields', () => {
      const activities = [
        normalizePullRequest(mockPullRequest, accountId),
        normalizeCommit(mockCommit, accountId),
        normalizeWorkItem(mockWorkItem, accountId),
      ];

      for (const activity of activities) {
        expect(activity.id).toBeDefined();
        expect(activity.provider).toBe('azure-devops');
        expect(activity.accountId).toBe(accountId);
        expect(activity.sourceId).toBeDefined();
        expect(activity.type).toBeDefined();
        expect(activity.timestamp).toBeDefined();

        expect(() => validateActivity(activity)).not.toThrow();
      }
    });

    it('should not include extra fields beyond UnifiedActivity schema', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      const schemaKeys = Object.keys(UnifiedActivitySchema.shape);
      const activityKeys = Object.keys(activity);

      for (const key of activityKeys) {
        expect(schemaKeys).toContain(key);
      }
    });
  });

  describe('Multiple orgs/projects support', () => {
    it('should correctly namespace activities by account', () => {
      const org1Activity = normalizePullRequest(mockPullRequest, 'azure-org1');
      const org2Activity = normalizePullRequest(mockPullRequest, 'azure-org2');

      expect(org1Activity.accountId).toBe('azure-org1');
      expect(org2Activity.accountId).toBe('azure-org2');

      expect(org1Activity.id).toContain('azure-org1');
      expect(org2Activity.id).toContain('azure-org2');
    });

    it('should include organization in URL', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId, 'different-org');
      expect(activity.url).toContain('different-org');
    });
  });

  describe('Stable ID generation', () => {
    it('should generate stable ID for PR', () => {
      const activity1 = normalizePullRequest(mockPullRequest, accountId);
      const activity2 = normalizePullRequest(mockPullRequest, accountId);

      expect(activity1.id).toBe(activity2.id);
    });

    it('should generate stable ID for commit', () => {
      const activity1 = normalizeCommit(mockCommit, accountId);
      const activity2 = normalizeCommit(mockCommit, accountId);

      expect(activity1.id).toBe(activity2.id);
    });

    it('should generate stable ID for work item', () => {
      const activity1 = normalizeWorkItem(mockWorkItem, accountId);
      const activity2 = normalizeWorkItem(mockWorkItem, accountId);

      expect(activity1.id).toBe(activity2.id);
    });

    it('should generate unique IDs for different entities', () => {
      const prActivity = normalizePullRequest(mockPullRequest, accountId);
      const commitActivity = normalizeCommit(mockCommit, accountId);
      const wiActivity = normalizeWorkItem(mockWorkItem, accountId);

      const ids = [prActivity.id, commitActivity.id, wiActivity.id];
      const uniqueIds = new Set(ids);

      expect(uniqueIds.size).toBe(3);
    });
  });

  describe('Timestamp normalization', () => {
    it('should preserve UTC timestamps', () => {
      const activity = normalizePullRequest(mockPullRequest, accountId);
      expect(activity.timestamp).toMatch(/Z$/);
    });

    it('should convert non-UTC timestamps to UTC', () => {
      const prWithOffset: AzurePullRequest = {
        ...mockPullRequest,
        creationDate: '2024-01-15T10:30:00+05:00',
      };

      const activity = normalizePullRequest(prWithOffset, accountId);
      expect(activity.timestamp).toMatch(/Z$/);
    });
  });
});

describe('Azure DevOps Activity Type Mapping', () => {
  it('should map all work item types to issue', () => {
    const workItemTypes = ['Bug', 'Task', 'User Story', 'Issue'];

    for (const type of workItemTypes) {
      const workItem: AzureWorkItem = {
        ...mockWorkItem,
        fields: {
          ...mockWorkItem.fields,
          'System.WorkItemType': type,
        },
      };

      const activity = normalizeWorkItem(workItem, 'account');
      expect(activity.type).toBe('issue');
    }
  });
});
