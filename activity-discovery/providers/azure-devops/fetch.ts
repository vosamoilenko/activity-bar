/**
 * Azure DevOps provider fetch implementation
 *
 * Uses Azure DevOps REST API to fetch activity data with minimal fields.
 * Supports multiple organizations and projects per account.
 */

import type { UnifiedActivity, FetchWindow } from '../../schemas/index.js';
import type {
  AzureDevOpsAccountConfig,
  AzureDevOpsFetchOptions,
  AzurePullRequest,
  AzureCommit,
  AzurePush,
  AzureWorkItem,
  AzureWiqlResult,
} from './types.js';

const AZURE_API_VERSION = '7.0';

/**
 * Execute a REST API request against Azure DevOps
 */
async function fetchAPI<T>(
  organization: string,
  token: string,
  endpoint: string,
  project?: string,
  params: Record<string, string> = {}
): Promise<T> {
  const baseUrl = project
    ? `https://dev.azure.com/${organization}/${project}/_apis${endpoint}`
    : `https://dev.azure.com/${organization}/_apis${endpoint}`;

  const url = new URL(baseUrl);
  url.searchParams.set('api-version', AZURE_API_VERSION);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url.toString(), {
    headers: {
      Authorization: `Basic ${Buffer.from(`:${token}`).toString('base64')}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`Azure DevOps API error: ${response.status} ${response.statusText}`);
  }

  return response.json() as Promise<T>;
}

/**
 * Execute a POST request (for WIQL queries)
 */
async function postAPI<T>(
  organization: string,
  token: string,
  endpoint: string,
  project: string,
  body: unknown
): Promise<T> {
  const url = new URL(`https://dev.azure.com/${organization}/${project}/_apis${endpoint}`);
  url.searchParams.set('api-version', AZURE_API_VERSION);

  const response = await fetch(url.toString(), {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`:${token}`).toString('base64')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Azure DevOps API error: ${response.status} ${response.statusText}`);
  }

  return response.json() as Promise<T>;
}

/**
 * Build time window for Azure DevOps API
 */
function buildTimeRange(window: FetchWindow): { minDate: string; maxDate: string } {
  if (window.timeMin && window.timeMax) {
    return {
      minDate: window.timeMin,
      maxDate: window.timeMax,
    };
  }

  const now = new Date();
  const daysBack = window.daysBack ?? 30;
  const minDate = new Date(now.getTime() - daysBack * 24 * 60 * 60 * 1000);

  return {
    minDate: minDate.toISOString(),
    maxDate: now.toISOString(),
  };
}

/**
 * Build URL for Azure DevOps Pull Request
 */
function buildPRUrl(organization: string, project: string, repoName: string, prId: number): string {
  return `https://dev.azure.com/${organization}/${project}/_git/${repoName}/pullrequest/${prId}`;
}

/**
 * Build URL for Azure DevOps Work Item
 */
function buildWorkItemUrl(organization: string, project: string, workItemId: number): string {
  return `https://dev.azure.com/${organization}/${project}/_workitems/edit/${workItemId}`;
}

/**
 * Normalize Azure DevOps Pull Request to UnifiedActivity
 */
function normalizePullRequest(
  pr: AzurePullRequest,
  accountId: string,
  organization: string
): UnifiedActivity {
  const timestamp = pr.closedDate ?? pr.creationDate;
  const sourceRef = stripBranchRef(pr.sourceRefName);
  const targetRef = stripBranchRef(pr.targetRefName);

  return {
    id: `azure-devops:${accountId}:pr-${pr.pullRequestId}`,
    provider: 'azure-devops',
    accountId,
    sourceId: String(pr.pullRequestId),
    type: 'pull_request',
    timestamp: timestamp.endsWith('Z') ? timestamp : new Date(timestamp).toISOString(),
    title: pr.title,
    url: buildPRUrl(organization, pr.repository.project.name, pr.repository.name, pr.pullRequestId),
    participants: [pr.createdBy.displayName],
    sourceRef,
    targetRef,
    rawEventType: `pull_request:${pr.status}`,
  };
}

/**
 * Normalize Azure DevOps Commit to UnifiedActivity
 */
function normalizeCommit(
  commit: AzureCommit,
  accountId: string,
  organization: string,
  project: string,
  repoName: string,
  branchName?: string
): UnifiedActivity {
  const timestamp = commit.author.date;

  return {
    id: `azure-devops:${accountId}:commit-${commit.commitId.slice(0, 8)}`,
    provider: 'azure-devops',
    accountId,
    sourceId: commit.commitId,
    type: 'commit',
    timestamp: timestamp.endsWith('Z') ? timestamp : new Date(timestamp).toISOString(),
    title: commit.comment.split('\n')[0].slice(0, 100),
    summary: commit.comment.length > 100 ? commit.comment.slice(0, 200) : undefined,
    url: `https://dev.azure.com/${organization}/${project}/_git/${repoName}/commit/${commit.commitId}`,
    participants: [commit.author.name],
    sourceRef: branchName,
    rawEventType: 'commit',
  };
}

/**
 * Normalize Azure DevOps Work Item to UnifiedActivity
 */
function normalizeWorkItem(
  workItem: AzureWorkItem,
  accountId: string,
  organization: string,
  project: string
): UnifiedActivity {
  const fields = workItem.fields;
  const workItemType = fields['System.WorkItemType'];

  // Map work item type to activity type
  let activityType: 'issue' | 'pipeline' = 'issue';
  if (workItemType === 'Bug' || workItemType === 'Issue' || workItemType === 'Task' || workItemType === 'User Story') {
    activityType = 'issue';
  }

  const timestamp = fields['System.ChangedDate'] ?? fields['System.CreatedDate'];

  return {
    id: `azure-devops:${accountId}:wi-${workItem.id}`,
    provider: 'azure-devops',
    accountId,
    sourceId: String(workItem.id),
    type: activityType,
    timestamp: timestamp.endsWith('Z') ? timestamp : new Date(timestamp).toISOString(),
    title: `[${workItemType}] ${fields['System.Title']}`,
    url: buildWorkItemUrl(organization, project, workItem.id),
    participants: [fields['System.CreatedBy'].displayName],
    rawEventType: `work_item:${workItemType}`,
  };
}

/**
 * Normalize Azure ref name to branch name
 */
function stripBranchRef(refName?: string): string | undefined {
  if (!refName) return undefined;
  return refName.replace(/^refs\/heads\//, '');
}

/**
 * Fetch pull requests for a project
 */
async function fetchPullRequests(
  organization: string,
  project: string,
  token: string,
  minDate: string
): Promise<AzurePullRequest[]> {
  type PRResponse = { value: AzurePullRequest[] };

  const response = await fetchAPI<PRResponse>(
    organization,
    token,
    '/git/pullrequests',
    project,
    {
      'searchCriteria.status': 'all',
      '$top': '100',
    }
  );

  // Filter by date client-side (API doesn't support date filter directly)
  const minDateTime = new Date(minDate).getTime();
  return response.value.filter((pr) => {
    const prDate = new Date(pr.closedDate ?? pr.creationDate).getTime();
    return prDate >= minDateTime;
  });
}

/**
 * Fetch commits for a repository
 */
async function fetchCommits(
  organization: string,
  project: string,
  repoId: string,
  token: string,
  minDate: string,
  maxDate: string
): Promise<AzureCommit[]> {
  type CommitResponse = { value: AzureCommit[] };

  const response = await fetchAPI<CommitResponse>(
    organization,
    token,
    `/git/repositories/${repoId}/commits`,
    project,
    {
      'searchCriteria.fromDate': minDate,
      'searchCriteria.toDate': maxDate,
      '$top': '100',
    }
  );

  return response.value;
}

/**
 * Fetch pushes for a repository (used to map commits to branch names)
 */
async function fetchPushes(
  organization: string,
  project: string,
  repoId: string,
  token: string,
  minDate: string,
  maxDate: string
): Promise<AzurePush[]> {
  type PushResponse = { value: AzurePush[] };

  const response = await fetchAPI<PushResponse>(
    organization,
    token,
    `/git/repositories/${repoId}/pushes`,
    project,
    {
      'searchCriteria.fromDate': minDate,
      'searchCriteria.toDate': maxDate,
      'searchCriteria.includeRefUpdates': 'true',
      '$top': '100',
    }
  );

  return response.value;
}

function buildCommitBranchMap(pushes: AzurePush[]): Map<string, string> {
  const map = new Map<string, string>();
  for (const push of pushes) {
    const branchName = normalizeBranchName(push.refUpdates);
    if (!branchName) continue;
    for (const commit of push.commits ?? []) {
      map.set(commit.commitId.toLowerCase(), branchName);
    }
  }
  return map;
}

function normalizeBranchName(
  refUpdates?: Array<{ name?: string }>
): string | undefined {
  if (!refUpdates || refUpdates.length === 0) return undefined;
  const headRef = refUpdates.find((ref) => ref.name?.startsWith('refs/heads/'));
  const refName = headRef?.name ?? refUpdates[0].name;
  return stripBranchRef(refName);
}

/**
 * Fetch work items modified in time range
 */
async function fetchWorkItems(
  organization: string,
  project: string,
  token: string,
  minDate: string
): Promise<AzureWorkItem[]> {
  // Use WIQL to query work items changed since minDate
  const wiql = {
    query: `SELECT [System.Id] FROM WorkItems WHERE [System.ChangedDate] >= '${minDate.split('T')[0]}' AND [System.TeamProject] = '${project}' ORDER BY [System.ChangedDate] DESC`,
  };

  const queryResult = await postAPI<AzureWiqlResult>(
    organization,
    token,
    '/wit/wiql',
    project,
    wiql
  );

  if (queryResult.workItems.length === 0) {
    return [];
  }

  // Fetch work item details (batch)
  const ids = queryResult.workItems.slice(0, 100).map((wi) => wi.id).join(',');
  type WorkItemsResponse = { value: AzureWorkItem[] };

  const response = await fetchAPI<WorkItemsResponse>(
    organization,
    token,
    `/wit/workitems`,
    undefined,
    {
      ids,
      fields: 'System.Id,System.Title,System.WorkItemType,System.State,System.CreatedDate,System.ChangedDate,System.CreatedBy,System.AssignedTo',
    }
  );

  return response.value;
}

/**
 * Fetch repositories for a project
 */
async function fetchRepositories(
  organization: string,
  project: string,
  token: string
): Promise<Array<{ id: string; name: string }>> {
  type RepoResponse = { value: Array<{ id: string; name: string }> };

  const response = await fetchAPI<RepoResponse>(
    organization,
    token,
    '/git/repositories',
    project
  );

  return response.value;
}

/**
 * Fetch activities for a single Azure DevOps account
 */
export async function fetchAzureDevOpsActivities(
  options: AzureDevOpsFetchOptions
): Promise<UnifiedActivity[]> {
  const { account, window } = options;
  const { minDate, maxDate } = buildTimeRange(window);
  const activities: UnifiedActivity[] = [];

  for (const project of account.projects) {
    try {
      // Fetch pull requests
      const pullRequests = await fetchPullRequests(
        account.organization,
        project,
        account.token,
        minDate
      );

      for (const pr of pullRequests) {
        activities.push(normalizePullRequest(pr, account.id, account.organization));
      }

      // Fetch commits from each repository
      const repos = await fetchRepositories(account.organization, project, account.token);
      for (const repo of repos.slice(0, 10)) { // Limit repos to avoid over-fetch
        try {
          let commitBranchMap = new Map<string, string>();
          try {
            const pushes = await fetchPushes(
              account.organization,
              project,
              repo.id,
              account.token,
              minDate,
              maxDate
            );
            commitBranchMap = buildCommitBranchMap(pushes);
          } catch {
            // Skip branch mapping if pushes are unavailable
          }

          const commits = await fetchCommits(
            account.organization,
            project,
            repo.id,
            account.token,
            minDate,
            maxDate
          );

          for (const commit of commits) {
            const branchName = commitBranchMap.get(commit.commitId.toLowerCase());
            activities.push(normalizeCommit(
              commit,
              account.id,
              account.organization,
              project,
              repo.name,
              branchName
            ));
          }
        } catch {
          // Skip if we can't fetch commits for this repo
        }
      }

      // Fetch work items
      const workItems = await fetchWorkItems(
        account.organization,
        project,
        account.token,
        minDate
      );

      for (const workItem of workItems) {
        activities.push(normalizeWorkItem(workItem, account.id, account.organization, project));
      }
    } catch (error) {
      console.error(`Azure DevOps: Failed to fetch activities for project ${project}:`, error);
    }
  }

  // Sort by timestamp descending
  activities.sort((a, b) => b.timestamp.localeCompare(a.timestamp));

  return activities;
}

/**
 * Fetch activities for multiple Azure DevOps accounts
 */
export async function fetchAzureDevOpsActivitiesForAccounts(
  accounts: AzureDevOpsAccountConfig[],
  window: FetchWindow
): Promise<Map<string, UnifiedActivity[]>> {
  const results = new Map<string, UnifiedActivity[]>();

  for (const account of accounts) {
    try {
      const activities = await fetchAzureDevOpsActivities({ account, window });
      results.set(account.id, activities);
    } catch (error) {
      console.error(`Azure DevOps: Failed to fetch activities for account ${account.id}:`, error);
      results.set(account.id, []);
    }
  }

  return results;
}
