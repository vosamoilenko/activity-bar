/**
 * Heatmap aggregation functions for UnifiedActivity
 *
 * Groups activities by UTC date and provides per-provider breakdowns.
 */

import type { UnifiedActivity, HeatMapBucket, ProviderBreakdown, Provider } from '../schemas/index.js';

/**
 * Options for heatmap aggregation
 */
export interface AggregationOptions {
  /** Include per-provider breakdown (default: true) */
  includeBreakdown?: boolean;
}

/**
 * Aggregate activities into heatmap buckets by UTC date
 *
 * - Groups activities by YYYY-MM-DD extracted from UTC timestamp
 * - Counts total activity per day
 * - Optionally provides per-provider breakdown
 * - Returns buckets sorted by date ascending
 *
 * @param activities - Array of UnifiedActivity records
 * @param options - Aggregation options
 * @returns Array of HeatMapBucket sorted by date
 */
export function aggregateToHeatmap(
  activities: UnifiedActivity[],
  options: AggregationOptions = {}
): HeatMapBucket[] {
  const { includeBreakdown = true } = options;
  const buckets = new Map<string, HeatMapBucket>();

  for (const activity of activities) {
    // Extract date in YYYY-MM-DD format from UTC timestamp
    // Timestamps are guaranteed to be ISO8601 UTC (ending with Z)
    const date = extractUTCDate(activity.timestamp);

    let bucket = buckets.get(date);
    if (!bucket) {
      bucket = {
        date,
        count: 0,
      };
      if (includeBreakdown) {
        bucket.breakdown = {};
      }
      buckets.set(date, bucket);
    }

    bucket.count++;

    if (includeBreakdown && bucket.breakdown) {
      bucket.breakdown[activity.provider] = (bucket.breakdown[activity.provider] ?? 0) + 1;
    }
  }

  // Sort by date ascending
  return Array.from(buckets.values()).sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Extract YYYY-MM-DD date from an ISO8601 UTC timestamp
 *
 * This function handles both direct string slicing (for ISO8601 format)
 * and Date parsing as a fallback for edge cases.
 *
 * @param timestamp - ISO8601 UTC timestamp (e.g., "2024-01-15T10:30:00Z")
 * @returns Date string in YYYY-MM-DD format
 */
export function extractUTCDate(timestamp: string): string {
  // ISO8601 UTC timestamps are in format: YYYY-MM-DDTHH:mm:ss.sssZ
  // The date portion is always the first 10 characters
  if (timestamp.endsWith('Z') && timestamp.length >= 10) {
    return timestamp.slice(0, 10);
  }

  // Fallback: parse and format using Date
  // This handles edge cases like different timezone offsets
  const date = new Date(timestamp);
  return date.toISOString().slice(0, 10);
}

/**
 * Merge multiple heatmap bucket arrays into one
 *
 * Useful when aggregating results from multiple provider runs.
 *
 * @param bucketArrays - Arrays of HeatMapBucket to merge
 * @returns Merged and sorted HeatMapBucket array
 */
export function mergeHeatmapBuckets(...bucketArrays: HeatMapBucket[][]): HeatMapBucket[] {
  const merged = new Map<string, HeatMapBucket>();

  for (const buckets of bucketArrays) {
    for (const bucket of buckets) {
      const existing = merged.get(bucket.date);
      if (!existing) {
        merged.set(bucket.date, {
          date: bucket.date,
          count: bucket.count,
          breakdown: bucket.breakdown ? { ...bucket.breakdown } : undefined,
        });
      } else {
        existing.count += bucket.count;

        if (bucket.breakdown && existing.breakdown) {
          for (const [provider, count] of Object.entries(bucket.breakdown)) {
            const p = provider as Provider;
            existing.breakdown[p] = (existing.breakdown[p] ?? 0) + (count ?? 0);
          }
        }
      }
    }
  }

  return Array.from(merged.values()).sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Get activity count for a specific date
 *
 * @param heatmap - Array of HeatMapBucket
 * @param date - Date in YYYY-MM-DD format
 * @returns Activity count for that date, or 0 if not found
 */
export function getCountForDate(heatmap: HeatMapBucket[], date: string): number {
  const bucket = heatmap.find((b) => b.date === date);
  return bucket?.count ?? 0;
}

/**
 * Get provider breakdown for a specific date
 *
 * @param heatmap - Array of HeatMapBucket
 * @param date - Date in YYYY-MM-DD format
 * @returns Provider breakdown for that date, or undefined if not found
 */
export function getBreakdownForDate(
  heatmap: HeatMapBucket[],
  date: string
): ProviderBreakdown | undefined {
  const bucket = heatmap.find((b) => b.date === date);
  return bucket?.breakdown;
}
