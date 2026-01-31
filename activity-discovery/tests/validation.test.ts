import { describe, it, expect } from 'vitest';
import { ZodError } from 'zod';
import {
  UnifiedActivitySchema,
  HeatMapBucketSchema,
  ActivityOutputSchema,
  ProviderSchema,
  ActivityTypeSchema,
  validateActivity,
  safeValidateActivity,
  validateHeatMapBucket,
  safeValidateHeatMapBucket,
  validateActivityOutput,
  formatValidationErrors,
} from '../schemas/index.js';

describe('UnifiedActivitySchema', () => {
  const validActivity = {
    id: 'github:account1:abc123',
    provider: 'github',
    accountId: 'account1',
    sourceId: 'abc123',
    type: 'commit',
    timestamp: '2024-01-15T10:30:00Z',
  };

  describe('valid records', () => {
    it('should accept minimal valid activity', () => {
      const result = UnifiedActivitySchema.safeParse(validActivity);
      expect(result.success).toBe(true);
    });

    it('should accept activity with all optional fields', () => {
      const fullActivity = {
        ...validActivity,
        title: 'feat: add new feature',
        summary: 'Added a fantastic new feature',
        participants: ['alice', 'bob'],
        url: 'https://github.com/user/repo/commit/abc123',
      };
      const result = UnifiedActivitySchema.safeParse(fullActivity);
      expect(result.success).toBe(true);
    });

    it('should accept timestamp with milliseconds', () => {
      const activity = {
        ...validActivity,
        timestamp: '2024-01-15T10:30:00.123Z',
      };
      const result = UnifiedActivitySchema.safeParse(activity);
      expect(result.success).toBe(true);
    });

    it('should accept all valid providers', () => {
      const providers = ['github', 'gitlab', 'azure-devops', 'google-calendar'];
      for (const provider of providers) {
        const activity = { ...validActivity, provider };
        const result = UnifiedActivitySchema.safeParse(activity);
        expect(result.success, `Provider ${provider} should be valid`).toBe(true);
      }
    });

    it('should accept all valid activity types', () => {
      const types = [
        'commit',
        'pull_request',
        'pull_request_comment',
        'issue',
        'issue_comment',
        'code_review',
        'pipeline',
        'meeting',
      ];
      for (const type of types) {
        const activity = { ...validActivity, type };
        const result = UnifiedActivitySchema.safeParse(activity);
        expect(result.success, `Type ${type} should be valid`).toBe(true);
      }
    });
  });

  describe('invalid records with actionable errors', () => {
    it('should reject missing required id', () => {
      const activity = { ...validActivity };
      delete (activity as Record<string, unknown>).id;
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('id'))).toBe(true);
      }
    });

    it('should reject empty id', () => {
      const activity = { ...validActivity, id: '' };
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('id') && e.includes('required'))).toBe(true);
      }
    });

    it('should reject invalid provider', () => {
      const activity = { ...validActivity, provider: 'bitbucket' };
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('provider'))).toBe(true);
      }
    });

    it('should reject invalid activity type', () => {
      const activity = { ...validActivity, type: 'unknown_type' };
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('type'))).toBe(true);
      }
    });

    it('should reject non-UTC timestamp', () => {
      const activity = { ...validActivity, timestamp: '2024-01-15T10:30:00' };
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('timestamp') && e.includes('UTC'))).toBe(true);
      }
    });

    it('should reject timestamp with timezone offset', () => {
      const activity = { ...validActivity, timestamp: '2024-01-15T10:30:00+05:00' };
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
    });

    it('should reject invalid URL format', () => {
      const activity = { ...validActivity, url: 'not-a-valid-url' };
      const result = safeValidateActivity(activity);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('url'))).toBe(true);
      }
    });

    it('should throw ZodError with validateActivity', () => {
      const activity = { ...validActivity, provider: 'invalid' };
      expect(() => validateActivity(activity)).toThrow(ZodError);
    });
  });
});

describe('HeatMapBucketSchema', () => {
  const validBucket = {
    date: '2024-01-15',
    count: 5,
  };

  describe('valid records', () => {
    it('should accept minimal valid bucket', () => {
      const result = HeatMapBucketSchema.safeParse(validBucket);
      expect(result.success).toBe(true);
    });

    it('should accept bucket with breakdown', () => {
      const bucket = {
        ...validBucket,
        breakdown: {
          github: 3,
          gitlab: 2,
        },
      };
      const result = HeatMapBucketSchema.safeParse(bucket);
      expect(result.success).toBe(true);
    });

    it('should accept bucket with all providers in breakdown', () => {
      const bucket = {
        ...validBucket,
        breakdown: {
          github: 1,
          gitlab: 2,
          'azure-devops': 3,
          'google-calendar': 4,
        },
      };
      const result = HeatMapBucketSchema.safeParse(bucket);
      expect(result.success).toBe(true);
    });

    it('should accept zero count', () => {
      const bucket = { ...validBucket, count: 0 };
      const result = HeatMapBucketSchema.safeParse(bucket);
      expect(result.success).toBe(true);
    });
  });

  describe('invalid records with actionable errors', () => {
    it('should reject invalid date format', () => {
      const bucket = { ...validBucket, date: '01/15/2024' };
      const result = safeValidateHeatMapBucket(bucket);
      expect(result.success).toBe(false);
      if (!result.success) {
        const errors = formatValidationErrors(result.error);
        expect(errors.some((e) => e.includes('date') && e.includes('YYYY-MM-DD'))).toBe(true);
      }
    });

    it('should reject negative count', () => {
      const bucket = { ...validBucket, count: -1 };
      const result = safeValidateHeatMapBucket(bucket);
      expect(result.success).toBe(false);
    });

    it('should reject non-integer count', () => {
      const bucket = { ...validBucket, count: 5.5 };
      const result = safeValidateHeatMapBucket(bucket);
      expect(result.success).toBe(false);
    });

    it('should reject negative breakdown values', () => {
      const bucket = {
        ...validBucket,
        breakdown: { github: -1 },
      };
      const result = safeValidateHeatMapBucket(bucket);
      expect(result.success).toBe(false);
    });

    it('should throw ZodError with validateHeatMapBucket', () => {
      const bucket = { ...validBucket, date: 'invalid' };
      expect(() => validateHeatMapBucket(bucket)).toThrow(ZodError);
    });
  });
});

describe('ActivityOutputSchema', () => {
  it('should accept valid output structure', () => {
    const output = {
      activities: [
        {
          id: 'github:account1:abc123',
          provider: 'github',
          accountId: 'account1',
          sourceId: 'abc123',
          type: 'commit',
          timestamp: '2024-01-15T10:30:00Z',
        },
      ],
      heatmap: [
        {
          date: '2024-01-15',
          count: 1,
          breakdown: { github: 1 },
        },
      ],
    };
    const result = ActivityOutputSchema.safeParse(output);
    expect(result.success).toBe(true);
  });

  it('should accept empty arrays', () => {
    const output = {
      activities: [],
      heatmap: [],
    };
    const result = ActivityOutputSchema.safeParse(output);
    expect(result.success).toBe(true);
  });

  it('should reject invalid activity in array', () => {
    const output = {
      activities: [
        {
          id: 'github:account1:abc123',
          provider: 'invalid-provider',
          accountId: 'account1',
          sourceId: 'abc123',
          type: 'commit',
          timestamp: '2024-01-15T10:30:00Z',
        },
      ],
      heatmap: [],
    };
    const result = ActivityOutputSchema.safeParse(output);
    expect(result.success).toBe(false);
  });

  it('should validate with validateActivityOutput function', () => {
    const output = {
      activities: [],
      heatmap: [],
    };
    const result = validateActivityOutput(output);
    expect(result.activities).toEqual([]);
    expect(result.heatmap).toEqual([]);
  });
});

describe('ProviderSchema', () => {
  it('should accept all valid providers', () => {
    expect(ProviderSchema.safeParse('github').success).toBe(true);
    expect(ProviderSchema.safeParse('gitlab').success).toBe(true);
    expect(ProviderSchema.safeParse('azure-devops').success).toBe(true);
    expect(ProviderSchema.safeParse('google-calendar').success).toBe(true);
  });

  it('should reject invalid providers', () => {
    expect(ProviderSchema.safeParse('bitbucket').success).toBe(false);
    expect(ProviderSchema.safeParse('jira').success).toBe(false);
    expect(ProviderSchema.safeParse('').success).toBe(false);
  });
});

describe('ActivityTypeSchema', () => {
  it('should accept all valid activity types', () => {
    const types = [
      'commit',
      'pull_request',
      'pull_request_comment',
      'issue',
      'issue_comment',
      'code_review',
      'pipeline',
      'meeting',
    ];
    for (const type of types) {
      expect(ActivityTypeSchema.safeParse(type).success).toBe(true);
    }
  });

  it('should reject invalid activity types', () => {
    expect(ActivityTypeSchema.safeParse('task').success).toBe(false);
    expect(ActivityTypeSchema.safeParse('deployment').success).toBe(false);
  });
});

describe('formatValidationErrors', () => {
  it('should format nested path errors', () => {
    const result = ActivityOutputSchema.safeParse({
      activities: [{ invalid: true }],
      heatmap: [],
    });

    expect(result.success).toBe(false);
    if (!result.success) {
      const errors = formatValidationErrors(result.error);
      expect(errors.length).toBeGreaterThan(0);
      expect(errors.some((e) => e.includes('activities'))).toBe(true);
    }
  });
});

describe('Provider-normalized records validation', () => {
  it('should validate GitHub commit activity', () => {
    const githubCommit = {
      id: 'github:personal:commit-sha123',
      provider: 'github',
      accountId: 'personal',
      sourceId: 'commit-sha123',
      type: 'commit',
      timestamp: '2024-01-15T14:30:00Z',
      title: 'feat: implement feature X',
      url: 'https://github.com/user/repo/commit/sha123',
    };
    expect(validateActivity(githubCommit)).toBeDefined();
  });

  it('should validate GitLab merge request activity', () => {
    const gitlabMR = {
      id: 'gitlab:work:mr-456',
      provider: 'gitlab',
      accountId: 'work',
      sourceId: 'mr-456',
      type: 'pull_request',
      timestamp: '2024-01-15T09:00:00Z',
      title: 'Add new API endpoint',
      summary: 'Implements REST API for user management',
      participants: ['alice', 'bob'],
      url: 'https://gitlab.com/org/repo/-/merge_requests/456',
    };
    expect(validateActivity(gitlabMR)).toBeDefined();
  });

  it('should validate Azure DevOps work item activity', () => {
    const azureWorkItem = {
      id: 'azure-devops:org1:wi-789',
      provider: 'azure-devops',
      accountId: 'org1',
      sourceId: 'wi-789',
      type: 'issue',
      timestamp: '2024-01-15T11:00:00Z',
      title: 'Bug: Fix login error',
      url: 'https://dev.azure.com/org/project/_workitems/edit/789',
    };
    expect(validateActivity(azureWorkItem)).toBeDefined();
  });

  it('should validate Google Calendar meeting activity', () => {
    const calendarMeeting = {
      id: 'google-calendar:personal:event-abc',
      provider: 'google-calendar',
      accountId: 'personal',
      sourceId: 'event-abc',
      type: 'meeting',
      timestamp: '2024-01-15T15:00:00Z',
      title: 'Team Standup',
      participants: ['alice@example.com', 'bob@example.com', 'charlie@example.com'],
      url: 'https://calendar.google.com/calendar/event?eid=abc',
    };
    expect(validateActivity(calendarMeeting)).toBeDefined();
  });
});
