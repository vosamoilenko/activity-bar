import { describe, it, expect } from 'vitest';
import {
  normalizeToUTC,
  generateActivityId,
  truncateText,
  extractFirstLine,
  deduplicateStrings,
  extractDateFromTimestamp,
  GITHUB_TYPE_MAPPINGS,
  GITLAB_TYPE_MAPPINGS,
  AZURE_DEVOPS_TYPE_MAPPINGS,
  GOOGLE_CALENDAR_TYPE_MAPPINGS,
  getProviderTypeMappings,
  getSourceTypesForActivityType,
  mapSourceToActivityType,
  PROVIDER_TYPE_MAPPINGS,
} from '../normalizers/index.js';
import type { ActivityType } from '../schemas/index.js';

describe('Normalization Utility Functions', () => {
  describe('normalizeToUTC', () => {
    it('should pass through already UTC timestamps', () => {
      expect(normalizeToUTC('2024-01-15T10:30:00Z')).toBe('2024-01-15T10:30:00Z');
      expect(normalizeToUTC('2024-01-15T10:30:00.123Z')).toBe('2024-01-15T10:30:00.123Z');
    });

    it('should convert timezone offset to UTC', () => {
      // -08:00 means 8 hours behind UTC
      const result = normalizeToUTC('2024-01-15T10:00:00-08:00');
      expect(result).toMatch(/Z$/);
      expect(result).toBe('2024-01-15T18:00:00.000Z');
    });

    it('should handle date-only input with noon UTC', () => {
      expect(normalizeToUTC('2024-01-15')).toBe('2024-01-15T12:00:00Z');
    });

    it('should handle various timestamp formats', () => {
      // With positive offset
      const positive = normalizeToUTC('2024-01-15T10:00:00+05:00');
      expect(positive).toMatch(/Z$/);
      expect(positive).toBe('2024-01-15T05:00:00.000Z');
    });

    it('should return current time for invalid input', () => {
      const result = normalizeToUTC('invalid-timestamp');
      expect(result).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/);
    });
  });

  describe('generateActivityId', () => {
    it('should generate correct ID format', () => {
      expect(generateActivityId('github', 'personal', 'pr', '123')).toBe(
        'github:personal:pr-123'
      );
    });

    it('should handle hyphenated provider names', () => {
      expect(generateActivityId('azure-devops', 'org1', 'commit', 'abc')).toBe(
        'azure-devops:org1:commit-abc'
      );
    });

    it('should handle complex source IDs', () => {
      expect(generateActivityId('google-calendar', 'personal', 'event', 'abc123_def456')).toBe(
        'google-calendar:personal:event-abc123_def456'
      );
    });
  });

  describe('truncateText', () => {
    it('should return undefined for null/undefined/empty', () => {
      expect(truncateText(null)).toBeUndefined();
      expect(truncateText(undefined)).toBeUndefined();
      expect(truncateText('')).toBeUndefined();
      expect(truncateText('   ')).toBeUndefined();
    });

    it('should pass through short text', () => {
      expect(truncateText('Short text')).toBe('Short text');
    });

    it('should truncate long text to default 200 chars', () => {
      const longText = 'A'.repeat(300);
      expect(truncateText(longText)).toHaveLength(200);
    });

    it('should truncate to custom length', () => {
      const longText = 'A'.repeat(100);
      expect(truncateText(longText, 50)).toHaveLength(50);
    });
  });

  describe('extractFirstLine', () => {
    it('should return undefined for empty input', () => {
      expect(extractFirstLine(null)).toBeUndefined();
      expect(extractFirstLine('')).toBeUndefined();
    });

    it('should extract first line from multiline text', () => {
      expect(extractFirstLine('First line\nSecond line\nThird line')).toBe('First line');
    });

    it('should truncate long first line', () => {
      const longLine = 'A'.repeat(150);
      expect(extractFirstLine(longLine)).toHaveLength(100);
    });

    it('should truncate to custom length', () => {
      expect(extractFirstLine('A'.repeat(100), 50)).toHaveLength(50);
    });
  });

  describe('deduplicateStrings', () => {
    it('should remove duplicates', () => {
      expect(deduplicateStrings(['a', 'b', 'a', 'c', 'b'])).toEqual(['a', 'b', 'c']);
    });

    it('should preserve order', () => {
      expect(deduplicateStrings(['c', 'a', 'b', 'a'])).toEqual(['c', 'a', 'b']);
    });

    it('should handle empty array', () => {
      expect(deduplicateStrings([])).toEqual([]);
    });
  });

  describe('extractDateFromTimestamp', () => {
    it('should extract YYYY-MM-DD from timestamp', () => {
      expect(extractDateFromTimestamp('2024-01-15T10:30:00Z')).toBe('2024-01-15');
      expect(extractDateFromTimestamp('2024-01-15T10:30:00.123Z')).toBe('2024-01-15');
    });
  });
});

describe('Type Mapping Tables', () => {
  describe('GitHub mappings', () => {
    it('should have mappings for all GitHub activity types', () => {
      const targets = GITHUB_TYPE_MAPPINGS.map((m) => m.target);

      expect(targets).toContain('commit');
      expect(targets).toContain('pull_request');
      expect(targets).toContain('issue');
      expect(targets).toContain('issue_comment');
      expect(targets).toContain('code_review');
    });

    it('should have source types for each mapping', () => {
      for (const mapping of GITHUB_TYPE_MAPPINGS) {
        expect(mapping.source).toBeTruthy();
        expect(mapping.target).toBeTruthy();
      }
    });
  });

  describe('GitLab mappings', () => {
    it('should have mappings for all GitLab activity types', () => {
      const targets = GITLAB_TYPE_MAPPINGS.map((m) => m.target);

      expect(targets).toContain('commit');
      expect(targets).toContain('pull_request');
      expect(targets).toContain('issue');
      expect(targets).toContain('issue_comment');
      expect(targets).toContain('pull_request_comment');
      expect(targets).toContain('code_review');
    });

    it('should map MR actions correctly', () => {
      const mrMappings = GITLAB_TYPE_MAPPINGS.filter((m) => m.source.includes('MergeRequest'));

      expect(mrMappings.some((m) => m.source === 'created:MergeRequest' && m.target === 'pull_request')).toBe(true);
      expect(mrMappings.some((m) => m.source === 'merged:MergeRequest' && m.target === 'pull_request')).toBe(true);
      expect(mrMappings.some((m) => m.source === 'approved:MergeRequest' && m.target === 'code_review')).toBe(true);
    });
  });

  describe('Azure DevOps mappings', () => {
    it('should have mappings for all Azure DevOps activity types', () => {
      const targets = AZURE_DEVOPS_TYPE_MAPPINGS.map((m) => m.target);

      expect(targets).toContain('commit');
      expect(targets).toContain('pull_request');
      expect(targets).toContain('issue');
    });

    it('should map work item types to issue', () => {
      const workItemMappings = AZURE_DEVOPS_TYPE_MAPPINGS.filter((m) => m.source.startsWith('workItem:'));

      for (const mapping of workItemMappings) {
        expect(mapping.target).toBe('issue');
      }
    });
  });

  describe('Google Calendar mappings', () => {
    it('should map all event types to meeting', () => {
      for (const mapping of GOOGLE_CALENDAR_TYPE_MAPPINGS) {
        expect(mapping.target).toBe('meeting');
      }
    });
  });

  describe('All provider mappings', () => {
    it('should cover all 4 providers', () => {
      const providers = PROVIDER_TYPE_MAPPINGS.map((m) => m.provider);

      expect(providers).toContain('github');
      expect(providers).toContain('gitlab');
      expect(providers).toContain('azure-devops');
      expect(providers).toContain('google-calendar');
      expect(providers).toHaveLength(4);
    });
  });
});

describe('Mapping Helper Functions', () => {
  describe('getProviderTypeMappings', () => {
    it('should return mappings for valid provider', () => {
      expect(getProviderTypeMappings('github')).toBe(GITHUB_TYPE_MAPPINGS);
      expect(getProviderTypeMappings('gitlab')).toBe(GITLAB_TYPE_MAPPINGS);
      expect(getProviderTypeMappings('azure-devops')).toBe(AZURE_DEVOPS_TYPE_MAPPINGS);
      expect(getProviderTypeMappings('google-calendar')).toBe(GOOGLE_CALENDAR_TYPE_MAPPINGS);
    });
  });

  describe('getSourceTypesForActivityType', () => {
    it('should return source types for GitHub commit', () => {
      const sources = getSourceTypesForActivityType('github', 'commit');
      expect(sources).toContain('commit');
    });

    it('should return source types for GitLab pull_request', () => {
      const sources = getSourceTypesForActivityType('gitlab', 'pull_request');
      expect(sources).toContain('created:MergeRequest');
      expect(sources).toContain('merged:MergeRequest');
    });

    it('should return empty array for unmapped type', () => {
      const sources = getSourceTypesForActivityType('github', 'pipeline');
      expect(sources).toEqual([]);
    });
  });

  describe('mapSourceToActivityType', () => {
    it('should map GitHub source types', () => {
      expect(mapSourceToActivityType('github', 'commit')).toBe('commit');
      expect(mapSourceToActivityType('github', 'pullRequest')).toBe('pull_request');
      expect(mapSourceToActivityType('github', 'pullRequestReview')).toBe('code_review');
    });

    it('should map GitLab source types', () => {
      expect(mapSourceToActivityType('gitlab', 'pushed')).toBe('commit');
      expect(mapSourceToActivityType('gitlab', 'created:MergeRequest')).toBe('pull_request');
      expect(mapSourceToActivityType('gitlab', 'approved:MergeRequest')).toBe('code_review');
    });

    it('should return null for unknown source type', () => {
      expect(mapSourceToActivityType('github', 'unknown')).toBeNull();
    });
  });
});

describe('Normalization Integration', () => {
  describe('Representative inputs for each provider', () => {
    it('should handle GitHub commit contribution', () => {
      // Simulate normalized output from GitHub
      const raw = {
        commitCount: 5,
        occurredAt: '2024-01-15T00:00:00Z',
        repository: 'owner/repo',
      };

      const timestamp = normalizeToUTC(raw.occurredAt);
      const id = generateActivityId('github', 'personal', 'commits', `${raw.repository}-2024-01-15`);

      expect(timestamp).toBe('2024-01-15T00:00:00Z');
      expect(id).toBe('github:personal:commits-owner/repo-2024-01-15');
    });

    it('should handle GitLab push event', () => {
      const raw = {
        id: 12345,
        action_name: 'pushed',
        created_at: '2024-01-15T10:30:00+02:00',
        push_data: { commit_count: 3, ref: 'main' },
      };

      const timestamp = normalizeToUTC(raw.created_at);
      const id = generateActivityId('gitlab', 'work', 'event', String(raw.id));

      expect(timestamp).toBe('2024-01-15T08:30:00.000Z');
      expect(id).toBe('gitlab:work:event-12345');
    });

    it('should handle Azure DevOps work item', () => {
      const raw = {
        id: 789,
        fields: {
          'System.Title': 'Fix login bug',
          'System.WorkItemType': 'Bug',
          'System.ChangedDate': '2024-01-15T12:00:00.000Z',
        },
      };

      const timestamp = normalizeToUTC(raw.fields['System.ChangedDate']);
      const id = generateActivityId('azure-devops', 'org1', 'wi', String(raw.id));
      const title = `[${raw.fields['System.WorkItemType']}] ${raw.fields['System.Title']}`;

      expect(timestamp).toBe('2024-01-15T12:00:00.000Z');
      expect(id).toBe('azure-devops:org1:wi-789');
      expect(title).toBe('[Bug] Fix login bug');
    });

    it('should handle Google Calendar all-day event', () => {
      const raw = {
        id: 'event123',
        summary: 'Company All-Hands',
        start: { date: '2024-01-20' },
      };

      const timestamp = normalizeToUTC(raw.start.date!);
      const id = generateActivityId('google-calendar', 'personal', 'primary', raw.id);

      expect(timestamp).toBe('2024-01-20T12:00:00Z');
      expect(id).toBe('google-calendar:personal:primary-event123');
    });

    it('should handle Google Calendar timed event', () => {
      const raw = {
        id: 'event456',
        summary: 'Team Standup',
        start: { dateTime: '2024-01-15T09:00:00-08:00' },
        attendees: [
          { email: 'alice@example.com', self: false },
          { email: 'self@example.com', self: true },
        ],
      };

      const timestamp = normalizeToUTC(raw.start.dateTime!);
      const participants = deduplicateStrings(
        raw.attendees.filter((a) => !a.self).map((a) => a.email)
      );

      expect(timestamp).toBe('2024-01-15T17:00:00.000Z');
      expect(participants).toEqual(['alice@example.com']);
    });
  });

  describe('UTC timestamp enforcement', () => {
    it('should always produce Z-suffix timestamps', () => {
      const testCases = [
        '2024-01-15T10:00:00Z',
        '2024-01-15T10:00:00-08:00',
        '2024-01-15T10:00:00+05:30',
        '2024-01-15',
        '2024-01-15T10:00:00.123Z',
      ];

      for (const input of testCases) {
        const result = normalizeToUTC(input);
        expect(result).toMatch(/Z$/);
      }
    });
  });
});
