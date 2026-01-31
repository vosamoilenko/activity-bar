import { describe, it, expect } from 'vitest';
import {
  aggregateToHeatmap,
  extractUTCDate,
  mergeHeatmapBuckets,
  getCountForDate,
  getBreakdownForDate,
} from '../src/aggregation.js';
import type { UnifiedActivity, HeatMapBucket } from '../schemas/index.js';

/**
 * Helper to create a minimal valid activity
 */
function createActivity(
  overrides: Partial<UnifiedActivity> & { timestamp: string; provider: UnifiedActivity['provider'] }
): UnifiedActivity {
  return {
    id: `${overrides.provider}:account:${Date.now()}`,
    accountId: 'account',
    sourceId: String(Date.now()),
    type: 'commit',
    ...overrides,
  };
}

describe('aggregateToHeatmap', () => {
  describe('grouping by YYYY-MM-DD in UTC', () => {
    it('should group activities by UTC date', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:30:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T23:59:59Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-16T00:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(2);
      expect(heatmap[0].date).toBe('2024-01-15');
      expect(heatmap[0].count).toBe(2);
      expect(heatmap[1].date).toBe('2024-01-16');
      expect(heatmap[1].count).toBe(1);
    });

    it('should handle timestamps with milliseconds', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:30:00.123Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:30:00.999Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(1);
      expect(heatmap[0].date).toBe('2024-01-15');
      expect(heatmap[0].count).toBe(2);
    });

    it('should return empty array for empty input', () => {
      const heatmap = aggregateToHeatmap([]);
      expect(heatmap).toEqual([]);
    });

    it('should sort results by date ascending', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-20T10:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-18T10:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap.map((b) => b.date)).toEqual(['2024-01-15', '2024-01-18', '2024-01-20']);
    });
  });

  describe('total activity count per day', () => {
    it('should count total activities per day correctly', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T08:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T12:00:00Z' }),
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T16:00:00Z' }),
        createActivity({ provider: 'azure-devops', timestamp: '2024-01-15T20:00:00Z' }),
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-15T22:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(1);
      expect(heatmap[0].count).toBe(5);
    });
  });

  describe('per-provider breakdown', () => {
    it('should include per-provider breakdown by default', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T11:00:00Z' }),
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T12:00:00Z' }),
        createActivity({ provider: 'azure-devops', timestamp: '2024-01-15T13:00:00Z' }),
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-15T14:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap[0].breakdown).toEqual({
        github: 2,
        gitlab: 1,
        'azure-devops': 1,
        'google-calendar': 1,
      });
    });

    it('should exclude breakdown when includeBreakdown is false', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z' }),
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T11:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities, { includeBreakdown: false });

      expect(heatmap[0].breakdown).toBeUndefined();
      expect(heatmap[0].count).toBe(2);
    });

    it('should handle breakdown across multiple days', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z' }),
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T11:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-16T10:00:00Z' }),
        createActivity({ provider: 'azure-devops', timestamp: '2024-01-16T11:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap[0].date).toBe('2024-01-15');
      expect(heatmap[0].breakdown).toEqual({ github: 1, gitlab: 1 });
      expect(heatmap[1].date).toBe('2024-01-16');
      expect(heatmap[1].breakdown).toEqual({ github: 1, 'azure-devops': 1 });
    });
  });

  describe('same-day multiple events', () => {
    it('should correctly aggregate many events on the same day', () => {
      const activities: UnifiedActivity[] = [];
      for (let i = 0; i < 100; i++) {
        const hour = String(i % 24).padStart(2, '0');
        activities.push(
          createActivity({
            provider: 'github',
            timestamp: `2024-01-15T${hour}:00:00Z`,
          })
        );
      }

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(1);
      expect(heatmap[0].count).toBe(100);
      expect(heatmap[0].breakdown?.github).toBe(100);
    });

    it('should handle multiple activity types on the same day', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z', type: 'commit' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T11:00:00Z', type: 'pull_request' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T12:00:00Z', type: 'issue' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T13:00:00Z', type: 'code_review' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      // Aggregation counts all types together (type is not part of heatmap breakdown)
      expect(heatmap[0].count).toBe(4);
      expect(heatmap[0].breakdown?.github).toBe(4);
    });
  });

  describe('cross-provider mix', () => {
    it('should correctly aggregate activities from all providers', () => {
      const activities: UnifiedActivity[] = [
        // GitHub activities
        createActivity({ provider: 'github', timestamp: '2024-01-15T09:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T11:00:00Z' }),
        // GitLab activities
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T12:00:00Z' }),
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T13:00:00Z' }),
        // Azure DevOps activities
        createActivity({ provider: 'azure-devops', timestamp: '2024-01-15T14:00:00Z' }),
        // Google Calendar activities
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-15T15:00:00Z' }),
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-15T16:00:00Z' }),
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-15T17:00:00Z' }),
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-15T18:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(1);
      expect(heatmap[0].count).toBe(10);
      expect(heatmap[0].breakdown).toEqual({
        github: 3,
        gitlab: 2,
        'azure-devops': 1,
        'google-calendar': 4,
      });
    });

    it('should handle cross-provider activities across multiple days', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T10:00:00Z' }),
        createActivity({ provider: 'gitlab', timestamp: '2024-01-15T11:00:00Z' }),
        createActivity({ provider: 'azure-devops', timestamp: '2024-01-16T10:00:00Z' }),
        createActivity({ provider: 'google-calendar', timestamp: '2024-01-16T11:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-17T10:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(3);
      expect(heatmap[0].breakdown).toEqual({ github: 1, gitlab: 1 });
      expect(heatmap[1].breakdown).toEqual({ 'azure-devops': 1, 'google-calendar': 1 });
      expect(heatmap[2].breakdown).toEqual({ github: 1 });
    });
  });

  describe('timezone normalization', () => {
    it('should use UTC date from timestamp (not local time)', () => {
      // This test verifies that we extract the date from the UTC timestamp directly
      // and don't convert to local time
      const activities: UnifiedActivity[] = [
        // 23:00 UTC on Jan 15 should be Jan 15, not Jan 16 in any timezone
        createActivity({ provider: 'github', timestamp: '2024-01-15T23:00:00Z' }),
        // 00:00 UTC on Jan 16 should be Jan 16
        createActivity({ provider: 'github', timestamp: '2024-01-16T00:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(2);
      expect(heatmap[0].date).toBe('2024-01-15');
      expect(heatmap[1].date).toBe('2024-01-16');
    });

    it('should handle end-of-day boundary correctly', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-01-15T23:59:59Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-15T23:59:59.999Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-16T00:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-01-16T00:00:00.001Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(2);
      expect(heatmap[0].date).toBe('2024-01-15');
      expect(heatmap[0].count).toBe(2);
      expect(heatmap[1].date).toBe('2024-01-16');
      expect(heatmap[1].count).toBe(2);
    });

    it('should handle year boundary correctly', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-12-31T23:59:59Z' }),
        createActivity({ provider: 'github', timestamp: '2025-01-01T00:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(2);
      expect(heatmap[0].date).toBe('2024-12-31');
      expect(heatmap[1].date).toBe('2025-01-01');
    });

    it('should handle leap year day correctly', () => {
      const activities: UnifiedActivity[] = [
        createActivity({ provider: 'github', timestamp: '2024-02-28T23:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-02-29T12:00:00Z' }),
        createActivity({ provider: 'github', timestamp: '2024-03-01T01:00:00Z' }),
      ];

      const heatmap = aggregateToHeatmap(activities);

      expect(heatmap).toHaveLength(3);
      expect(heatmap.map((b) => b.date)).toEqual(['2024-02-28', '2024-02-29', '2024-03-01']);
    });
  });
});

describe('extractUTCDate', () => {
  it('should extract date from standard ISO8601 UTC timestamp', () => {
    expect(extractUTCDate('2024-01-15T10:30:00Z')).toBe('2024-01-15');
  });

  it('should extract date from timestamp with milliseconds', () => {
    expect(extractUTCDate('2024-01-15T10:30:00.123Z')).toBe('2024-01-15');
  });

  it('should handle midnight correctly', () => {
    expect(extractUTCDate('2024-01-15T00:00:00Z')).toBe('2024-01-15');
  });

  it('should handle end of day correctly', () => {
    expect(extractUTCDate('2024-01-15T23:59:59Z')).toBe('2024-01-15');
  });
});

describe('mergeHeatmapBuckets', () => {
  it('should merge buckets from multiple arrays', () => {
    const buckets1: HeatMapBucket[] = [
      { date: '2024-01-15', count: 5, breakdown: { github: 5 } },
    ];
    const buckets2: HeatMapBucket[] = [
      { date: '2024-01-15', count: 3, breakdown: { gitlab: 3 } },
    ];

    const merged = mergeHeatmapBuckets(buckets1, buckets2);

    expect(merged).toHaveLength(1);
    expect(merged[0].date).toBe('2024-01-15');
    expect(merged[0].count).toBe(8);
    expect(merged[0].breakdown).toEqual({ github: 5, gitlab: 3 });
  });

  it('should handle non-overlapping dates', () => {
    const buckets1: HeatMapBucket[] = [{ date: '2024-01-15', count: 5 }];
    const buckets2: HeatMapBucket[] = [{ date: '2024-01-16', count: 3 }];

    const merged = mergeHeatmapBuckets(buckets1, buckets2);

    expect(merged).toHaveLength(2);
    expect(merged[0].date).toBe('2024-01-15');
    expect(merged[1].date).toBe('2024-01-16');
  });

  it('should return empty array for empty inputs', () => {
    expect(mergeHeatmapBuckets([], [])).toEqual([]);
  });

  it('should sort merged results by date', () => {
    const buckets1: HeatMapBucket[] = [{ date: '2024-01-20', count: 1 }];
    const buckets2: HeatMapBucket[] = [{ date: '2024-01-15', count: 1 }];
    const buckets3: HeatMapBucket[] = [{ date: '2024-01-18', count: 1 }];

    const merged = mergeHeatmapBuckets(buckets1, buckets2, buckets3);

    expect(merged.map((b) => b.date)).toEqual(['2024-01-15', '2024-01-18', '2024-01-20']);
  });
});

describe('getCountForDate', () => {
  const heatmap: HeatMapBucket[] = [
    { date: '2024-01-15', count: 5 },
    { date: '2024-01-16', count: 10 },
  ];

  it('should return count for existing date', () => {
    expect(getCountForDate(heatmap, '2024-01-15')).toBe(5);
    expect(getCountForDate(heatmap, '2024-01-16')).toBe(10);
  });

  it('should return 0 for non-existing date', () => {
    expect(getCountForDate(heatmap, '2024-01-17')).toBe(0);
  });

  it('should return 0 for empty heatmap', () => {
    expect(getCountForDate([], '2024-01-15')).toBe(0);
  });
});

describe('getBreakdownForDate', () => {
  const heatmap: HeatMapBucket[] = [
    { date: '2024-01-15', count: 5, breakdown: { github: 3, gitlab: 2 } },
    { date: '2024-01-16', count: 3 },
  ];

  it('should return breakdown for existing date', () => {
    expect(getBreakdownForDate(heatmap, '2024-01-15')).toEqual({ github: 3, gitlab: 2 });
  });

  it('should return undefined for date without breakdown', () => {
    expect(getBreakdownForDate(heatmap, '2024-01-16')).toBeUndefined();
  });

  it('should return undefined for non-existing date', () => {
    expect(getBreakdownForDate(heatmap, '2024-01-17')).toBeUndefined();
  });
});
