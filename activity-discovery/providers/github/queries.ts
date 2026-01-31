/**
 * GitHub GraphQL queries for activity discovery
 *
 * Queries are designed to fetch ONLY minimal fields required for:
 * - UnifiedActivity schema (id, timestamp, type, title, url, participants)
 * - Heatmap aggregation (timestamp, provider)
 * - Minimal drill-down (title, summary, url)
 */

/**
 * Contributions query for a given time window
 *
 * Fetches:
 * - Commit contributions (grouped by repository)
 * - Pull request contributions
 * - Issue contributions
 * - Pull request review contributions
 *
 * Time window is controlled by `from` and `to` variables (ISO8601 DateTime)
 */
export const CONTRIBUTIONS_QUERY = `
query GetContributions($from: DateTime!, $to: DateTime!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      commitContributionsByRepository(maxRepositories: 100) {
        repository {
          nameWithOwner
        }
        contributions(first: 100) {
          nodes {
            commitCount
            occurredAt
          }
        }
      }
      pullRequestContributions(first: 100) {
        nodes {
          pullRequest {
            id
            number
            title
            createdAt
            url
            author {
              login
            }
          }
        }
      }
      issueContributions(first: 100) {
        nodes {
          issue {
            id
            number
            title
            createdAt
            url
            author {
              login
            }
          }
        }
      }
      pullRequestReviewContributions(first: 100) {
        nodes {
          pullRequestReview {
            id
            body
            createdAt
            url
            author {
              login
            }
            pullRequest {
              number
              title
            }
          }
        }
      }
    }
  }
}
`;

/**
 * Query for issue comments (not included in contributionsCollection)
 *
 * Fetches issue comments made by the authenticated user.
 * Uses pagination to handle users with many comments.
 */
export const ISSUE_COMMENTS_QUERY = `
query GetIssueComments($from: DateTime!, $first: Int!, $after: String) {
  viewer {
    login
    issueComments(first: $first, after: $after) {
      nodes {
        id
        body
        createdAt
        url
        author {
          login
        }
        issue {
          number
          title
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
`;

/**
 * Query to get recent commits from user's repositories
 *
 * This is a fallback/supplementary query when contributionsCollection
 * doesn't provide enough detail for individual commits.
 */
export const RECENT_COMMITS_QUERY = `
query GetRecentCommits($login: String!, $from: DateTime!, $to: DateTime!, $first: Int!) {
  user(login: $login) {
    repositories(first: 50, orderBy: {field: PUSHED_AT, direction: DESC}) {
      nodes {
        nameWithOwner
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: $first, since: $from, until: $to, author: {id: null}) {
                nodes {
                  oid
                  message
                  committedDate
                  url
                  author {
                    user {
                      login
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
`;

/**
 * Simple query to get the current user's login
 */
export const VIEWER_LOGIN_QUERY = `
query GetViewerLogin {
  viewer {
    login
  }
}
`;
