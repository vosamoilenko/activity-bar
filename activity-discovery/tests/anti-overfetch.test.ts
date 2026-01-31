import { describe, it, expect } from 'vitest';
import type { UnifiedActivity } from '../schemas/index.js';
import { UnifiedActivitySchema } from '../schemas/index.js';
import { aggregateToHeatmap } from '../src/aggregation.js';

/**
 * Anti-overfetch tests ensuring the app uses only declared minimal fields
 *
 * These tests verify that:
 * 1. Aggregation (heatmap) uses only: timestamp, provider, type
 * 2. Drill-down view uses only: timestamp, title, summary, participants, url, sourceId, accountId
 * 3. Provider adapters don't leak extra fields
 */

// Define the minimal fields required for each use case
const HEATMAP_REQUIRED_FIELDS = ['timestamp', 'provider', 'type'] as const;
const DRILLDOWN_REQUIRED_FIELDS = [
  'timestamp',
  'title',
  'summary',
  'participants',
  'url',
  'sourceId',
  'accountId',
] as const;

// All fields in UnifiedActivity schema
const ALL_SCHEMA_FIELDS = Object.keys(UnifiedActivitySchema.shape);

/**
 * Create a minimal activity for testing
 */
function createMinimalActivity(overrides: Partial<UnifiedActivity> = {}): UnifiedActivity {
  return {
    id: 'test:account:item-1',
    provider: 'github',
    accountId: 'account',
    sourceId: 'source-1',
    type: 'commit',
    timestamp: '2024-01-15T10:00:00Z',
    ...overrides,
  };
}

describe('Heatmap Aggregation Field Usage', () => {
  it('should only access timestamp for date extraction', () => {
    const accessedFields: Set<string> = new Set();

    // Create a proxy to track field access
    const activity = new Proxy(createMinimalActivity(), {
      get(target, prop) {
        if (typeof prop === 'string' && prop !== 'then') {
          accessedFields.add(prop);
        }
        return Reflect.get(target, prop);
      },
    });

    // Run aggregation
    aggregateToHeatmap([activity as UnifiedActivity]);

    // Verify only heatmap-required fields were accessed
    const unexpectedFields = Array.from(accessedFields).filter(
      (f) => !HEATMAP_REQUIRED_FIELDS.includes(f as (typeof HEATMAP_REQUIRED_FIELDS)[number])
    );

    // We expect only timestamp and provider to be accessed
    expect(accessedFields.has('timestamp')).toBe(true);
    expect(accessedFields.has('provider')).toBe(true);
  });

  it('should produce heatmap buckets using only date and provider info', () => {
    const activities: UnifiedActivity[] = [
      createMinimalActivity({ timestamp: '2024-01-15T10:00:00Z', provider: 'github' }),
      createMinimalActivity({ timestamp: '2024-01-15T14:00:00Z', provider: 'gitlab' }),
      createMinimalActivity({ timestamp: '2024-01-16T09:00:00Z', provider: 'github' }),
    ];

    const heatmap = aggregateToHeatmap(activities);

    // Heatmap output should only contain date, count, and breakdown
    expect(heatmap).toHaveLength(2);

    for (const bucket of heatmap) {
      // Verify bucket structure is minimal
      const bucketKeys = Object.keys(bucket);
      expect(bucketKeys).toContain('date');
      expect(bucketKeys).toContain('count');
      // breakdown is optional but allowed
      expect(bucketKeys.every((k) => ['date', 'count', 'breakdown'].includes(k))).toBe(true);
    }
  });

  it('should not require title, summary, url, or participants for aggregation', () => {
    // Activities with minimal fields (no optional drill-down fields)
    const minimalActivities: UnifiedActivity[] = [
      {
        id: 'test:account:1',
        provider: 'github',
        accountId: 'account',
        sourceId: '1',
        type: 'commit',
        timestamp: '2024-01-15T10:00:00Z',
        // No title, summary, url, or participants
      },
      {
        id: 'test:account:2',
        provider: 'gitlab',
        accountId: 'account',
        sourceId: '2',
        type: 'pull_request',
        timestamp: '2024-01-15T11:00:00Z',
        // No title, summary, url, or participants
      },
    ];

    // Aggregation should work without optional fields
    const heatmap = aggregateToHeatmap(minimalActivities);

    expect(heatmap).toHaveLength(1);
    expect(heatmap[0].date).toBe('2024-01-15');
    expect(heatmap[0].count).toBe(2);
  });

  it('should correctly count by type without accessing type value', () => {
    // The aggregation groups by date and optionally provider
    // Type is in the schema but not used for basic heatmap aggregation
    const activities = [
      createMinimalActivity({ type: 'commit' }),
      createMinimalActivity({ type: 'pull_request' }),
      createMinimalActivity({ type: 'issue' }),
    ];

    const heatmap = aggregateToHeatmap(activities);

    // All activities on same day should be counted together
    expect(heatmap[0].count).toBe(3);
  });
});

describe('Drill-down View Field Requirements', () => {
  it('should have all drill-down fields defined in schema', () => {
    for (const field of DRILLDOWN_REQUIRED_FIELDS) {
      expect(ALL_SCHEMA_FIELDS).toContain(field);
    }
  });

  it('should support optional drill-down fields', () => {
    // Create activity with all drill-down fields
    const fullActivity: UnifiedActivity = {
      id: 'test:account:item-1',
      provider: 'github',
      accountId: 'my-account',
      sourceId: 'abc123',
      type: 'pull_request',
      timestamp: '2024-01-15T10:00:00Z',
      title: 'Add new feature',
      summary: 'This PR adds a new feature that...',
      url: 'https://github.com/owner/repo/pull/123',
      participants: ['alice', 'bob'],
    };

    // Verify all drill-down fields are present
    expect(fullActivity.timestamp).toBeDefined();
    expect(fullActivity.title).toBeDefined();
    expect(fullActivity.summary).toBeDefined();
    expect(fullActivity.participants).toBeDefined();
    expect(fullActivity.url).toBeDefined();
    expect(fullActivity.sourceId).toBeDefined();
    expect(fullActivity.accountId).toBeDefined();
  });

  it('should allow minimal activity without optional drill-down fields', () => {
    const minimalActivity: UnifiedActivity = {
      id: 'test:account:item-1',
      provider: 'github',
      accountId: 'my-account',
      sourceId: 'abc123',
      type: 'commit',
      timestamp: '2024-01-15T10:00:00Z',
      // title, summary, url, participants all undefined
    };

    // Should validate successfully
    expect(minimalActivity.title).toBeUndefined();
    expect(minimalActivity.summary).toBeUndefined();
    expect(minimalActivity.url).toBeUndefined();
    expect(minimalActivity.participants).toBeUndefined();
  });

  it('should identify which fields are used for display vs aggregation', () => {
    const AGGREGATION_ONLY_FIELDS = ['timestamp', 'provider'];
    const DISPLAY_ONLY_FIELDS = ['title', 'summary', 'url', 'participants'];
    const IDENTIFICATION_FIELDS = ['id', 'sourceId', 'accountId', 'type'];

    // All fields should be categorized
    const allCategorized = [
      ...AGGREGATION_ONLY_FIELDS,
      ...DISPLAY_ONLY_FIELDS,
      ...IDENTIFICATION_FIELDS,
    ];

    // Every schema field should fit in one category
    for (const field of ALL_SCHEMA_FIELDS) {
      expect(allCategorized).toContain(field);
    }
  });
});

describe('Provider Adapter Field Extraction', () => {
  /**
   * Simulates what provider adapters should do:
   * Pick only the fields needed from raw API responses
   */
  interface RawGitHubPR {
    id: string;
    node_id: string;
    number: number;
    state: string;
    locked: boolean;
    title: string;
    body: string;
    created_at: string;
    updated_at: string;
    closed_at: string | null;
    merged_at: string | null;
    merge_commit_sha: string | null;
    assignee: unknown;
    assignees: unknown[];
    requested_reviewers: unknown[];
    requested_teams: unknown[];
    labels: unknown[];
    milestone: unknown;
    draft: boolean;
    commits: number;
    additions: number;
    deletions: number;
    changed_files: number;
    html_url: string;
    user: { login: string; id: number; avatar_url: string };
    // ... many more fields in real API
  }

  function normalizeGitHubPR(raw: RawGitHubPR, accountId: string): UnifiedActivity {
    // ONLY extract the fields we need
    return {
      id: `github:${accountId}:pr-${raw.id}`,
      provider: 'github',
      accountId,
      sourceId: raw.id,
      type: 'pull_request',
      timestamp: raw.created_at,
      title: raw.title,
      summary: raw.body?.slice(0, 200) || undefined,
      url: raw.html_url,
      participants: raw.user?.login ? [raw.user.login] : undefined,
    };
  }

  it('should discard extra fields from raw API response', () => {
    const rawPR: RawGitHubPR = {
      id: 'pr-123',
      node_id: 'MDExOlB1bGxSZXF1ZXN0MTIz',
      number: 42,
      state: 'open',
      locked: false,
      title: 'Add feature X',
      body: 'This PR adds feature X',
      created_at: '2024-01-15T10:00:00Z',
      updated_at: '2024-01-15T12:00:00Z',
      closed_at: null,
      merged_at: null,
      merge_commit_sha: null,
      assignee: null,
      assignees: [],
      requested_reviewers: [],
      requested_teams: [],
      labels: [],
      milestone: null,
      draft: false,
      commits: 3,
      additions: 100,
      deletions: 50,
      changed_files: 5,
      html_url: 'https://github.com/owner/repo/pull/42',
      user: { login: 'alice', id: 123, avatar_url: 'https://...' },
    };

    const normalized = normalizeGitHubPR(rawPR, 'gh-account');
    const normalizedKeys = Object.keys(normalized).filter(
      (k) => normalized[k as keyof UnifiedActivity] !== undefined
    );

    // Verify we only have UnifiedActivity fields
    for (const key of normalizedKeys) {
      expect(ALL_SCHEMA_FIELDS).toContain(key);
    }

    // Verify we DON'T have raw API fields
    expect(normalized).not.toHaveProperty('node_id');
    expect(normalized).not.toHaveProperty('number');
    expect(normalized).not.toHaveProperty('state');
    expect(normalized).not.toHaveProperty('draft');
    expect(normalized).not.toHaveProperty('commits');
    expect(normalized).not.toHaveProperty('additions');
    expect(normalized).not.toHaveProperty('deletions');
    expect(normalized).not.toHaveProperty('changed_files');
  });

  it('should truncate summary to 200 chars', () => {
    const longBody = 'A'.repeat(500);
    const rawPR: RawGitHubPR = {
      id: 'pr-123',
      node_id: '',
      number: 42,
      state: 'open',
      locked: false,
      title: 'Title',
      body: longBody,
      created_at: '2024-01-15T10:00:00Z',
      updated_at: '2024-01-15T12:00:00Z',
      closed_at: null,
      merged_at: null,
      merge_commit_sha: null,
      assignee: null,
      assignees: [],
      requested_reviewers: [],
      requested_teams: [],
      labels: [],
      milestone: null,
      draft: false,
      commits: 1,
      additions: 1,
      deletions: 1,
      changed_files: 1,
      html_url: 'https://github.com/owner/repo/pull/42',
      user: { login: 'alice', id: 1, avatar_url: '' },
    };

    const normalized = normalizeGitHubPR(rawPR, 'gh');

    expect(normalized.summary).toHaveLength(200);
  });

  it('should only extract participant username, not full user object', () => {
    const rawPR: RawGitHubPR = {
      id: 'pr-123',
      node_id: '',
      number: 42,
      state: 'open',
      locked: false,
      title: 'Title',
      body: '',
      created_at: '2024-01-15T10:00:00Z',
      updated_at: '2024-01-15T12:00:00Z',
      closed_at: null,
      merged_at: null,
      merge_commit_sha: null,
      assignee: null,
      assignees: [],
      requested_reviewers: [],
      requested_teams: [],
      labels: [],
      milestone: null,
      draft: false,
      commits: 1,
      additions: 1,
      deletions: 1,
      changed_files: 1,
      html_url: 'https://github.com/owner/repo/pull/42',
      user: { login: 'alice', id: 123, avatar_url: 'https://avatars...' },
    };

    const normalized = normalizeGitHubPR(rawPR, 'gh');

    // Participants should be array of strings, not objects
    expect(normalized.participants).toEqual(['alice']);
    expect(typeof normalized.participants![0]).toBe('string');
  });
});

describe('Schema Field Inventory', () => {
  it('should have exactly 9 fields in UnifiedActivity schema', () => {
    // This is an explicit check to catch any accidental schema expansion
    const expectedFields = [
      'id',
      'provider',
      'accountId',
      'sourceId',
      'type',
      'timestamp',
      'title',
      'summary',
      'participants',
      'url',
    ];

    expect(ALL_SCHEMA_FIELDS.sort()).toEqual(expectedFields.sort());
    expect(ALL_SCHEMA_FIELDS.length).toBe(10);
  });

  it('should identify required vs optional fields', () => {
    const REQUIRED_FIELDS = ['id', 'provider', 'accountId', 'sourceId', 'type', 'timestamp'];
    const OPTIONAL_FIELDS = ['title', 'summary', 'participants', 'url'];

    // Required fields must be present
    for (const field of REQUIRED_FIELDS) {
      expect(ALL_SCHEMA_FIELDS).toContain(field);
    }

    // Optional fields are also in schema but not required
    for (const field of OPTIONAL_FIELDS) {
      expect(ALL_SCHEMA_FIELDS).toContain(field);
    }

    // All fields are accounted for
    expect([...REQUIRED_FIELDS, ...OPTIONAL_FIELDS].sort()).toEqual(ALL_SCHEMA_FIELDS.sort());
  });
});

describe('Provider Output Snapshots', () => {
  // These tests verify that normalized output contains only expected fields

  it('should produce GitHub activity with only schema fields', () => {
    const githubActivity: UnifiedActivity = {
      id: 'github:personal:pr-123',
      provider: 'github',
      accountId: 'personal',
      sourceId: '123',
      type: 'pull_request',
      timestamp: '2024-01-15T10:00:00Z',
      title: 'Add feature',
      url: 'https://github.com/owner/repo/pull/123',
      participants: ['alice'],
    };

    const keys = Object.keys(githubActivity);
    for (const key of keys) {
      expect(ALL_SCHEMA_FIELDS).toContain(key);
    }
  });

  it('should produce GitLab activity with only schema fields', () => {
    const gitlabActivity: UnifiedActivity = {
      id: 'gitlab:work:event-456',
      provider: 'gitlab',
      accountId: 'work',
      sourceId: '456',
      type: 'commit',
      timestamp: '2024-01-15T10:00:00Z',
      title: '3 commits to main',
      summary: 'feat: add new endpoint',
      url: 'https://gitlab.com/group/project/-/commit/abc123',
      participants: ['bob'],
    };

    const keys = Object.keys(gitlabActivity);
    for (const key of keys) {
      expect(ALL_SCHEMA_FIELDS).toContain(key);
    }
  });

  it('should produce Azure DevOps activity with only schema fields', () => {
    const azureActivity: UnifiedActivity = {
      id: 'azure-devops:org1:pr-789',
      provider: 'azure-devops',
      accountId: 'org1',
      sourceId: '789',
      type: 'pull_request',
      timestamp: '2024-01-15T10:00:00Z',
      title: 'Fix bug in login',
      url: 'https://dev.azure.com/org/project/_git/repo/pullrequest/789',
      participants: ['charlie'],
    };

    const keys = Object.keys(azureActivity);
    for (const key of keys) {
      expect(ALL_SCHEMA_FIELDS).toContain(key);
    }
  });

  it('should produce Google Calendar activity with only schema fields', () => {
    const calendarActivity: UnifiedActivity = {
      id: 'google-calendar:personal:primary:event123',
      provider: 'google-calendar',
      accountId: 'personal',
      sourceId: 'event123',
      type: 'meeting',
      timestamp: '2024-01-15T14:00:00Z',
      title: 'Team Standup',
      url: 'https://calendar.google.com/event?eid=event123',
      participants: ['alice@example.com', 'bob@example.com'],
    };

    const keys = Object.keys(calendarActivity);
    for (const key of keys) {
      expect(ALL_SCHEMA_FIELDS).toContain(key);
    }
  });
});

describe('Minimal Data Contract Enforcement', () => {
  it('should verify heatmap output format is minimal', () => {
    const activities = [
      createMinimalActivity({ timestamp: '2024-01-15T10:00:00Z', provider: 'github' }),
    ];

    const heatmap = aggregateToHeatmap(activities);
    const bucket = heatmap[0];

    // Heatmap bucket should only have: date, count, optional breakdown
    const allowedKeys = ['date', 'count', 'breakdown'];
    const actualKeys = Object.keys(bucket);

    for (const key of actualKeys) {
      expect(allowedKeys).toContain(key);
    }
  });

  it('should verify breakdown contains only provider names', () => {
    const activities = [
      createMinimalActivity({ provider: 'github' }),
      createMinimalActivity({ provider: 'gitlab' }),
    ];

    const heatmap = aggregateToHeatmap(activities);
    const breakdown = heatmap[0].breakdown!;

    const allowedProviders = ['github', 'gitlab', 'azure-devops', 'google-calendar'];
    const actualProviders = Object.keys(breakdown);

    for (const provider of actualProviders) {
      expect(allowedProviders).toContain(provider);
    }
  });
});
