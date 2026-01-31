/**
 * Normalization utility functions
 *
 * Common helpers for normalizing provider data to UnifiedActivity format.
 */

import type { Provider } from '../schemas/index.js';

/**
 * Normalize a timestamp to UTC ISO8601 format
 *
 * Handles various input formats:
 * - Already UTC (ends with Z): pass through
 * - With timezone offset (+/-HH:MM): convert to UTC
 * - Date only (YYYY-MM-DD): use noon UTC
 * - Other formats: parse and convert
 *
 * @param timestamp - Input timestamp string
 * @returns ISO8601 UTC timestamp (ending with Z)
 */
export function normalizeToUTC(timestamp: string): string {
  // Already UTC
  if (timestamp.endsWith('Z')) {
    return timestamp;
  }

  // Date only - use noon UTC
  if (/^\d{4}-\d{2}-\d{2}$/.test(timestamp)) {
    return `${timestamp}T12:00:00Z`;
  }

  // Parse and convert to ISO string
  const date = new Date(timestamp);
  if (isNaN(date.getTime())) {
    // Invalid date - return current time as fallback
    return new Date().toISOString();
  }

  return date.toISOString();
}

/**
 * Generate a stable activity ID
 *
 * Format: {provider}:{accountId}:{type}-{sourceId}
 *
 * @param provider - Provider identifier
 * @param accountId - Account identifier
 * @param type - Activity type prefix (e.g., 'pr', 'commit', 'event')
 * @param sourceId - Provider-specific source identifier
 * @returns Stable activity ID
 */
export function generateActivityId(
  provider: Provider,
  accountId: string,
  type: string,
  sourceId: string
): string {
  return `${provider}:${accountId}:${type}-${sourceId}`;
}

/**
 * Truncate a string to a maximum length
 *
 * @param text - Input text
 * @param maxLength - Maximum length (default: 200)
 * @returns Truncated text or undefined if empty
 */
export function truncateText(text: string | undefined | null, maxLength: number = 200): string | undefined {
  if (!text) {
    return undefined;
  }

  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return undefined;
  }

  if (trimmed.length <= maxLength) {
    return trimmed;
  }

  return trimmed.slice(0, maxLength);
}

/**
 * Extract first line from multiline text
 *
 * @param text - Input text
 * @param maxLength - Maximum length for the first line (default: 100)
 * @returns First line, truncated if necessary
 */
export function extractFirstLine(text: string | undefined | null, maxLength: number = 100): string | undefined {
  if (!text) {
    return undefined;
  }

  const firstLine = text.split('\n')[0].trim();
  if (firstLine.length === 0) {
    return undefined;
  }

  if (firstLine.length <= maxLength) {
    return firstLine;
  }

  return firstLine.slice(0, maxLength);
}

/**
 * Deduplicate an array of strings while preserving order
 *
 * @param items - Array of strings
 * @returns Deduplicated array
 */
export function deduplicateStrings(items: string[]): string[] {
  return [...new Set(items)];
}

/**
 * Extract date portion from ISO8601 timestamp
 *
 * @param timestamp - ISO8601 timestamp
 * @returns Date in YYYY-MM-DD format
 */
export function extractDateFromTimestamp(timestamp: string): string {
  return timestamp.slice(0, 10);
}
