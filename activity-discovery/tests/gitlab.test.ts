import { describe, it, expect } from 'vitest';
import { validateActivity, UnifiedActivitySchema } from '../schemas/index.js';
import type { UnifiedActivity, ActivityType } from '../schemas/index.js';
import type { GitLabEvent } from '../providers/gitlab/index.js';
import { EVENT_TYPE_MAPPING } from '../providers/gitlab/index.js';

/**
 * Mock GitLab API response data for testing normalization
 */
const mockPushEvent: GitLabEvent = {
  id: 12345,
  action_name: 'pushed',
  created_at: '2024-01-15T10:30:00.000Z',
  target_id: null,
  target_iid: null,
  target_type: null,
  target_title: null,
  author_id: 1,
  author_username: 'gitlab_user',
  project_id: 100,
  push_data: {
    commit_count: 3,
    action: 'pushed',
    ref_type: 'branch',
    commit_from: 'abc123',
    commit_to: 'def456',
    ref: 'main',
    commit_title: 'feat: add new feature',
  },
};

const mockMergeRequestEvent: GitLabEvent = {
  id: 12346,
  action_name: 'created',
  created_at: '2024-01-15T11:00:00.000Z',
  target_id: 200,
  target_iid: 42,
  target_type: 'MergeRequest',
  target_title: 'Add user authentication',
  author_id: 1,
  author_username: 'gitlab_user',
  project_id: 100,
};

const mockIssueEvent: GitLabEvent = {
  id: 12347,
  action_name: 'created',
  created_at: '2024-01-15T12:00:00.000Z',
  target_id: 300,
  target_iid: 99,
  target_type: 'Issue',
  target_title: 'Bug: Login not working',
  author_id: 1,
  author_username: 'gitlab_user',
  project_id: 100,
};

const mockCommentEvent: GitLabEvent = {
  id: 12348,
  action_name: 'commented',
  created_at: '2024-01-15T13:00:00.000Z',
  target_id: null,
  target_iid: null,
  target_type: null,
  target_title: null,
  author_id: 1,
  author_username: 'gitlab_user',
  project_id: 100,
  note: {
    id: 500,
    body: 'This looks good to me! Nice work on the implementation.',
    noteable_type: 'MergeRequest',
    noteable_id: 200,
    noteable_iid: 42,
  },
};

const mockIssueCommentEvent: GitLabEvent = {
  id: 12349,
  action_name: 'commented',
  created_at: '2024-01-15T14:00:00.000Z',
  target_id: null,
  target_iid: null,
  target_type: null,
  target_title: null,
  author_id: 1,
  author_username: 'gitlab_user',
  project_id: 100,
  note: {
    id: 501,
    body: 'I can reproduce this issue on my machine.',
    noteable_type: 'Issue',
    noteable_id: 300,
    noteable_iid: 99,
  },
};

const mockApprovedEvent: GitLabEvent = {
  id: 12350,
  action_name: 'approved',
  created_at: '2024-01-15T15:00:00.000Z',
  target_id: 200,
  target_iid: 42,
  target_type: 'MergeRequest',
  target_title: 'Add user authentication',
  author_id: 1,
  author_username: 'gitlab_user',
  project_id: 100,
};

/**
 * Helper to normalize mock data to UnifiedActivity
 * (Simulates the normalization logic in fetch.ts)
 */
function normalizeEvent(
  event: GitLabEvent,
  accountId: string,
  baseUrl: string = 'https://gitlab.com',
  projectPath: string = 'owner/repo'
): UnifiedActivity | null {
  // Map event to activity type
  let activityType: ActivityType | null = null;

  if (event.action_name === 'pushed' && event.push_data) {
    activityType = 'commit';
  } else if (event.action_name === 'commented') {
    if (event.note?.noteable_type === 'MergeRequest') {
      activityType = 'pull_request_comment';
    } else {
      activityType = 'issue_comment';
    }
  } else if (event.action_name === 'approved' && event.target_type === 'MergeRequest') {
    activityType = 'code_review';
  } else if (event.target_type === 'MergeRequest') {
    activityType = 'pull_request';
  } else if (event.target_type === 'Issue') {
    activityType = 'issue';
  }

  if (!activityType) {
    return null;
  }

  // Build URL
  let url: string | undefined;
  const base = `${baseUrl}/${projectPath}`;

  if (event.target_type === 'MergeRequest' && event.target_iid) {
    url = `${base}/-/merge_requests/${event.target_iid}`;
  } else if (event.target_type === 'Issue' && event.target_iid) {
    url = `${base}/-/issues/${event.target_iid}`;
  } else if (event.action_name === 'pushed' && event.push_data?.commit_to) {
    url = `${base}/-/commit/${event.push_data.commit_to}`;
  } else if (event.note && event.note.noteable_iid) {
    if (event.note.noteable_type === 'MergeRequest') {
      url = `${base}/-/merge_requests/${event.note.noteable_iid}#note_${event.note.id}`;
    } else if (event.note.noteable_type === 'Issue') {
      url = `${base}/-/issues/${event.note.noteable_iid}#note_${event.note.id}`;
    }
  }

  // Build title
  let title: string;
  let summary: string | undefined;

  if (event.action_name === 'pushed' && event.push_data) {
    const count = event.push_data.commit_count;
    title = `${count} commit${count > 1 ? 's' : ''} to ${event.push_data.ref}`;
    summary = event.push_data.commit_title || undefined;
  } else if (event.note) {
    title = `Comment on ${event.note.noteable_type} #${event.note.noteable_iid ?? event.note.noteable_id}`;
    summary = event.note.body?.slice(0, 200) || undefined;
  } else {
    title = event.target_title ?? `${event.action_name} ${event.target_type ?? 'item'}`;
  }

  const timestamp = event.created_at.endsWith('Z')
    ? event.created_at
    : new Date(event.created_at).toISOString();

  return {
    id: `gitlab:${accountId}:event-${event.id}`,
    provider: 'gitlab',
    accountId,
    sourceId: String(event.id),
    type: activityType,
    timestamp,
    title,
    summary,
    url,
    participants: [event.author_username],
  };
}

describe('GitLab Provider Contract Tests', () => {
  const accountId = 'gitlab-cloud';

  describe('Push event normalization', () => {
    it('should produce valid UnifiedActivity from push event', () => {
      const activity = normalizeEvent(mockPushEvent, accountId);
      expect(activity).not.toBeNull();
      expect(() => validateActivity(activity!)).not.toThrow();
    });

    it('should map push event to commit type', () => {
      const activity = normalizeEvent(mockPushEvent, accountId);
      expect(activity?.type).toBe('commit');
    });

    it('should include commit count in title', () => {
      const activity = normalizeEvent(mockPushEvent, accountId);
      expect(activity?.title).toBe('3 commits to main');
    });

    it('should include commit title as summary', () => {
      const activity = normalizeEvent(mockPushEvent, accountId);
      expect(activity?.summary).toBe('feat: add new feature');
    });

    it('should include author as participant', () => {
      const activity = normalizeEvent(mockPushEvent, accountId);
      expect(activity?.participants).toEqual(['gitlab_user']);
    });
  });

  describe('Merge Request event normalization', () => {
    it('should produce valid UnifiedActivity from MR event', () => {
      const activity = normalizeEvent(mockMergeRequestEvent, accountId);
      expect(activity).not.toBeNull();
      expect(() => validateActivity(activity!)).not.toThrow();
    });

    it('should map MR event to pull_request type', () => {
      const activity = normalizeEvent(mockMergeRequestEvent, accountId);
      expect(activity?.type).toBe('pull_request');
    });

    it('should use target_title for MR title', () => {
      const activity = normalizeEvent(mockMergeRequestEvent, accountId);
      expect(activity?.title).toBe('Add user authentication');
    });

    it('should include MR URL', () => {
      const activity = normalizeEvent(mockMergeRequestEvent, accountId);
      expect(activity?.url).toContain('merge_requests/42');
    });
  });

  describe('Issue event normalization', () => {
    it('should produce valid UnifiedActivity from issue event', () => {
      const activity = normalizeEvent(mockIssueEvent, accountId);
      expect(activity).not.toBeNull();
      expect(() => validateActivity(activity!)).not.toThrow();
    });

    it('should map issue event to issue type', () => {
      const activity = normalizeEvent(mockIssueEvent, accountId);
      expect(activity?.type).toBe('issue');
    });

    it('should include issue URL', () => {
      const activity = normalizeEvent(mockIssueEvent, accountId);
      expect(activity?.url).toContain('issues/99');
    });
  });

  describe('Comment event normalization', () => {
    it('should map MR comment to pull_request_comment type', () => {
      const activity = normalizeEvent(mockCommentEvent, accountId);
      expect(activity?.type).toBe('pull_request_comment');
    });

    it('should map issue comment to issue_comment type', () => {
      const activity = normalizeEvent(mockIssueCommentEvent, accountId);
      expect(activity?.type).toBe('issue_comment');
    });

    it('should include comment body as summary', () => {
      const activity = normalizeEvent(mockCommentEvent, accountId);
      expect(activity?.summary).toContain('This looks good to me!');
    });

    it('should include note anchor in URL', () => {
      const activity = normalizeEvent(mockCommentEvent, accountId);
      expect(activity?.url).toContain('#note_500');
    });
  });

  describe('Code review (approval) normalization', () => {
    it('should map approval to code_review type', () => {
      const activity = normalizeEvent(mockApprovedEvent, accountId);
      expect(activity?.type).toBe('code_review');
    });

    it('should produce valid UnifiedActivity from approval', () => {
      const activity = normalizeEvent(mockApprovedEvent, accountId);
      expect(activity).not.toBeNull();
      expect(() => validateActivity(activity!)).not.toThrow();
    });
  });

  describe('Required fields verification', () => {
    it('should verify all normalized activities have required fields', () => {
      const events = [
        mockPushEvent,
        mockMergeRequestEvent,
        mockIssueEvent,
        mockCommentEvent,
        mockApprovedEvent,
      ];

      for (const event of events) {
        const activity = normalizeEvent(event, accountId);
        expect(activity).not.toBeNull();

        expect(activity!.id).toBeDefined();
        expect(activity!.provider).toBe('gitlab');
        expect(activity!.accountId).toBe(accountId);
        expect(activity!.sourceId).toBeDefined();
        expect(activity!.type).toBeDefined();
        expect(activity!.timestamp).toBeDefined();

        expect(() => validateActivity(activity!)).not.toThrow();
      }
    });

    it('should not include extra fields beyond UnifiedActivity schema', () => {
      const activity = normalizeEvent(mockMergeRequestEvent, accountId);
      const schemaKeys = Object.keys(UnifiedActivitySchema.shape);
      const activityKeys = Object.keys(activity!);

      for (const key of activityKeys) {
        expect(schemaKeys).toContain(key);
      }
    });
  });

  describe('Self-hosted GitLab support', () => {
    it('should use custom baseURL for self-hosted instances', () => {
      const selfHostedUrl = 'https://gitlab.mycompany.com';
      const activity = normalizeEvent(mockMergeRequestEvent, 'gitlab-self-hosted', selfHostedUrl);

      expect(activity?.url).toContain(selfHostedUrl);
    });
  });

  describe('Multiple accounts support', () => {
    it('should correctly namespace activities by account', () => {
      const cloudActivity = normalizeEvent(mockPushEvent, 'gitlab-cloud');
      const selfHostedActivity = normalizeEvent(mockPushEvent, 'gitlab-self-hosted');

      expect(cloudActivity?.accountId).toBe('gitlab-cloud');
      expect(selfHostedActivity?.accountId).toBe('gitlab-self-hosted');

      expect(cloudActivity?.id).toContain('gitlab-cloud');
      expect(selfHostedActivity?.id).toContain('gitlab-self-hosted');
    });
  });

  describe('Timestamp normalization', () => {
    it('should convert non-UTC timestamps to UTC', () => {
      const eventWithoutZ: GitLabEvent = {
        ...mockPushEvent,
        created_at: '2024-01-15T10:30:00.000+00:00',
      };

      const activity = normalizeEvent(eventWithoutZ, accountId);
      expect(activity?.timestamp).toMatch(/Z$/);
    });

    it('should preserve already UTC timestamps', () => {
      const activity = normalizeEvent(mockPushEvent, accountId);
      expect(activity?.timestamp).toBe('2024-01-15T10:30:00.000Z');
    });
  });
});

describe('GitLab Event Type Mapping', () => {
  it('should have mappings for all required activity types', () => {
    const mappedTypes = Object.values(EVENT_TYPE_MAPPING);

    expect(mappedTypes).toContain('commit');
    expect(mappedTypes).toContain('pull_request');
    expect(mappedTypes).toContain('issue');
    expect(mappedTypes).toContain('issue_comment');
    expect(mappedTypes).toContain('code_review');
  });

  it('should map MR actions to pull_request', () => {
    expect(EVENT_TYPE_MAPPING['created:MergeRequest']).toBe('pull_request');
    expect(EVENT_TYPE_MAPPING['merged:MergeRequest']).toBe('pull_request');
    expect(EVENT_TYPE_MAPPING['closed:MergeRequest']).toBe('pull_request');
  });

  it('should map approval to code_review', () => {
    expect(EVENT_TYPE_MAPPING['approved:MergeRequest']).toBe('code_review');
  });

  it('should map push to commit', () => {
    expect(EVENT_TYPE_MAPPING['pushed:']).toBe('commit');
  });
});
