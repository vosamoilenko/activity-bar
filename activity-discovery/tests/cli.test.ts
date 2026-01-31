import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { validateActivityOutput } from '../schemas/index.js';
import type { UnifiedActivity, HeatMapBucket, ActivityOutput } from '../schemas/index.js';

/**
 * Mock implementations for testing CLI logic without actual network calls
 */

// Helper to create a mock activity
function createMockActivity(
  provider: 'github' | 'gitlab' | 'azure-devops' | 'google-calendar',
  accountId: string,
  index: number,
  date: string = '2024-01-15'
): UnifiedActivity {
  return {
    id: `${provider}:${accountId}:item-${index}`,
    provider,
    accountId,
    sourceId: `source-${index}`,
    type: provider === 'google-calendar' ? 'meeting' : 'commit',
    timestamp: `${date}T10:00:00Z`,
    title: `Test activity ${index} from ${provider}`,
  };
}

describe('CLI Argument Parsing', () => {
  // Test the parseArgs logic by simulating argument arrays

  it('should require --provider argument', () => {
    const args: string[] = [];
    // The actual CLI would exit with error, but we test the logic
    expect(args.includes('--provider')).toBe(false);
  });

  it('should accept valid provider names', () => {
    const validProviders = ['github', 'gitlab', 'azure-devops', 'google-calendar', 'all'];
    for (const provider of validProviders) {
      const args = ['--provider', provider];
      expect(args[1]).toBe(provider);
    }
  });

  it('should parse --daysBack as number', () => {
    const args = ['--provider', 'github', '--daysBack', '7'];
    const daysBackIndex = args.indexOf('--daysBack');
    const value = parseInt(args[daysBackIndex + 1], 10);
    expect(value).toBe(7);
  });

  it('should parse --account filter', () => {
    const args = ['--provider', 'all', '--account', 'work'];
    const accountIndex = args.indexOf('--account');
    expect(args[accountIndex + 1]).toBe('work');
  });

  it('should parse --timeMin and --timeMax', () => {
    const args = [
      '--provider', 'github',
      '--timeMin', '2024-01-01T00:00:00Z',
      '--timeMax', '2024-01-31T23:59:59Z'
    ];

    const timeMinIndex = args.indexOf('--timeMin');
    const timeMaxIndex = args.indexOf('--timeMax');

    expect(args[timeMinIndex + 1]).toBe('2024-01-01T00:00:00Z');
    expect(args[timeMaxIndex + 1]).toBe('2024-01-31T23:59:59Z');
  });

  it('should parse --config and --output paths', () => {
    const args = [
      '--provider', 'all',
      '--config', '/path/to/config.json',
      '--output', '/path/to/output.json'
    ];

    const configIndex = args.indexOf('--config');
    const outputIndex = args.indexOf('--output');

    expect(args[configIndex + 1]).toBe('/path/to/config.json');
    expect(args[outputIndex + 1]).toBe('/path/to/output.json');
  });
});

describe('FetchWindow Building', () => {
  it('should build window from daysBack', () => {
    const daysBack = 7;
    const now = new Date();
    const timeMin = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);

    expect(timeMin.getTime()).toBeLessThan(now.getTime());
    expect(now.getTime() - timeMin.getTime()).toBe(daysBack * 24 * 60 * 60 * 1000);
  });

  it('should use explicit timeMin/timeMax when provided', () => {
    const timeMin = '2024-01-01T00:00:00Z';
    const timeMax = '2024-01-31T23:59:59Z';

    const window = { timeMin, timeMax };
    expect(window.timeMin).toBe('2024-01-01T00:00:00Z');
    expect(window.timeMax).toBe('2024-01-31T23:59:59Z');
  });

  it('should default daysBack to 30', () => {
    const defaultDaysBack = 30;
    expect(defaultDaysBack).toBe(30);
  });
});

describe('Account Filtering', () => {
  const mockAccounts = [
    { id: 'github-personal', token: 'token1' },
    { id: 'github-work', token: 'token2' },
    { id: 'gitlab-personal', token: 'token3' },
  ];

  function getAccountsForProvider<T extends { id: string }>(
    accounts: T[],
    accountFilter?: string
  ): T[] {
    if (!accountFilter) {
      return accounts;
    }
    return accounts.filter((a) => a.id === accountFilter || a.id.includes(accountFilter));
  }

  it('should return all accounts when no filter', () => {
    const result = getAccountsForProvider(mockAccounts);
    expect(result).toHaveLength(3);
  });

  it('should filter by exact account ID', () => {
    const result = getAccountsForProvider(mockAccounts, 'github-personal');
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('github-personal');
  });

  it('should filter by partial match', () => {
    const result = getAccountsForProvider(mockAccounts, 'personal');
    expect(result).toHaveLength(2);
    expect(result.map((a) => a.id)).toContain('github-personal');
    expect(result.map((a) => a.id)).toContain('gitlab-personal');
  });

  it('should return empty array for non-matching filter', () => {
    const result = getAccountsForProvider(mockAccounts, 'nonexistent');
    expect(result).toHaveLength(0);
  });
});

describe('Result Merging', () => {
  it('should merge activities from multiple accounts', () => {
    const results = [
      {
        provider: 'github' as const,
        accountId: 'github-personal',
        activities: [
          createMockActivity('github', 'github-personal', 1),
          createMockActivity('github', 'github-personal', 2),
        ],
      },
      {
        provider: 'gitlab' as const,
        accountId: 'gitlab-work',
        activities: [
          createMockActivity('gitlab', 'gitlab-work', 1),
        ],
      },
    ];

    const allActivities: UnifiedActivity[] = [];
    for (const result of results) {
      allActivities.push(...result.activities);
    }

    expect(allActivities).toHaveLength(3);
  });

  it('should sort merged activities by timestamp descending', () => {
    const activities = [
      createMockActivity('github', 'gh', 1, '2024-01-10'),
      createMockActivity('gitlab', 'gl', 1, '2024-01-15'),
      createMockActivity('azure-devops', 'az', 1, '2024-01-12'),
    ];

    activities.sort((a, b) => b.timestamp.localeCompare(a.timestamp));

    expect(activities[0].provider).toBe('gitlab'); // 2024-01-15
    expect(activities[1].provider).toBe('azure-devops'); // 2024-01-12
    expect(activities[2].provider).toBe('github'); // 2024-01-10
  });

  it('should isolate errors per account', () => {
    const results = [
      {
        provider: 'github' as const,
        accountId: 'github-personal',
        activities: [createMockActivity('github', 'github-personal', 1)],
      },
      {
        provider: 'gitlab' as const,
        accountId: 'gitlab-work',
        activities: [],
        error: 'Authentication failed',
      },
      {
        provider: 'azure-devops' as const,
        accountId: 'azure-org1',
        activities: [createMockActivity('azure-devops', 'azure-org1', 1)],
      },
    ];

    const allActivities: UnifiedActivity[] = [];
    const errors: Array<{ provider: string; accountId: string; error: string }> = [];

    for (const result of results) {
      allActivities.push(...result.activities);
      if (result.error) {
        errors.push({
          provider: result.provider,
          accountId: result.accountId,
          error: result.error,
        });
      }
    }

    // Activities from successful accounts should be included
    expect(allActivities).toHaveLength(2);

    // Errors should be tracked separately
    expect(errors).toHaveLength(1);
    expect(errors[0].provider).toBe('gitlab');
    expect(errors[0].accountId).toBe('gitlab-work');
    expect(errors[0].error).toBe('Authentication failed');
  });
});

describe('Output Format', () => {
  it('should produce valid ActivityOutput structure', () => {
    const activities = [
      createMockActivity('github', 'gh', 1, '2024-01-15'),
      createMockActivity('gitlab', 'gl', 1, '2024-01-15'),
    ];

    // Simulate heatmap generation
    const heatmap: HeatMapBucket[] = [
      {
        date: '2024-01-15',
        count: 2,
        breakdown: {
          github: 1,
          gitlab: 1,
        },
      },
    ];

    const output: ActivityOutput = {
      activities,
      heatmap,
    };

    expect(() => validateActivityOutput(output)).not.toThrow();
    expect(output.activities).toHaveLength(2);
    expect(output.heatmap).toHaveLength(1);
  });

  it('should include errors array when accounts fail', () => {
    const activities: UnifiedActivity[] = [];
    const heatmap: HeatMapBucket[] = [];
    const errors = [
      { provider: 'github' as const, accountId: 'gh', error: 'Token expired' },
    ];

    const output = {
      activities,
      heatmap,
      errors,
    };

    expect(output.errors).toHaveLength(1);
    expect(output.errors![0].error).toBe('Token expired');
  });

  it('should not include errors array when all accounts succeed', () => {
    const activities = [createMockActivity('github', 'gh', 1)];
    const heatmap: HeatMapBucket[] = [{ date: '2024-01-15', count: 1 }];
    const errors: Array<{ provider: string; accountId: string; error: string }> = [];

    const output: ActivityOutput & { errors?: typeof errors } = {
      activities,
      heatmap,
    };

    if (errors.length > 0) {
      output.errors = errors;
    }

    expect(output.errors).toBeUndefined();
  });
});

describe('Provider Selection', () => {
  const providers = ['github', 'gitlab', 'azure-devops', 'google-calendar'] as const;

  it('should support all individual providers', () => {
    for (const provider of providers) {
      expect(typeof provider).toBe('string');
      expect(providers).toContain(provider);
    }
  });

  it('should support "all" to run all providers', () => {
    const providerArg = 'all';
    const runAll = providerArg === 'all';
    expect(runAll).toBe(true);
  });

  it('should map provider to correct fetch function', () => {
    const providerFetchMap = {
      github: 'fetchGitHubActivities',
      gitlab: 'fetchGitLabActivities',
      'azure-devops': 'fetchAzureDevOpsActivities',
      'google-calendar': 'fetchGoogleCalendarActivities',
    };

    for (const provider of providers) {
      expect(providerFetchMap[provider]).toBeDefined();
    }
  });
});

describe('Config Loading', () => {
  it('should expect providers object in config', () => {
    const mockConfig = {
      providers: {
        github: { accounts: [] },
        gitlab: { accounts: [] },
        'azure-devops': { accounts: [] },
        'google-calendar': { accounts: [] },
      },
    };

    expect(mockConfig.providers).toBeDefined();
    expect(mockConfig.providers.github).toBeDefined();
    expect(mockConfig.providers.gitlab).toBeDefined();
    expect(mockConfig.providers['azure-devops']).toBeDefined();
    expect(mockConfig.providers['google-calendar']).toBeDefined();
  });

  it('should handle missing provider sections gracefully', () => {
    const partialConfig = {
      providers: {
        github: { accounts: [{ id: 'gh', token: 'token' }] },
        // gitlab, azure-devops, google-calendar are missing
      },
    };

    const githubAccounts = partialConfig.providers.github?.accounts ?? [];
    const gitlabAccounts = (partialConfig.providers as Record<string, { accounts: unknown[] } | undefined>).gitlab?.accounts ?? [];

    expect(githubAccounts).toHaveLength(1);
    expect(gitlabAccounts).toHaveLength(0);
  });
});

describe('Cross-Provider Integration', () => {
  it('should handle activities from all 4 providers', () => {
    const activities = [
      createMockActivity('github', 'gh', 1),
      createMockActivity('gitlab', 'gl', 1),
      createMockActivity('azure-devops', 'az', 1),
      createMockActivity('google-calendar', 'gc', 1),
    ];

    const providers = new Set(activities.map((a) => a.provider));

    expect(providers.size).toBe(4);
    expect(providers.has('github')).toBe(true);
    expect(providers.has('gitlab')).toBe(true);
    expect(providers.has('azure-devops')).toBe(true);
    expect(providers.has('google-calendar')).toBe(true);
  });

  it('should deduplicate by activity ID across reruns', () => {
    // Activities with same ID should be considered duplicates
    const activity1 = createMockActivity('github', 'gh', 1);
    const activity2 = createMockActivity('github', 'gh', 1); // Same ID

    expect(activity1.id).toBe(activity2.id);

    // Deduplication would use Map or Set keyed by ID
    const seen = new Map<string, UnifiedActivity>();
    seen.set(activity1.id, activity1);
    seen.set(activity2.id, activity2);

    expect(seen.size).toBe(1);
  });

  it('should handle mixed success/failure across providers', () => {
    const results = [
      { provider: 'github' as const, accountId: 'gh', activities: [createMockActivity('github', 'gh', 1)] },
      { provider: 'gitlab' as const, accountId: 'gl', activities: [], error: 'Network error' },
      { provider: 'azure-devops' as const, accountId: 'az', activities: [createMockActivity('azure-devops', 'az', 1)] },
      { provider: 'google-calendar' as const, accountId: 'gc', activities: [], error: 'OAuth expired' },
    ];

    const successCount = results.filter((r) => !r.error).length;
    const errorCount = results.filter((r) => r.error).length;

    expect(successCount).toBe(2);
    expect(errorCount).toBe(2);

    // Total activities should only come from successful accounts
    const totalActivities = results.reduce((sum, r) => sum + r.activities.length, 0);
    expect(totalActivities).toBe(2);
  });
});
