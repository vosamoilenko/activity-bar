/**
 * Provider identifiers supported by the activity aggregation system
 */
export type Provider = 'github' | 'gitlab' | 'azure-devops' | 'google-calendar';

/**
 * Activity types that can be normalized from provider-specific events
 */
export type ActivityType =
  | 'commit'
  | 'pull_request'
  | 'pull_request_comment'
  | 'issue'
  | 'issue_comment'
  | 'code_review'
  | 'pipeline'
  | 'meeting';

/**
 * Unified activity record normalized from any provider
 */
export interface UnifiedActivity {
  /** Unique identifier: `${provider}:${accountId}:${sourceId}` */
  id: string;
  /** Source provider */
  provider: Provider;
  /** Account identifier from config */
  accountId: string;
  /** Provider-specific identifier for the source entity */
  sourceId: string;
  /** Normalized activity type */
  type: ActivityType;
  /** ISO8601 UTC timestamp */
  timestamp: string;
  /** Activity title (optional) */
  title?: string;
  /** Brief summary or description (optional) */
  summary?: string;
  /** Participant usernames or emails (optional) */
  participants?: string[];
  /** Deep link URL to the source (optional) */
  url?: string;
}

/**
 * Per-provider activity count breakdown
 */
export interface ProviderBreakdown {
  github?: number;
  gitlab?: number;
  'azure-devops'?: number;
  'google-calendar'?: number;
}

/**
 * Aggregated activity count for a single day
 */
export interface HeatMapBucket {
  /** Date in YYYY-MM-DD format (UTC) */
  date: string;
  /** Total activity count for the day */
  count: number;
  /** Optional per-provider breakdown */
  breakdown?: ProviderBreakdown;
}

/**
 * Time window specification for fetching activities
 */
export interface FetchWindow {
  /** Number of days to look back from now */
  daysBack?: number;
  /** Start of time window (ISO8601) */
  timeMin?: string;
  /** End of time window (ISO8601) */
  timeMax?: string;
}

/**
 * Output format from the CLI runner
 */
export interface ActivityOutput {
  /** Normalized activities from all requested providers/accounts */
  activities: UnifiedActivity[];
  /** Aggregated heatmap data */
  heatmap: HeatMapBucket[];
}
