/**
 * GitLab provider configuration and API types
 */

import type { FetchWindow } from '../../schemas/index.js';

/**
 * GitLab account configuration
 */
export interface GitLabAccountConfig {
  /** Unique identifier for this account */
  id: string;
  /** GitLab instance base URL (e.g., https://gitlab.com or https://gitlab.your-company.com) */
  baseUrl: string;
  /** GitLab personal access token */
  token: string;
  /** Optional description for this account */
  description?: string;
}

/**
 * GitLab provider configuration
 */
export interface GitLabProviderConfig {
  accounts: GitLabAccountConfig[];
}

/**
 * Options for fetching GitLab activities
 */
export interface GitLabFetchOptions {
  /** Account configuration to use */
  account: GitLabAccountConfig;
  /** Time window for fetching activities */
  window: FetchWindow;
}

/**
 * GitLab event types from the Events API
 * https://docs.gitlab.com/ee/api/events.html
 */
export type GitLabEventAction =
  | 'pushed'
  | 'created'
  | 'updated'
  | 'closed'
  | 'reopened'
  | 'merged'
  | 'joined'
  | 'left'
  | 'commented'
  | 'approved'
  | 'accepted'
  | 'expired'
  | 'removed'
  | 'deleted'
  | 'destroyed';

export type GitLabEventTargetType =
  | 'Issue'
  | 'MergeRequest'
  | 'Note'
  | 'Milestone'
  | 'WikiPage'
  | 'Snippet'
  | 'Project'
  | 'DesignManagement::Design';

/**
 * GitLab Event from the Events API
 * Only minimal fields needed for UnifiedActivity
 */
export interface GitLabEvent {
  id: number;
  action_name: GitLabEventAction;
  created_at: string;
  target_id: number | null;
  target_iid: number | null;
  target_type: GitLabEventTargetType | null;
  target_title: string | null;
  author_id: number;
  author_username: string;
  project_id: number | null;
  push_data?: {
    commit_count: number;
    action: string;
    ref_type: string;
    commit_from: string | null;
    commit_to: string | null;
    ref: string;
    commit_title: string | null;
  };
  note?: {
    id: number;
    body: string;
    noteable_type: string;
    noteable_id: number;
    noteable_iid: number | null;
  };
}

/**
 * GitLab Project (minimal fields)
 */
export interface GitLabProject {
  id: number;
  name: string;
  name_with_namespace: string;
  path_with_namespace: string;
  web_url: string;
}

/**
 * GitLab Merge Request (minimal fields)
 */
export interface GitLabMergeRequest {
  id: number;
  iid: number;
  title: string;
  created_at: string;
  web_url: string;
  author: {
    id: number;
    username: string;
  };
}

/**
 * GitLab Issue (minimal fields)
 */
export interface GitLabIssue {
  id: number;
  iid: number;
  title: string;
  created_at: string;
  web_url: string;
  author: {
    id: number;
    username: string;
  };
}

/**
 * Mapping from GitLab event action + target to ActivityType
 */
export const EVENT_TYPE_MAPPING: Record<string, string> = {
  // Push events
  'pushed:': 'commit',

  // Merge Request events
  'created:MergeRequest': 'pull_request',
  'updated:MergeRequest': 'pull_request',
  'closed:MergeRequest': 'pull_request',
  'reopened:MergeRequest': 'pull_request',
  'merged:MergeRequest': 'pull_request',
  'approved:MergeRequest': 'code_review',

  // Issue events
  'created:Issue': 'issue',
  'updated:Issue': 'issue',
  'closed:Issue': 'issue',
  'reopened:Issue': 'issue',

  // Comment events
  'commented:Note': 'issue_comment',
  'commented:MergeRequest': 'pull_request_comment',
  'commented:Issue': 'issue_comment',
};
