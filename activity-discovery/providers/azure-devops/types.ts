/**
 * Azure DevOps provider configuration and API types
 */

import type { FetchWindow } from '../../schemas/index.js';

/**
 * Azure DevOps account configuration
 */
export interface AzureDevOpsAccountConfig {
  /** Unique identifier for this account */
  id: string;
  /** Azure DevOps organization name */
  organization: string;
  /** Projects to fetch activities from */
  projects: string[];
  /** Personal Access Token */
  token: string;
  /** Optional description for this account */
  description?: string;
}

/**
 * Azure DevOps provider configuration
 */
export interface AzureDevOpsProviderConfig {
  accounts: AzureDevOpsAccountConfig[];
}

/**
 * Options for fetching Azure DevOps activities
 */
export interface AzureDevOpsFetchOptions {
  /** Account configuration to use */
  account: AzureDevOpsAccountConfig;
  /** Time window for fetching activities */
  window: FetchWindow;
}

/**
 * Azure DevOps Pull Request (minimal fields)
 * https://docs.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests
 */
export interface AzurePullRequest {
  pullRequestId: number;
  title: string;
  creationDate: string;
  closedDate?: string;
  status: 'active' | 'abandoned' | 'completed';
  sourceRefName?: string;
  targetRefName?: string;
  createdBy: {
    id: string;
    displayName: string;
    uniqueName: string;
  };
  repository: {
    id: string;
    name: string;
    project: {
      name: string;
    };
  };
}

/**
 * Azure DevOps Commit (minimal fields)
 * https://docs.microsoft.com/en-us/rest/api/azure/devops/git/commits/get-commits
 */
export interface AzureCommit {
  commitId: string;
  comment: string;
  author: {
    name: string;
    email: string;
    date: string;
  };
  committer: {
    name: string;
    email: string;
    date: string;
  };
  url: string;
  remoteUrl: string;
}

/**
 * Azure DevOps Push (minimal fields for branch mapping)
 * https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pushes/get-pushes
 */
export interface AzurePush {
  pushId?: number;
  date?: string;
  refUpdates?: Array<{
    name?: string;
  }>;
  commits?: Array<{
    commitId: string;
  }>;
}

/**
 * Azure DevOps Work Item (minimal fields)
 * https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/work-items/get-work-item
 */
export interface AzureWorkItem {
  id: number;
  fields: {
    'System.Title': string;
    'System.WorkItemType': string;
    'System.State': string;
    'System.CreatedDate': string;
    'System.ChangedDate': string;
    'System.CreatedBy': {
      displayName: string;
      uniqueName: string;
    };
    'System.AssignedTo'?: {
      displayName: string;
      uniqueName: string;
    };
  };
  url: string;
  _links: {
    html: {
      href: string;
    };
  };
}

/**
 * Azure DevOps Work Item Update
 * https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/updates/get-updates
 */
export interface AzureWorkItemUpdate {
  id: number;
  workItemId: number;
  rev: number;
  revisedDate: string;
  revisedBy: {
    displayName: string;
    uniqueName: string;
  };
  fields?: Record<string, { oldValue?: unknown; newValue?: unknown }>;
}

/**
 * Azure DevOps WIQL query result
 */
export interface AzureWiqlResult {
  workItems: Array<{
    id: number;
    url: string;
  }>;
}
