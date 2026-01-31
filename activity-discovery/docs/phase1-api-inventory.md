# Phase 1 API Inventory

This document catalogs all API endpoints and queries used in the Activity Discovery module, with field-level justifications for what data is fetched.

## Table of Contents

- [Data Contracts](#data-contracts)
- [GitHub Provider](#github-provider)
- [GitLab Provider](#gitlab-provider)
- [Azure DevOps Provider](#azure-devops-provider)
- [Google Calendar Provider](#google-calendar-provider)
- [Known Limitations](#known-limitations)
- [Configuration Requirements](#configuration-requirements)

---

## Data Contracts

### UnifiedActivity

The normalized activity record used across all providers.

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `id` | string | Yes | Unique identifier: `{provider}:{accountId}:{type}-{sourceId}` |
| `provider` | enum | Yes | `github`, `gitlab`, `azure-devops`, `google-calendar` |
| `accountId` | string | Yes | Account identifier from config |
| `sourceId` | string | Yes | Provider-specific unique identifier |
| `type` | enum | Yes | Activity type (see below) |
| `timestamp` | string | Yes | ISO8601 UTC timestamp (ends with Z) |
| `title` | string | No | Short description for drill-down |
| `summary` | string | No | Extended description (max 200 chars) |
| `participants` | string[] | No | Usernames/emails of involved parties |
| `url` | string | No | Deep link to activity in provider |

**Activity Types:**
- `commit` - Git commits
- `pull_request` - PRs/MRs
- `pull_request_comment` - Comments on PRs/MRs
- `issue` - Issues/bugs/tasks
- `issue_comment` - Comments on issues
- `code_review` - PR/MR reviews
- `pipeline` - CI/CD runs
- `meeting` - Calendar events

### HeatMapBucket

Aggregated activity count per day.

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `date` | string | Yes | YYYY-MM-DD format |
| `count` | number | Yes | Total activities on that day |
| `breakdown` | object | No | Per-provider counts |

---

## GitHub Provider

### API Type

GraphQL (preferred per requirements)

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `https://api.github.com/graphql` | All queries |

### Required Scopes

- `read:user` - Access user profile
- `repo` - Access repositories (for contribution data)
- `read:org` - Organization membership (if needed)

### Queries

#### 1. Contributions Collection

Fetches commits, PRs, issues, and reviews from `contributionsCollection`.

```graphql
query($from: DateTime!, $to: DateTime!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      commitContributionsByRepository {
        repository { nameWithOwner }
        contributions(first: 100) {
          nodes { occurredAt commitCount }
        }
      }
      pullRequestContributions(first: 100) {
        nodes {
          pullRequest { id title url createdAt author { login } }
        }
      }
      issueContributions(first: 100) {
        nodes {
          issue { id title url createdAt author { login } }
        }
      }
      pullRequestReviewContributions(first: 100) {
        nodes {
          pullRequestReview {
            id url createdAt body
            pullRequest { number title }
            author { login }
          }
        }
      }
    }
  }
}
```

**Field Justifications:**

| Field | Use Case |
|-------|----------|
| `occurredAt` | Heatmap aggregation (timestamp) |
| `commitCount` | Title generation ("5 commits to repo") |
| `id` | Stable activity ID generation |
| `title` | Drill-down display |
| `url` | Deep link to GitHub |
| `createdAt` | Heatmap aggregation |
| `author.login` | Participants array |
| `body` | Summary (truncated to 200 chars) |

#### 2. Issue Comments

Issue comments are not included in `contributionsCollection` and require a separate query.

```graphql
query($from: DateTime!, $first: Int!, $after: String) {
  viewer {
    login
    issueComments(first: $first, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id url createdAt body
        issue { number title }
        author { login }
      }
    }
  }
}
```

### Pagination

- Uses GraphQL cursor-based pagination
- `first: 100` per page
- Stops at 10,000 activities (safety limit)

### Type Mapping

| GitHub Type | UnifiedActivity Type |
|-------------|---------------------|
| commit | `commit` |
| pullRequest | `pull_request` |
| issue | `issue` |
| issueComment | `issue_comment` |
| pullRequestReview | `code_review` |

---

## GitLab Provider

### API Type

REST (GraphQL insufficient for activity timeline)

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `{baseUrl}/api/v4/events` | User activity events |
| `{baseUrl}/api/v4/projects/{id}` | Project details for URL building |

### Required Scopes

- `read_api` - Read-only API access
- `read_user` - Read user profile

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `after` | YYYY-MM-DD | Start of time window |
| `before` | YYYY-MM-DD | End of time window |
| `scope` | `all` | All events (not just owned) |
| `per_page` | 100 | Items per page |

### Response Fields Used

```json
{
  "id": 12345,
  "action_name": "pushed",
  "target_type": "MergeRequest",
  "target_iid": 42,
  "target_title": "Add feature X",
  "created_at": "2024-01-15T10:30:00+02:00",
  "author_username": "alice",
  "project_id": 123,
  "push_data": {
    "commit_count": 3,
    "ref": "main",
    "commit_title": "feat: add endpoint"
  },
  "note": {
    "id": 789,
    "body": "Comment text...",
    "noteable_type": "MergeRequest",
    "noteable_iid": 42
  }
}
```

**Field Justifications:**

| Field | Use Case |
|-------|----------|
| `id` | Stable activity ID |
| `action_name` | Type mapping |
| `target_type` | Type mapping refinement |
| `target_title` | Drill-down title |
| `created_at` | Heatmap aggregation |
| `author_username` | Participants array |
| `project_id` | URL construction |
| `push_data.*` | Title/summary for commits |
| `note.*` | Comment details |

### Pagination

- Page-based: `page=1&per_page=100`
- Max 10 pages (1000 events)

### Type Mapping

| GitLab Action:Target | UnifiedActivity Type |
|---------------------|---------------------|
| pushed | `commit` |
| created:MergeRequest | `pull_request` |
| merged:MergeRequest | `pull_request` |
| approved:MergeRequest | `code_review` |
| created:Issue | `issue` |
| commented (MR) | `pull_request_comment` |
| commented (Issue) | `issue_comment` |

---

## Azure DevOps Provider

### API Type

REST (no GraphQL available)

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `dev.azure.com/{org}/{project}/_apis/git/pullrequests` | Pull requests |
| `dev.azure.com/{org}/{project}/_apis/git/repositories/{repo}/commits` | Commits |
| `dev.azure.com/{org}/_apis/wit/wiql` | Work item query |
| `dev.azure.com/{org}/_apis/wit/workitems` | Work item details |
| `dev.azure.com/{org}/{project}/_apis/git/repositories` | Repository list |

### Authentication

Basic Auth with Personal Access Token (PAT):
```
Authorization: Basic base64(:{token})
```

### Required Scopes

- `Code (Read)` - Repository and PR access
- `Work Items (Read)` - Work item access

### Parameters

#### Pull Requests
| Parameter | Value |
|-----------|-------|
| `searchCriteria.status` | `all` |
| `$top` | 100 |
| `api-version` | 7.0 |

#### Commits
| Parameter | Value |
|-----------|-------|
| `searchCriteria.fromDate` | ISO8601 |
| `searchCriteria.toDate` | ISO8601 |
| `$top` | 100 |

#### Work Items (WIQL)
```sql
SELECT [System.Id] FROM WorkItems
WHERE [System.ChangedDate] >= '{date}'
  AND [System.TeamProject] = '{project}'
ORDER BY [System.ChangedDate] DESC
```

### Response Fields Used

**Pull Request:**
```json
{
  "pullRequestId": 123,
  "title": "Add feature",
  "creationDate": "2024-01-15T10:00:00Z",
  "closedDate": null,
  "createdBy": { "displayName": "Alice" },
  "repository": {
    "name": "repo",
    "project": { "name": "Project" }
  }
}
```

**Commit:**
```json
{
  "commitId": "abc123...",
  "comment": "feat: add endpoint\n\nDescription...",
  "author": {
    "name": "Alice",
    "date": "2024-01-15T10:00:00Z"
  }
}
```

**Work Item:**
```json
{
  "id": 789,
  "fields": {
    "System.Title": "Fix bug",
    "System.WorkItemType": "Bug",
    "System.CreatedDate": "2024-01-15T09:00:00Z",
    "System.ChangedDate": "2024-01-15T12:00:00Z",
    "System.CreatedBy": { "displayName": "Alice" }
  }
}
```

### Pagination

- PRs: No built-in date filter; client-side filtering
- Commits: API supports date range
- Work Items: WIQL query + batch fetch by IDs

### Type Mapping

| Azure DevOps Type | UnifiedActivity Type |
|-------------------|---------------------|
| Pull Request | `pull_request` |
| Commit | `commit` |
| Bug/Task/UserStory/Issue | `issue` |

---

## Google Calendar Provider

### API Type

REST

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `oauth2.googleapis.com/token` | Token refresh |
| `googleapis.com/calendar/v3/calendars/{id}/events` | Event list |

### Authentication

OAuth 2.0 with refresh token:
```
Authorization: Bearer {access_token}
```

### Required Scopes

- `https://www.googleapis.com/auth/calendar.readonly`

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `timeMin` | ISO8601 | Start of window |
| `timeMax` | ISO8601 | End of window |
| `singleEvents` | true | Expand recurring events |
| `orderBy` | startTime | Chronological order |
| `maxResults` | 250 | Items per page |
| `fields` | items(...) | Minimal fields only |

### Fields Parameter

```
items(id,summary,description,start,end,attendees,organizer,htmlLink,status,created,updated),nextPageToken
```

### Response Fields Used

```json
{
  "id": "event123",
  "summary": "Team Standup",
  "description": "Daily sync...",
  "status": "confirmed",
  "htmlLink": "https://calendar.google.com/...",
  "start": {
    "dateTime": "2024-01-15T09:00:00-08:00",
    "date": "2024-01-15"
  },
  "organizer": {
    "email": "alice@example.com",
    "self": false
  },
  "attendees": [
    { "email": "bob@example.com", "responseStatus": "accepted", "self": false }
  ]
}
```

**Field Justifications:**

| Field | Use Case |
|-------|----------|
| `id` | Stable activity ID |
| `summary` | Drill-down title |
| `description` | Summary (truncated) |
| `start.dateTime/date` | Heatmap aggregation |
| `htmlLink` | Deep link to calendar |
| `organizer.email` | Participants (if not self) |
| `attendees[].email` | Participants (exclude self, declined) |
| `status` | Filter cancelled events |

### Pagination

- Token-based: `pageToken`
- Max 1000 events (safety limit)

### Type Mapping

| Calendar Event | UnifiedActivity Type |
|----------------|---------------------|
| Any event | `meeting` |

---

## Known Limitations

### GitHub

1. **Commit granularity**: `contributionsCollection` provides daily commit counts per repository, not individual commit details. Displayed as "N commits to repo".

2. **Issue comments pagination**: No time-based filter available; must paginate through all comments and filter client-side.

3. **Private repos**: Requires `repo` scope; without it, only public activity is visible.

### GitLab

1. **Date format**: Events API uses YYYY-MM-DD format, not full ISO8601. Time portion is ignored.

2. **Push events**: Contain commit count, not individual commits. Similar to GitHub contributions.

3. **Project fetching**: Each unique project_id requires a separate API call to get path_with_namespace for URL building.

### Azure DevOps

1. **PR date filtering**: No server-side date filter for PRs; must fetch all and filter client-side.

2. **Repository iteration**: Must iterate through repositories to get commits. Limited to 10 repos per project to avoid over-fetching.

3. **Work items**: Require two-step fetch (WIQL query for IDs, then batch fetch for details).

### Google Calendar

1. **All-day events**: Use `date` field instead of `dateTime`. Normalized to noon UTC.

2. **Recurring events**: `singleEvents=true` expands them but loses recurrence rule information.

3. **Declined events**: Filtered out by checking `responseStatus !== 'declined'`.

---

## Configuration Requirements

### config.json Structure

```json
{
  "providers": {
    "github": {
      "accounts": [
        {
          "id": "github-personal",
          "token": "<GITHUB_PAT>",
          "description": "Personal GitHub"
        }
      ]
    },
    "gitlab": {
      "accounts": [
        {
          "id": "gitlab-cloud",
          "baseUrl": "https://gitlab.com",
          "token": "<GITLAB_PAT>",
          "description": "GitLab.com"
        },
        {
          "id": "gitlab-self-hosted",
          "baseUrl": "https://gitlab.company.com",
          "token": "<SELF_HOSTED_PAT>",
          "description": "Self-hosted GitLab"
        }
      ]
    },
    "azure-devops": {
      "accounts": [
        {
          "id": "azure-org1",
          "organization": "<ORG_NAME>",
          "projects": ["Project1", "Project2"],
          "token": "<AZURE_PAT>",
          "description": "Azure DevOps"
        }
      ]
    },
    "google-calendar": {
      "accounts": [
        {
          "id": "google-personal",
          "credentials": {
            "clientId": "<CLIENT_ID>",
            "clientSecret": "<CLIENT_SECRET>",
            "refreshToken": "<REFRESH_TOKEN>"
          },
          "calendarIds": ["primary", "work@group.calendar.google.com"],
          "description": "Personal Google"
        }
      ]
    }
  }
}
```

### Per-Provider Requirements

| Provider | Required Config |
|----------|----------------|
| GitHub | `id`, `token` |
| GitLab | `id`, `baseUrl`, `token` |
| Azure DevOps | `id`, `organization`, `projects[]`, `token` |
| Google Calendar | `id`, `credentials.*`, `calendarIds[]` |

### Self-Hosted GitLab

For self-hosted GitLab instances:

1. Set `baseUrl` to your instance URL (e.g., `https://gitlab.company.com`)
2. Generate a Personal Access Token with `read_api` and `read_user` scopes
3. Ensure API v4 is enabled on the instance

### Multiple Accounts

Each provider supports multiple accounts:

```json
{
  "github": {
    "accounts": [
      { "id": "github-personal", "token": "..." },
      { "id": "github-work", "token": "..." }
    ]
  }
}
```

Use `--account <filter>` to run specific accounts:
- `--account personal` matches `github-personal`, `gitlab-personal`
- `--account github-personal` matches exact ID
