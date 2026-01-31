/**
 * Type mapping tables for each provider
 *
 * These tables document and enforce the mapping from provider-specific
 * event types to the unified ActivityType enum.
 */

import type { ActivityType, Provider } from '../schemas/index.js';
import type { ProviderTypeMapping, TypeMappingEntry } from './types.js';

/**
 * GitHub type mappings
 */
export const GITHUB_TYPE_MAPPINGS: TypeMappingEntry[] = [
  { source: 'commit', target: 'commit', description: 'Git commits (via contributionsCollection)' },
  { source: 'pullRequest', target: 'pull_request', description: 'Pull request created/updated' },
  { source: 'issue', target: 'issue', description: 'Issue created/updated' },
  { source: 'issueComment', target: 'issue_comment', description: 'Comment on issue' },
  { source: 'pullRequestReview', target: 'code_review', description: 'PR review submitted' },
];

/**
 * GitLab type mappings
 */
export const GITLAB_TYPE_MAPPINGS: TypeMappingEntry[] = [
  { source: 'pushed', target: 'commit', description: 'Git push event' },
  { source: 'created:MergeRequest', target: 'pull_request', description: 'MR created' },
  { source: 'merged:MergeRequest', target: 'pull_request', description: 'MR merged' },
  { source: 'closed:MergeRequest', target: 'pull_request', description: 'MR closed' },
  { source: 'reopened:MergeRequest', target: 'pull_request', description: 'MR reopened' },
  { source: 'approved:MergeRequest', target: 'code_review', description: 'MR approved' },
  { source: 'created:Issue', target: 'issue', description: 'Issue created' },
  { source: 'closed:Issue', target: 'issue', description: 'Issue closed' },
  { source: 'reopened:Issue', target: 'issue', description: 'Issue reopened' },
  { source: 'commented:MergeRequest', target: 'pull_request_comment', description: 'Comment on MR' },
  { source: 'commented:Issue', target: 'issue_comment', description: 'Comment on issue' },
];

/**
 * Azure DevOps type mappings
 */
export const AZURE_DEVOPS_TYPE_MAPPINGS: TypeMappingEntry[] = [
  { source: 'pullRequest', target: 'pull_request', description: 'Pull request' },
  { source: 'commit', target: 'commit', description: 'Git commit' },
  { source: 'workItem:Bug', target: 'issue', description: 'Bug work item' },
  { source: 'workItem:Task', target: 'issue', description: 'Task work item' },
  { source: 'workItem:User Story', target: 'issue', description: 'User Story work item' },
  { source: 'workItem:Issue', target: 'issue', description: 'Issue work item' },
];

/**
 * Google Calendar type mappings
 */
export const GOOGLE_CALENDAR_TYPE_MAPPINGS: TypeMappingEntry[] = [
  { source: 'event', target: 'meeting', description: 'Calendar event' },
  { source: 'event:timed', target: 'meeting', description: 'Timed calendar event' },
  { source: 'event:allDay', target: 'meeting', description: 'All-day calendar event' },
];

/**
 * All provider type mappings
 */
export const PROVIDER_TYPE_MAPPINGS: ProviderTypeMapping[] = [
  { provider: 'github', mappings: GITHUB_TYPE_MAPPINGS },
  { provider: 'gitlab', mappings: GITLAB_TYPE_MAPPINGS },
  { provider: 'azure-devops', mappings: AZURE_DEVOPS_TYPE_MAPPINGS },
  { provider: 'google-calendar', mappings: GOOGLE_CALENDAR_TYPE_MAPPINGS },
];

/**
 * Get type mapping for a provider
 */
export function getProviderTypeMappings(provider: Provider): TypeMappingEntry[] {
  const mapping = PROVIDER_TYPE_MAPPINGS.find((m) => m.provider === provider);
  return mapping?.mappings ?? [];
}

/**
 * Get all source types that map to a given ActivityType for a provider
 */
export function getSourceTypesForActivityType(
  provider: Provider,
  activityType: ActivityType
): string[] {
  const mappings = getProviderTypeMappings(provider);
  return mappings.filter((m) => m.target === activityType).map((m) => m.source);
}

/**
 * Get the ActivityType for a provider source type
 */
export function mapSourceToActivityType(
  provider: Provider,
  sourceType: string
): ActivityType | null {
  const mappings = getProviderTypeMappings(provider);
  const mapping = mappings.find((m) => m.source === sourceType);
  return mapping?.target ?? null;
}
