# Activity Discovery Module

The `activity-discovery` module is a TypeScript/Node.js package that defines the unified activity schema and provides provider implementations and normalization utilities.

## Table of Contents

- [Overview](#overview)
- [Schema Definitions](#schema-definitions)
- [Providers](#providers)
- [Aggregation](#aggregation)
- [CLI Usage](#cli-usage)
- [Testing](#testing)

## Overview

While the main ActivityBar application is written in Swift, the `activity-discovery` module serves several purposes:

1. **Schema Definition** - Canonical TypeScript types that define the unified activity format
2. **Validation** - Zod schemas for runtime validation
3. **Reference Implementation** - Provider implementations that can be used as reference
4. **CLI Tool** - Command-line interface for fetching and aggregating activities

The Swift app maintains compatible data structures but doesn't directly execute this TypeScript code.

## Directory Structure

```
activity-discovery/
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── providers/
│   ├── index.ts              # Provider exports
│   ├── github/               # GitHub provider
│   │   ├── index.ts
│   │   ├── fetch.ts
│   │   ├── queries.ts
│   │   └── types.ts
│   ├── gitlab/               # GitLab provider
│   │   ├── index.ts
│   │   ├── fetch.ts
│   │   └── types.ts
│   ├── azure-devops/         # Azure DevOps provider
│   │   ├── index.ts
│   │   ├── fetch.ts
│   │   └── types.ts
│   └── google-calendar/      # Google Calendar provider
│       ├── index.ts
│       ├── fetch.ts
│       └── types.ts
├── normalizers/
│   ├── index.ts              # Normalizer exports
│   ├── mappings.ts           # Type mappings
│   ├── types.ts              # Normalizer types
│   └── utils.ts              # Utility functions
├── schemas/
│   ├── index.ts              # Schema exports
│   ├── types.ts              # TypeScript types
│   ├── validation.ts         # Zod schemas
│   └── snapshots/            # Schema snapshots for testing
├── src/
│   ├── index.ts              # Main exports
│   ├── run.ts                # CLI entry point
│   └── aggregation.ts        # Heatmap aggregation
└── tests/
    ├── aggregation.test.ts
    ├── azure-devops.test.ts
    ├── github.test.ts
    ├── gitlab.test.ts
    ├── google-calendar.test.ts
    └── normalizers.test.ts
```

## Schema Definitions

### Provider Enum

```typescript
// schemas/types.ts
export type Provider = 'github' | 'gitlab' | 'azureDevops' | 'googleCalendar';

export const providers: Provider[] = [
  'github',
  'gitlab',
  'azureDevops',
  'googleCalendar'
];
```

### Activity Type Enum

```typescript
export type ActivityType =
  | 'commit'
  | 'pullRequest'
  | 'issue'
  | 'issueComment'
  | 'codeReview'
  | 'meeting'
  | 'workItem'
  | 'deployment'
  | 'release'
  | 'wiki'
  | 'other';
```

### Unified Activity

```typescript
export interface UnifiedActivity {
  // Identity
  id: string;                    // "provider:accountId:sourceId"
  provider: Provider;
  accountId: string;
  sourceId: string;

  // Core data
  type: ActivityType;
  title: string;
  subtitle?: string;
  url?: string;
  timestamp: string;             // ISO 8601 datetime

  // Author
  authorName?: string;
  authorAvatarURL?: string;

  // Metadata
  labels?: ActivityLabel[];
  commentCount?: number;
  isDraft?: boolean;

  // PR/MR specific
  sourceRef?: string;
  targetRef?: string;
  projectName?: string;
  reviewers?: Participant[];

  // Calendar specific
  endTimestamp?: string;
  isAllDay?: boolean;
  attendees?: Participant[];
  calendarId?: string;

  // Commit specific
  commitSha?: string;
  filesChanged?: number;
  additions?: number;
  deletions?: number;
}
```

### Activity Label

```typescript
export interface ActivityLabel {
  name: string;
  color?: string;               // Hex color, e.g., "#ff0000"
}
```

### Participant

```typescript
export interface Participant {
  name: string;
  email?: string;
  avatarURL?: string;
}
```

### Heatmap Bucket

```typescript
export interface HeatMapBucket {
  date: string;                 // "YYYY-MM-DD" in UTC
  count: number;
  breakdown?: Record<Provider, number>;
}
```

### Zod Validation Schemas

```typescript
// schemas/validation.ts
import { z } from 'zod';

export const providerSchema = z.enum([
  'github',
  'gitlab',
  'azureDevops',
  'googleCalendar'
]);

export const activityTypeSchema = z.enum([
  'commit',
  'pullRequest',
  'issue',
  // ... etc
]);

export const unifiedActivitySchema = z.object({
  id: z.string(),
  provider: providerSchema,
  accountId: z.string(),
  sourceId: z.string(),
  type: activityTypeSchema,
  title: z.string(),
  timestamp: z.string().datetime(),
  // ... optional fields with .optional()
});

export const heatMapBucketSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  count: z.number().int().nonnegative(),
  breakdown: z.record(providerSchema, z.number()).optional()
});
```

## Providers

Each provider module exports a function to fetch activities.

### Provider Interface

```typescript
// providers/index.ts
export interface ProviderConfig {
  token: string;
  // Provider-specific config
}

export interface ProviderFetcher {
  fetchActivities(
    config: ProviderConfig,
    from: Date,
    to: Date
  ): Promise<UnifiedActivity[]>;

  fetchHeatmap?(
    config: ProviderConfig,
    from: Date,
    to: Date
  ): Promise<HeatMapBucket[]>;
}
```

### GitHub Provider

```typescript
// providers/github/index.ts
import { fetchGitHubActivities } from './fetch';

export interface GitHubConfig {
  token: string;
  username?: string;  // Defaults to authenticated user
}

export async function fetchActivities(
  config: GitHubConfig,
  from: Date,
  to: Date
): Promise<UnifiedActivity[]> {
  return fetchGitHubActivities(config, from, to);
}
```

**API Endpoints Used:**
- GraphQL API for user events
- REST API for commit details, PR details

### GitLab Provider

```typescript
// providers/gitlab/index.ts
export interface GitLabConfig {
  token: string;
  host?: string;      // Defaults to "gitlab.com"
  userId?: number;    // Defaults to authenticated user
}

export async function fetchActivities(
  config: GitLabConfig,
  from: Date,
  to: Date
): Promise<UnifiedActivity[]>;
```

**API Endpoints Used:**
- `GET /users/:id/events`
- `GET /projects/:id`
- `GET /projects/:id/merge_requests/:iid`

### Azure DevOps Provider

```typescript
// providers/azure-devops/index.ts
export interface AzureDevOpsConfig {
  token: string;
  organization: string;
  projects?: string[];  // Defaults to all projects
}

export async function fetchActivities(
  config: AzureDevOpsConfig,
  from: Date,
  to: Date
): Promise<UnifiedActivity[]>;
```

**API Endpoints Used:**
- `GET /_apis/projects`
- `GET /{project}/_apis/git/pullrequests`
- `GET /{project}/_apis/git/repositories/{repo}/commits`
- `POST /{project}/_apis/wit/wiql`

### Google Calendar Provider

```typescript
// providers/google-calendar/index.ts
export interface GoogleCalendarConfig {
  token: string;
  calendarIds?: string[];  // Defaults to all calendars
  showOnlyMyEvents?: boolean;
}

export async function fetchActivities(
  config: GoogleCalendarConfig,
  from: Date,
  to: Date
): Promise<UnifiedActivity[]>;
```

**API Endpoints Used:**
- `GET /calendar/v3/users/me/calendarList`
- `GET /calendar/v3/calendars/{calendarId}/events`

## Aggregation

### Heatmap Generation

```typescript
// src/aggregation.ts

/**
 * Groups activities by date and counts them
 */
export function aggregateToHeatmap(
  activities: UnifiedActivity[],
  includeBreakdown?: boolean
): HeatMapBucket[] {
  const buckets = new Map<string, { count: number; breakdown: Record<string, number> }>();

  for (const activity of activities) {
    const date = extractUTCDate(activity.timestamp);

    if (!buckets.has(date)) {
      buckets.set(date, { count: 0, breakdown: {} });
    }

    const bucket = buckets.get(date)!;
    bucket.count++;

    if (includeBreakdown) {
      bucket.breakdown[activity.provider] = (bucket.breakdown[activity.provider] || 0) + 1;
    }
  }

  return Array.from(buckets.entries()).map(([date, data]) => ({
    date,
    count: data.count,
    breakdown: includeBreakdown ? data.breakdown : undefined
  }));
}

/**
 * Extracts UTC date string from ISO timestamp
 */
export function extractUTCDate(timestamp: string): string {
  const date = new Date(timestamp);
  return date.toISOString().split('T')[0];
}

/**
 * Merges multiple bucket arrays, summing counts
 */
export function mergeHeatmapBuckets(
  ...bucketArrays: HeatMapBucket[][]
): HeatMapBucket[] {
  const merged = new Map<string, HeatMapBucket>();

  for (const buckets of bucketArrays) {
    for (const bucket of buckets) {
      if (merged.has(bucket.date)) {
        const existing = merged.get(bucket.date)!;
        existing.count += bucket.count;

        if (bucket.breakdown && existing.breakdown) {
          for (const [provider, count] of Object.entries(bucket.breakdown)) {
            existing.breakdown[provider] = (existing.breakdown[provider] || 0) + count;
          }
        }
      } else {
        merged.set(bucket.date, { ...bucket });
      }
    }
  }

  return Array.from(merged.values());
}
```

## CLI Usage

The module includes a CLI for testing and debugging.

### Installation

```bash
cd activity-discovery
npm install
```

### Running

```bash
# Fetch activities from all configured providers
npm run fetch

# Fetch from specific provider
npm run fetch -- --provider gitlab

# Fetch with date range
npm run fetch -- --from 2024-01-01 --to 2024-01-31

# Output as JSON
npm run fetch -- --output json

# Generate heatmap
npm run heatmap -- --days 90
```

### Configuration

Create `config.json` based on `config.example.json`:

```json
{
  "accounts": [
    {
      "provider": "gitlab",
      "token": "glpat-xxxxx",
      "config": {
        "host": "gitlab.com"
      }
    },
    {
      "provider": "azureDevops",
      "token": "xxxxx",
      "config": {
        "organization": "myorg",
        "projects": ["ProjectA", "ProjectB"]
      }
    },
    {
      "provider": "googleCalendar",
      "token": "ya29.xxxxx",
      "config": {
        "showOnlyMyEvents": true
      }
    }
  ]
}
```

## Testing

### Running Tests

```bash
cd activity-discovery
npm test
```

### Test Structure

```typescript
// tests/aggregation.test.ts
import { describe, it, expect } from 'vitest';
import { aggregateToHeatmap, mergeHeatmapBuckets } from '../src/aggregation';

describe('aggregateToHeatmap', () => {
  it('groups activities by date', () => {
    const activities = [
      { ...baseActivity, timestamp: '2024-01-15T10:00:00Z' },
      { ...baseActivity, timestamp: '2024-01-15T14:00:00Z' },
      { ...baseActivity, timestamp: '2024-01-16T09:00:00Z' },
    ];

    const buckets = aggregateToHeatmap(activities);

    expect(buckets).toHaveLength(2);
    expect(buckets.find(b => b.date === '2024-01-15')?.count).toBe(2);
    expect(buckets.find(b => b.date === '2024-01-16')?.count).toBe(1);
  });

  it('includes provider breakdown when requested', () => {
    const activities = [
      { ...baseActivity, provider: 'gitlab', timestamp: '2024-01-15T10:00:00Z' },
      { ...baseActivity, provider: 'azureDevops', timestamp: '2024-01-15T14:00:00Z' },
    ];

    const buckets = aggregateToHeatmap(activities, true);

    expect(buckets[0].breakdown).toEqual({
      gitlab: 1,
      azureDevops: 1
    });
  });
});
```

### Schema Snapshot Tests

```typescript
// tests/validation.test.ts
import { describe, it, expect } from 'vitest';
import { unifiedActivitySchema } from '../schemas/validation';
import snapshot from '../schemas/snapshots/unified-activity.snapshot.json';

describe('UnifiedActivity schema', () => {
  it('validates snapshot', () => {
    const result = unifiedActivitySchema.safeParse(snapshot);
    expect(result.success).toBe(true);
  });
});
```

## Swift Compatibility

The Swift `UnifiedActivity` struct mirrors this TypeScript interface exactly:

| TypeScript | Swift |
|------------|-------|
| `string` | `String` |
| `string?` (optional) | `String?` |
| `number` | `Int` |
| `boolean` | `Bool` |
| `ActivityType` | `ActivityType` enum |
| `Provider` | `Provider` enum |
| `Participant[]` | `[Participant]` |

Date handling:
- TypeScript: ISO 8601 string (`"2024-01-15T10:30:00Z"`)
- Swift: `Date` with ISO 8601 encoder/decoder

Both use the same ID format: `{provider}:{accountId}:{sourceId}`
