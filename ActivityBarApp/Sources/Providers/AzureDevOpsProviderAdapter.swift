import Foundation
import Core

/// Azure DevOps provider adapter implementing activity fetching via REST API v7.0
///
/// Ported from activity-discovery/providers/azure-devops/fetch.ts
public final class AzureDevOpsProviderAdapter: ProviderAdapter, Sendable {
    public let provider = Provider.azureDevops

    private let httpClient: HTTPClient

    public init(httpClient: HTTPClient = .shared) {
        self.httpClient = httpClient
    }

    // MARK: - ProviderAdapter Protocol

    public func fetchActivities(for account: Account, token: String, from: Date, to: Date) async throws -> [UnifiedActivity] {
        // Determine organization from account.organization field
        guard let organization = account.organization else {
            throw ProviderError.configurationError("Azure DevOps requires organization")
        }

        // Get current authenticated user
        let currentUser = try await fetchCurrentUser(organization: organization, token: token)

        // Discover projects for this organization
        let projects = try await fetchProjects(organization: organization, token: token)
        if projects.isEmpty {
            return []
        }

        let minDate = DateFormatting.iso8601String(from: from)
        let maxDate = DateFormatting.iso8601String(from: to)

        var activities: [UnifiedActivity] = []

        // Limit number of projects to avoid excessive requests
        for project in projects.prefix(10) {
            // Pull Requests (filter by current user as creator)
            if let prs = try? await fetchPullRequests(organization: organization, project: project.name, token: token, minDate: minDate, maxDate: maxDate, creatorId: currentUser.id) {
                // Fetch linked work items for each PR
                var prWorkItemsMap: [Int: [AzureWorkItem]] = [:]
                for pr in prs {
                    if let workItems = try? await fetchPRLinkedWorkItems(
                        organization: organization,
                        project: project.name,
                        repositoryId: pr.repository.id,
                        pullRequestId: pr.pullRequestId,
                        token: token
                    ) {
                        prWorkItemsMap[pr.pullRequestId] = workItems
                    }
                }

                for pr in prs {
                    let linkedWorkItems = prWorkItemsMap[pr.pullRequestId] ?? []
                    activities.append(normalizePullRequest(pr, accountId: account.id, organization: organization, linkedWorkItems: linkedWorkItems))
                }
            }

            // Commits per repository (limit repos to avoid over-fetch)
            if let repos = try? await fetchRepositories(organization: organization, project: project.name, token: token) {
                for repo in repos.prefix(10) {
                    if let commits = try? await fetchCommits(
                        organization: organization,
                        project: project.name,
                        repoId: repo.id,
                        token: token,
                        minDate: minDate,
                        maxDate: maxDate,
                        authorEmail: currentUser.email
                    ) {
                        for commit in commits {
                            activities.append(normalizeCommit(commit, accountId: account.id, organization: organization, project: project.name, repoName: repo.name))
                        }
                    }
                }
            }

            // Work Items (assigned to current user)
            if let workItems = try? await fetchWorkItems(organization: organization, project: project.name, token: token, minDate: minDate, maxDate: maxDate, userEmail: currentUser.email) {
                for wi in workItems {
                    activities.append(normalizeWorkItem(wi, accountId: account.id, organization: organization, project: project.name))
                }
            }
        }

        // Sort by timestamp descending
        activities.sort { $0.timestamp > $1.timestamp }
        return activities
    }

    public func fetchHeatmap(for account: Account, token: String, from: Date, to: Date) async throws -> [HeatMapBucket] {
        let activities = try await fetchActivities(for: account, token: token, from: from, to: to)
        return HeatmapGenerator.generateBuckets(from: activities)
    }

    // MARK: - API Helpers

    private func buildPath(project: String?, endpoint: String) -> String {
        if let project = project {
            return "/\(project)/_apis\(endpoint)"
        } else {
            return "/_apis\(endpoint)"
        }
    }

    private func get<T: Decodable>(organization: String, project: String? = nil, endpoint: String, token: String, query: [String: String] = [:], decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let request = try RequestBuilder.buildAzureDevOpsRequest(
            organization: organization,
            path: buildPath(project: project, endpoint: endpoint),
            queryItems: items,
            token: token
        )
        return try await httpClient.executeRequest(request, decoding: T.self)
    }

    private func post<T: Decodable>(organization: String, project: String, endpoint: String, token: String, body: [String: Any], decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var request = try RequestBuilder.buildAzureDevOpsRequest(
            organization: organization,
            path: buildPath(project: project, endpoint: endpoint),
            token: token
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await httpClient.executeRequest(request)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Fetchers

    private func fetchCurrentUser(organization: String, token: String) async throws -> AzureAuthenticatedUser {
        struct ConnectionData: Decodable {
            let authenticatedUser: AzureAuthenticatedUser
        }
        let resp: ConnectionData = try await get(organization: organization, endpoint: "/connectionData", token: token)
        return resp.authenticatedUser
    }

    private func fetchProjects(organization: String, token: String) async throws -> [AzureProject] {
        struct Response: Decodable { let value: [AzureProject] }
        let resp: Response = try await get(organization: organization, endpoint: "/projects", token: token)
        return resp.value
    }

    private func fetchPullRequests(organization: String, project: String, token: String, minDate: String, maxDate: String, creatorId: String) async throws -> [AzurePullRequest] {
        struct Response: Decodable { let value: [AzurePullRequest] }
        let resp: Response = try await get(
            organization: organization,
            project: project,
            endpoint: "/git/pullrequests",
            token: token,
            query: [
                "searchCriteria.status": "all",
                "searchCriteria.creatorId": creatorId,
                "$top": "100"
            ]
        )

        // Client-side filter by date range
        let minTime = DateFormatting.parseISO8601(minDate)?.timeIntervalSince1970 ?? 0
        let maxTime = DateFormatting.parseISO8601(maxDate)?.timeIntervalSince1970 ?? Date.distantFuture.timeIntervalSince1970
        return resp.value.filter { pr in
            let ts = DateFormatting.parseISO8601(pr.closedDate ?? pr.creationDate)?.timeIntervalSince1970 ?? 0
            return ts >= minTime && ts <= maxTime
        }
    }

    private func fetchRepositories(organization: String, project: String, token: String) async throws -> [AzureRepo] {
        struct Response: Decodable { let value: [AzureRepo] }
        let resp: Response = try await get(
            organization: organization,
            project: project,
            endpoint: "/git/repositories",
            token: token
        )
        return resp.value
    }

    private func fetchCommits(organization: String, project: String, repoId: String, token: String, minDate: String, maxDate: String, authorEmail: String) async throws -> [AzureCommit] {
        struct Response: Decodable { let value: [AzureCommit] }
        let resp: Response = try await get(
            organization: organization,
            project: project,
            endpoint: "/git/repositories/\(repoId)/commits",
            token: token,
            query: [
                "searchCriteria.fromDate": minDate,
                "searchCriteria.toDate": maxDate,
                "searchCriteria.author": authorEmail,
                "$top": "100"
            ]
        )
        return resp.value
    }

    private func fetchWorkItems(organization: String, project: String, token: String, minDate: String, maxDate: String, userEmail: String) async throws -> [AzureWorkItem] {
        // WIQL query: changed within date range and assigned to current user (date-only)
        let minDateOnly = String(minDate.prefix(10))
        let maxDateOnly = String(maxDate.prefix(10))
        let wiql = [
            "query": "SELECT [System.Id] FROM WorkItems WHERE [System.ChangedDate] >= '\(minDateOnly)' AND [System.ChangedDate] <= '\(maxDateOnly)' AND [System.TeamProject] = '\(project)' AND [System.AssignedTo] = @Me ORDER BY [System.ChangedDate] DESC"
        ]

        let wiqlResult: AzureWiqlResult = try await post(
            organization: organization,
            project: project,
            endpoint: "/wit/wiql",
            token: token,
            body: wiql
        )

        guard !wiqlResult.workItems.isEmpty else { return [] }

        // Fetch details in batch (limit to 100)
        let ids = wiqlResult.workItems.prefix(100).map { String($0.id) }.joined(separator: ",")
        struct Response: Decodable { let value: [AzureWorkItem] }
        let resp: Response = try await get(
            organization: organization,
            endpoint: "/wit/workitems",
            token: token,
            query: [
                "ids": ids,
                "fields": "System.Id,System.Title,System.WorkItemType,System.State,System.CreatedDate,System.ChangedDate,System.CreatedBy,System.AssignedTo"
            ]
        )
        return resp.value
    }

    /// Fetch work items linked to a pull request
    private func fetchPRLinkedWorkItems(organization: String, project: String, repositoryId: String, pullRequestId: Int, token: String) async throws -> [AzureWorkItem] {
        // First, get the work item references
        let resp: AzurePRWorkItemsResponse = try await get(
            organization: organization,
            project: project,
            endpoint: "/git/repositories/\(repositoryId)/pullRequests/\(pullRequestId)/workitems",
            token: token
        )

        guard !resp.value.isEmpty else { return [] }

        // Fetch work item details in batch
        let ids = resp.value.map { $0.id }.joined(separator: ",")
        struct WorkItemsResponse: Decodable { let value: [AzureWorkItem] }
        let workItemsResp: WorkItemsResponse = try await get(
            organization: organization,
            endpoint: "/wit/workitems",
            token: token,
            query: [
                "ids": ids,
                "fields": "System.Id,System.Title,System.WorkItemType,System.State"
            ]
        )
        return workItemsResp.value
    }

    // MARK: - Normalization

    private func normalizePullRequest(_ pr: AzurePullRequest, accountId: String, organization: String, linkedWorkItems: [AzureWorkItem] = []) -> UnifiedActivity {
        let tsStr = pr.closedDate ?? pr.creationDate
        let timestamp = DateFormatting.parseISO8601(tsStr) ?? Date()
        let url = URL(string: "https://dev.azure.com/\(organization)/\(pr.repository.project.name)/_git/\(pr.repository.name)/pullrequest/\(pr.pullRequestId)")

        // Extract branch name from refs/heads/feature/AB#123 format
        let branchName = pr.sourceRefName?.replacingOccurrences(of: "refs/heads/", with: "")

        // Build API-linked tickets from work items
        var apiLinkedTickets: [LinkedTicket] = []
        for workItem in linkedWorkItems {
            let workItemTitle = workItem.fields.string(for: "System.Title")
            let workItemType = workItem.fields.string(for: "System.WorkItemType") ?? "Work Item"
            let workItemUrl = URL(string: "https://dev.azure.com/\(organization)/\(pr.repository.project.name)/_workitems/edit/\(workItem.id)")
            apiLinkedTickets.append(LinkedTicket(
                system: .azureBoards,
                key: "AB#\(workItem.id)",
                title: "[\(workItemType)] \(workItemTitle ?? "")",
                url: workItemUrl,
                source: .apiLink
            ))
        }

        // Extract tickets from text sources
        let extractedTickets = TicketExtractor.extractFromActivity(
            branchName: branchName,
            title: pr.title,
            description: pr.description,
            defaultSystem: .azureBoards
        )

        // Merge API-linked and extracted tickets
        let mergedTickets = TicketExtractor.merge(extracted: extractedTickets, apiLinked: apiLinkedTickets)
        let linkedTickets: [LinkedTicket]? = mergedTickets.isEmpty ? nil : mergedTickets

        return UnifiedActivity(
            id: "azure-devops:\(accountId):pr-\(pr.pullRequestId)",
            provider: .azureDevops,
            accountId: accountId,
            sourceId: String(pr.pullRequestId),
            type: .pullRequest,
            timestamp: timestamp,
            title: pr.title,
            participants: [pr.createdBy.displayName],
            url: url,
            sourceRef: branchName,
            targetRef: pr.targetRefName?.replacingOccurrences(of: "refs/heads/", with: ""),
            projectName: pr.repository.name,
            linkedTickets: linkedTickets
        )
    }

    private func normalizeCommit(_ commit: AzureCommit, accountId: String, organization: String, project: String, repoName: String) -> UnifiedActivity {
        let timestamp = DateFormatting.parseISO8601(commit.author.date) ?? Date()
        let titleFirstLine = commit.comment.split(separator: "\n").first.map(String.init) ?? commit.comment
        let title = String(titleFirstLine.prefix(100))
        let summary = commit.comment.count > 100 ? String(commit.comment.prefix(200)) : nil
        let url = URL(string: "https://dev.azure.com/\(organization)/\(project)/_git/\(repoName)/commit/\(commit.commitId)")
        let shortId = String(commit.commitId.prefix(8))

        return UnifiedActivity(
            id: "azure-devops:\(accountId):commit-\(shortId)",
            provider: .azureDevops,
            accountId: accountId,
            sourceId: commit.commitId,
            type: .commit,
            timestamp: timestamp,
            title: title,
            summary: summary,
            participants: [commit.author.name],
            url: url,
            projectName: repoName
        )
    }

    private func normalizeWorkItem(_ workItem: AzureWorkItem, accountId: String, organization: String, project: String) -> UnifiedActivity {
        let fields = workItem.fields
        let workItemType = fields.string(for: "System.WorkItemType") ?? "Work Item"
        let title = fields.string(for: "System.Title") ?? "Work Item #\(workItem.id)"
        let changed = fields.string(for: "System.ChangedDate")
        let created = fields.string(for: "System.CreatedDate")
        let timestamp = (changed.flatMap(DateFormatting.parseISO8601) ?? created.flatMap(DateFormatting.parseISO8601)) ?? Date()
        let createdBy = fields.user(for: "System.CreatedBy")?.displayName
        let url = URL(string: "https://dev.azure.com/\(organization)/\(project)/_workitems/edit/\(workItem.id)")

        return UnifiedActivity(
            id: "azure-devops:\(accountId):wi-\(workItem.id)",
            provider: .azureDevops,
            accountId: accountId,
            sourceId: String(workItem.id),
            type: .issue,
            timestamp: timestamp,
            title: "[\(workItemType)] \(title)",
            participants: createdBy.map { [$0] },
            url: url
        )
    }
}

// MARK: - API Types

struct AzureProject: Decodable, Sendable {
    let id: String
    let name: String
}

struct AzureRepo: Decodable, Sendable {
    let id: String
    let name: String
}

struct AzurePullRequest: Decodable, Sendable {
    let pullRequestId: Int
    let title: String
    let description: String?
    let sourceRefName: String?  // refs/heads/feature/AB#123
    let targetRefName: String?
    let creationDate: String
    let closedDate: String?
    let status: String
    let createdBy: AzureUser
    let repository: AzureRepository
}

/// Work item reference from PR work items API
struct AzureWorkItemRef: Decodable, Sendable {
    let id: String
    let url: String
}

/// Response wrapper for PR work items
struct AzurePRWorkItemsResponse: Decodable, Sendable {
    let value: [AzureWorkItemRef]
}

struct AzureUser: Decodable, Sendable {
    let id: String?
    let displayName: String
    let uniqueName: String?
}

struct AzureAuthenticatedUser: Decodable, Sendable {
    let id: String
    let descriptor: String?
    let subjectDescriptor: String?
    let providerDisplayName: String?
    let customDisplayName: String?

    // Email might be in different fields depending on the auth type
    let emailAddress: String?
    let mailAddress: String?

    /// Best available email address
    var email: String {
        emailAddress ?? mailAddress ?? ""
    }

    /// Best available display name
    var displayName: String {
        customDisplayName ?? providerDisplayName ?? id
    }
}

struct AzureRepository: Decodable, Sendable {
    let id: String
    let name: String
    let project: AzureProjectRef
}

struct AzureProjectRef: Decodable, Sendable { let name: String }

struct AzureCommit: Decodable, Sendable {
    let commitId: String
    let comment: String
    let author: AzureCommitIdentity
    let committer: AzureCommitIdentity
    let url: String
    let remoteUrl: String?
}

struct AzureCommitIdentity: Decodable, Sendable {
    let name: String
    let email: String
    let date: String
}

struct AzureWorkItem: Decodable, Sendable {
    let id: Int
    let fields: AzureFields
    let _links: AzureWorkItemLinks
}

struct AzureWorkItemLinks: Decodable, Sendable {
    let html: AzureHref

    enum CodingKeys: String, CodingKey { case html }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.html = try container.decode(AzureHref.self, forKey: .html)
    }
}

struct AzureHref: Decodable, Sendable { let href: String }

/// Flexible fields map for work items
struct AzureFields: Decodable, Sendable {
    let raw: [String: AzureFieldValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: AzureFieldValue].self)
        self.raw = dict
    }

    func string(for key: String) -> String? {
        if case let .string(str)? = raw[key] { return str }
        return raw[key]?.stringValue
    }

    func user(for key: String) -> AzureUser? {
        guard let value = raw[key] else { return nil }
        switch value {
        case .object(let obj):
            let name = (obj["displayName"]?.stringValue)
            let unique = (obj["uniqueName"]?.stringValue)
            return AzureUser(id: nil, displayName: name ?? "", uniqueName: unique)
        default:
            return nil
        }
    }
}

enum AzureFieldValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AzureFieldValue])
    case array([AzureFieldValue])
    case null

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let obj = try? container.decode([String: AzureFieldValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([AzureFieldValue].self) {
            self = .array(arr)
        } else {
            self = .null
        }
    }
}

struct AzureWiqlResult: Decodable, Sendable {
    struct Item: Decodable, Sendable { let id: Int; let url: String }
    let workItems: [Item]
}

