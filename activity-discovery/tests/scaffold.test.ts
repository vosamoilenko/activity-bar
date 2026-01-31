import { describe, it, expect } from 'vitest';
import type {
  UnifiedActivity,
  HeatMapBucket,
  ActivityOutput,
  Provider,
  ActivityType,
} from '../schemas/index.js';

describe('Scaffold', () => {
  describe('UnifiedActivity type', () => {
    it('should allow valid activity objects', () => {
      const activity: UnifiedActivity = {
        id: 'github:account1:abc123',
        provider: 'github',
        accountId: 'account1',
        sourceId: 'abc123',
        type: 'commit',
        timestamp: '2024-01-15T10:30:00Z',
        title: 'feat: add new feature',
        url: 'https://github.com/user/repo/commit/abc123',
      };

      expect(activity.id).toBe('github:account1:abc123');
      expect(activity.provider).toBe('github');
      expect(activity.type).toBe('commit');
    });

    it('should allow optional fields to be omitted', () => {
      const activity: UnifiedActivity = {
        id: 'gitlab:account2:def456',
        provider: 'gitlab',
        accountId: 'account2',
        sourceId: 'def456',
        type: 'pull_request',
        timestamp: '2024-01-15T14:00:00Z',
      };

      expect(activity.title).toBeUndefined();
      expect(activity.summary).toBeUndefined();
      expect(activity.participants).toBeUndefined();
      expect(activity.url).toBeUndefined();
    });
  });

  describe('HeatMapBucket type', () => {
    it('should allow valid heatmap bucket objects', () => {
      const bucket: HeatMapBucket = {
        date: '2024-01-15',
        count: 5,
        breakdown: {
          github: 3,
          gitlab: 2,
        },
      };

      expect(bucket.date).toBe('2024-01-15');
      expect(bucket.count).toBe(5);
      expect(bucket.breakdown?.github).toBe(3);
    });

    it('should allow breakdown to be omitted', () => {
      const bucket: HeatMapBucket = {
        date: '2024-01-16',
        count: 10,
      };

      expect(bucket.breakdown).toBeUndefined();
    });
  });

  describe('ActivityOutput type', () => {
    it('should allow valid output structure', () => {
      const output: ActivityOutput = {
        activities: [
          {
            id: 'google-calendar:personal:event1',
            provider: 'google-calendar',
            accountId: 'personal',
            sourceId: 'event1',
            type: 'meeting',
            timestamp: '2024-01-15T09:00:00Z',
            title: 'Team Standup',
            participants: ['alice@example.com', 'bob@example.com'],
          },
        ],
        heatmap: [
          {
            date: '2024-01-15',
            count: 1,
            breakdown: {
              'google-calendar': 1,
            },
          },
        ],
      };

      expect(output.activities).toHaveLength(1);
      expect(output.heatmap).toHaveLength(1);
      expect(output.activities[0].type).toBe('meeting');
    });
  });

  describe('Provider values', () => {
    it('should support all required providers', () => {
      const providers: Provider[] = ['github', 'gitlab', 'azure-devops', 'google-calendar'];
      expect(providers).toHaveLength(4);
    });
  });

  describe('ActivityType values', () => {
    it('should support all required activity types', () => {
      const types: ActivityType[] = [
        'commit',
        'pull_request',
        'pull_request_comment',
        'issue',
        'issue_comment',
        'code_review',
        'pipeline',
        'meeting',
      ];
      expect(types).toHaveLength(8);
    });
  });
});

describe('Directory structure', () => {
  it('should have required folders', async () => {
    const fs = await import('fs/promises');
    const path = await import('path');

    const baseDir = path.resolve(import.meta.dirname, '..');
    const requiredDirs = ['providers', 'schemas', 'normalizers', 'tests'];

    for (const dir of requiredDirs) {
      const stat = await fs.stat(path.join(baseDir, dir));
      expect(stat.isDirectory()).toBe(true);
    }
  });

  it('should have config example file', async () => {
    const fs = await import('fs/promises');
    const path = await import('path');

    const baseDir = path.resolve(import.meta.dirname, '..');
    const configPath = path.join(baseDir, 'config.example.json');

    const content = await fs.readFile(configPath, 'utf-8');
    const config = JSON.parse(content);

    expect(config.providers).toBeDefined();
    expect(config.providers.github).toBeDefined();
    expect(config.providers.gitlab).toBeDefined();
    expect(config.providers['azure-devops']).toBeDefined();
    expect(config.providers['google-calendar']).toBeDefined();
  });
});
