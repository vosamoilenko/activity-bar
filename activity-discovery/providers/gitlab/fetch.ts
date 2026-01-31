/**
 * GitLab provider fetch implementation
 *
 * Uses GitLab REST API to fetch activity data with minimal fields.
 * Supports both gitlab.com and self-hosted instances via configurable baseURL.
 */

import type { UnifiedActivity, FetchWindow, ActivityType } from '../../schemas/index.js';
import type {
  GitLabAccountConfig,
  GitLabFetchOptions,
  GitLabEvent,
  GitLabProject,
} from './types.js';
import { EVENT_TYPE_MAPPING } from './types.js';

/**
 * Execute a REST API request against GitLab
 */
async function fetchAPI<T>(
  baseUrl: string,
  token: string,
  endpoint: string,
  params: Record<string, string> = {}
): Promise<T> {
  const url = new URL(`/api/v4${endpoint}`, baseUrl);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url.toString(), {
    headers: {
      'PRIVATE-TOKEN': token,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`GitLab API error: ${response.status} ${response.statusText}`);
  }

  return response.json() as Promise<T>;
}

/**
 * Fetch all pages of a paginated endpoint
 */
async function fetchAllPages<T>(
  baseUrl: string,
  token: string,
  endpoint: string,
  params: Record<string, string> = {},
  maxPages: number = 10
): Promise<T[]> {
  const results: T[] = [];
  let page = 1;

  while (page <= maxPages) {
    const pageParams = { ...params, page: String(page), per_page: '100' };
    const pageResults = await fetchAPI<T[]>(baseUrl, token, endpoint, pageParams);

    if (pageResults.length === 0) {
      break;
    }

    results.push(...pageResults);
    page++;
  }

  return results;
}

/**
 * Build time window parameters for GitLab API
 */
function buildTimeParams(window: FetchWindow): { after: string; before: string } {
  if (window.timeMin && window.timeMax) {
    return {
      after: window.timeMin.split('T')[0],
      before: window.timeMax.split('T')[0],
    };
  }

  const now = new Date();
  const daysBack = window.daysBack ?? 30;
  const after = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);

  return {
    after: after.toISOString().split('T')[0],
    before: now.toISOString().split('T')[0],
  };
}

/**
 * Map GitLab event to ActivityType
 */
function mapEventToActivityType(event: GitLabEvent): ActivityType | null {
  // Handle push events
  if (event.action_name === 'pushed' && event.push_data) {
    return 'commit';
  }

  // Handle comment events
  if (event.action_name === 'commented') {
    if (event.note?.noteable_type === 'MergeRequest') {
      return 'pull_request_comment';
    }
    return 'issue_comment';
  }

  // Look up in mapping table
  const key = `${event.action_name}:${event.target_type ?? ''}`;
  const mappedType = EVENT_TYPE_MAPPING[key];

  if (mappedType) {
    return mappedType as ActivityType;
  }

  // Default mapping based on target type
  if (event.target_type === 'MergeRequest') {
    return 'pull_request';
  }
  if (event.target_type === 'Issue') {
    return 'issue';
  }

  return null;
}

/**
 * Build URL for GitLab event
 */
function buildEventUrl(
  baseUrl: string,
  event: GitLabEvent,
  projectPath?: string
): string | undefined {
  if (!projectPath) {
    return undefined;
  }

  const base = `${baseUrl}/${projectPath}`;

  if (event.target_type === 'MergeRequest' && event.target_iid) {
    return `${base}/-/merge_requests/${event.target_iid}`;
  }

  if (event.target_type === 'Issue' && event.target_iid) {
    return `${base}/-/issues/${event.target_iid}`;
  }

  if (event.action_name === 'pushed' && event.push_data?.commit_to) {
    return `${base}/-/commit/${event.push_data.commit_to}`;
  }

  if (event.note && event.note.noteable_iid) {
    if (event.note.noteable_type === 'MergeRequest') {
      return `${base}/-/merge_requests/${event.note.noteable_iid}#note_${event.note.id}`;
    }
    if (event.note.noteable_type === 'Issue') {
      return `${base}/-/issues/${event.note.noteable_iid}#note_${event.note.id}`;
    }
  }

  return undefined;
}

/**
 * Normalize a GitLab event to UnifiedActivity
 */
function normalizeEvent(
  event: GitLabEvent,
  accountId: string,
  baseUrl: string,
  projectPathMap: Map<number, string>
): UnifiedActivity | null {
  const activityType = mapEventToActivityType(event);

  if (!activityType) {
    return null;
  }

  const projectPath = event.project_id ? projectPathMap.get(event.project_id) : undefined;
  const url = buildEventUrl(baseUrl, event, projectPath);

  // Build title based on event type
  let title: string;
  let summary: string | undefined;

  if (event.action_name === 'pushed' && event.push_data) {
    const count = event.push_data.commit_count;
    const ref = event.push_data.ref;
    title = `${count} commit${count > 1 ? 's' : ''} to ${ref}`;
    summary = event.push_data.commit_title || undefined;
  } else if (event.note) {
    title = `Comment on ${event.note.noteable_type} #${event.note.noteable_iid ?? event.note.noteable_id}`;
    summary = event.note.body?.slice(0, 200) || undefined;
  } else {
    title = event.target_title ?? `${event.action_name} ${event.target_type ?? 'item'}`;
  }

  // Convert timestamp to UTC format
  const timestamp = event.created_at.endsWith('Z')
    ? event.created_at
    : new Date(event.created_at).toISOString();

  return {
    id: `gitlab:${accountId}:event-${event.id}`,
    provider: 'gitlab',
    accountId,
    sourceId: String(event.id),
    type: activityType,
    timestamp,
    title,
    summary,
    url,
    participants: [event.author_username],
  };
}

/**
 * Fetch activities for a single GitLab account
 */
export async function fetchGitLabActivities(
  options: GitLabFetchOptions
): Promise<UnifiedActivity[]> {
  const { account, window } = options;
  const { after, before } = buildTimeParams(window);

  // Fetch user events
  const events = await fetchAllPages<GitLabEvent>(
    account.baseUrl,
    account.token,
    '/events',
    { after, before, scope: 'all' }
  );

  // Get unique project IDs to fetch project paths for URLs
  const projectIds = new Set<number>();
  for (const event of events) {
    if (event.project_id) {
      projectIds.add(event.project_id);
    }
  }

  // Fetch project details for URL building
  const projectPathMap = new Map<number, string>();
  for (const projectId of projectIds) {
    try {
      const project = await fetchAPI<GitLabProject>(
        account.baseUrl,
        account.token,
        `/projects/${projectId}`
      );
      projectPathMap.set(projectId, project.path_with_namespace);
    } catch {
      // Skip if we can't fetch project details
    }
  }

  // Normalize events to activities
  const activities: UnifiedActivity[] = [];
  for (const event of events) {
    const activity = normalizeEvent(event, account.id, account.baseUrl, projectPathMap);
    if (activity) {
      activities.push(activity);
    }
  }

  // Sort by timestamp descending
  activities.sort((a, b) => b.timestamp.localeCompare(a.timestamp));

  return activities;
}

/**
 * Fetch activities for multiple GitLab accounts
 */
export async function fetchGitLabActivitiesForAccounts(
  accounts: GitLabAccountConfig[],
  window: FetchWindow
): Promise<Map<string, UnifiedActivity[]>> {
  const results = new Map<string, UnifiedActivity[]>();

  for (const account of accounts) {
    try {
      const activities = await fetchGitLabActivities({ account, window });
      results.set(account.id, activities);
    } catch (error) {
      console.error(`GitLab: Failed to fetch activities for account ${account.id}:`, error);
      results.set(account.id, []);
    }
  }

  return results;
}
