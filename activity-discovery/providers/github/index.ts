/**
 * GitHub provider for activity discovery
 *
 * Uses GitHub GraphQL API to fetch activity data with minimal fields.
 */

export * from './types.js';
export * from './fetch.js';
export { CONTRIBUTIONS_QUERY, ISSUE_COMMENTS_QUERY, VIEWER_LOGIN_QUERY } from './queries.js';
