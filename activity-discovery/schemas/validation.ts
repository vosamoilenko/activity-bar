/**
 * Zod schemas for runtime validation of activity data structures
 * These schemas enforce the data contracts at runtime and provide
 * actionable error messages for invalid records.
 */

import { z } from 'zod';

/**
 * Provider identifiers supported by the activity aggregation system
 */
export const ProviderSchema = z.enum([
  'github',
  'gitlab',
  'azure-devops',
  'google-calendar',
]);

/**
 * Activity types that can be normalized from provider-specific events
 */
export const ActivityTypeSchema = z.enum([
  'commit',
  'pull_request',
  'pull_request_comment',
  'issue',
  'issue_comment',
  'code_review',
  'pipeline',
  'meeting',
]);

/**
 * ISO8601 UTC timestamp regex pattern
 * Matches: 2024-01-15T10:30:00Z or 2024-01-15T10:30:00.000Z
 */
const ISO8601_UTC_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/;

/**
 * ISO8601 UTC timestamp schema with validation
 */
export const TimestampSchema = z
  .string()
  .regex(ISO8601_UTC_REGEX, {
    message: 'Timestamp must be ISO8601 UTC format (e.g., 2024-01-15T10:30:00Z)',
  });

/**
 * Date in YYYY-MM-DD format
 */
const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

export const DateSchema = z
  .string()
  .regex(DATE_REGEX, {
    message: 'Date must be in YYYY-MM-DD format',
  });

/**
 * Unified activity record schema
 */
export const UnifiedActivitySchema = z.object({
  /** Unique identifier: `${provider}:${accountId}:${sourceId}` */
  id: z.string().min(1, 'Activity ID is required'),
  /** Source provider */
  provider: ProviderSchema,
  /** Account identifier from config */
  accountId: z.string().min(1, 'Account ID is required'),
  /** Provider-specific identifier for the source entity */
  sourceId: z.string().min(1, 'Source ID is required'),
  /** Normalized activity type */
  type: ActivityTypeSchema,
  /** ISO8601 UTC timestamp */
  timestamp: TimestampSchema,
  /** Activity title (optional) */
  title: z.string().optional(),
  /** Brief summary or description (optional) */
  summary: z.string().optional(),
  /** Participant usernames or emails (optional) */
  participants: z.array(z.string()).optional(),
  /** Deep link URL to the source (optional) */
  url: z.string().url().optional(),
  /** Source branch/ref name (optional) */
  sourceRef: z.string().optional(),
  /** Target branch/ref name (optional) */
  targetRef: z.string().optional(),
  /** Raw event type from provider (optional) */
  rawEventType: z.string().optional(),
});

/**
 * Per-provider activity count breakdown schema
 */
export const ProviderBreakdownSchema = z.object({
  github: z.number().int().nonnegative().optional(),
  gitlab: z.number().int().nonnegative().optional(),
  'azure-devops': z.number().int().nonnegative().optional(),
  'google-calendar': z.number().int().nonnegative().optional(),
});

/**
 * Aggregated activity count for a single day schema
 */
export const HeatMapBucketSchema = z.object({
  /** Date in YYYY-MM-DD format (UTC) */
  date: DateSchema,
  /** Total activity count for the day */
  count: z.number().int().nonnegative(),
  /** Optional per-provider breakdown */
  breakdown: ProviderBreakdownSchema.optional(),
});

/**
 * Time window specification schema
 */
export const FetchWindowSchema = z.object({
  /** Number of days to look back from now */
  daysBack: z.number().int().positive().optional(),
  /** Start of time window (ISO8601) */
  timeMin: z.string().optional(),
  /** End of time window (ISO8601) */
  timeMax: z.string().optional(),
});

/**
 * Output format schema
 */
export const ActivityOutputSchema = z.object({
  /** Normalized activities from all requested providers/accounts */
  activities: z.array(UnifiedActivitySchema),
  /** Aggregated heatmap data */
  heatmap: z.array(HeatMapBucketSchema),
});

// Type exports inferred from schemas
export type ValidatedUnifiedActivity = z.infer<typeof UnifiedActivitySchema>;
export type ValidatedHeatMapBucket = z.infer<typeof HeatMapBucketSchema>;
export type ValidatedActivityOutput = z.infer<typeof ActivityOutputSchema>;
export type ValidatedProvider = z.infer<typeof ProviderSchema>;
export type ValidatedActivityType = z.infer<typeof ActivityTypeSchema>;

/**
 * Validate a single activity record
 * @throws ZodError with actionable error messages if validation fails
 */
export function validateActivity(data: unknown): ValidatedUnifiedActivity {
  return UnifiedActivitySchema.parse(data);
}

/**
 * Validate an activity record safely (returns result object)
 */
export function safeValidateActivity(data: unknown): z.SafeParseReturnType<unknown, ValidatedUnifiedActivity> {
  return UnifiedActivitySchema.safeParse(data);
}

/**
 * Validate a heatmap bucket
 * @throws ZodError with actionable error messages if validation fails
 */
export function validateHeatMapBucket(data: unknown): ValidatedHeatMapBucket {
  return HeatMapBucketSchema.parse(data);
}

/**
 * Validate a heatmap bucket safely (returns result object)
 */
export function safeValidateHeatMapBucket(data: unknown): z.SafeParseReturnType<unknown, ValidatedHeatMapBucket> {
  return HeatMapBucketSchema.safeParse(data);
}

/**
 * Validate complete activity output
 * @throws ZodError with actionable error messages if validation fails
 */
export function validateActivityOutput(data: unknown): ValidatedActivityOutput {
  return ActivityOutputSchema.parse(data);
}

/**
 * Validate activity output safely (returns result object)
 */
export function safeValidateActivityOutput(data: unknown): z.SafeParseReturnType<unknown, ValidatedActivityOutput> {
  return ActivityOutputSchema.safeParse(data);
}

/**
 * Format Zod errors into actionable messages
 */
export function formatValidationErrors(error: z.ZodError): string[] {
  return error.errors.map((err) => {
    const path = err.path.join('.');
    return path ? `${path}: ${err.message}` : err.message;
  });
}
