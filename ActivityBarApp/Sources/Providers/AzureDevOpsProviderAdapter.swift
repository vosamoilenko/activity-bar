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

        ActivityLogger.shared.log("Azure", "Fetching activities for \(organization) (\(DateFormatting.dateString(from: from)) to \(DateFormatting.dateString(from: to)))")

        // Get current authenticated user
        let currentUser = try await fetchCurrentUser(organization: organization, token: token)
        ActivityLogger.shared.log("Azure", "User: \(currentUser.displayName) (email=\(currentUser.email.isEmpty ? "N/A" : currentUser.email))")

        // Discover projects for this organization
        let projects = try await fetchProjects(organization: organization, token: token)
        if projects.isEmpty {
            ActivityLogger.shared.log("Azure", "No projects found")
            return []
        }
        ActivityLogger.shared.log("Azure", "Found \(projects.count) projects")

        let minDate = DateFormatting.iso8601String(from: from)
        let maxDate = DateFormatting.iso8601String(from: to)

        var activities: [UnifiedActivity] = []
        var totalPRs = 0
        var totalCommits = 0
        var totalWorkItems = 0

        // Limit number of projects to avoid excessive requests
        for project in projects.prefix(10) {
            var projectPRs = 0
            var projectCommits = 0
            var projectWorkItems = 0

            // Pull Requests (filter by current user as creator)
            if let prs = try? await fetchPullRequests(organization: organization, project: project.name, token: token, minDate: minDate, maxDate: maxDate, creatorId: currentUser.id) {
                projectPRs = prs.count

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
            // Collect commits first, then batch-validate extracted ticket IDs
            var pendingCommits: [(commit: AzureCommit, repoName: String, branchName: String?)] = []

            if let repos = try? await fetchRepositories(organization: organization, project: project.name, token: token) {
                for repo in repos.prefix(10) {
                    // Fetch pushes for branch mapping
                    var pushBranchMap: [String: String] = [:]
                    if let pushes = try? await fetchPushes(
                        organization: organization,
                        project: project.name,
                        repoId: repo.id,
                        token: token,
                        minDate: minDate,
                        maxDate: maxDate
                    ) {
                        pushBranchMap = mapCommitBranches(from: pushes)
                        if !pushBranchMap.isEmpty {
                            // Log the branches found
                            let uniqueBranches = Set(pushBranchMap.values)
                            ActivityLogger.shared.log("Azure", "[\(repo.name)] Push branches: \(uniqueBranches.joined(separator: ", "))")
                        }
                    }

                    do {
                        let commits = try await fetchCommits(
                            organization: organization,
                            project: project.name,
                            repoId: repo.id,
                            token: token,
                            minDate: minDate,
                            maxDate: maxDate
                        )
                        ActivityLogger.shared.log("Azure", "[\(repo.name)] Got \(commits.count) commits")
                        // Don't filter by author - just like TypeScript version
                        // Users only see repos they have access to anyway
                        for commit in commits {
                            let commitIdLower = commit.commitId.lowercased()
                            let branchName = pushBranchMap[commitIdLower]
                            pendingCommits.append((commit, repo.name, branchName))
                        }
                    } catch {
                        ActivityLogger.shared.log("Azure", "[\(repo.name)] Commits error: \(error)")
                    }
                }
            }

            // Collect all potential ticket IDs from commits for batch validation
            var potentialTicketIds = Set<Int>()
            for (commit, _, branchName) in pendingCommits {
                let titleLine = String(commit.comment.split(separator: "\n").first ?? "")
                let extracted = TicketExtractor.extractFromActivity(
                    branchName: branchName,
                    title: titleLine,
                    description: commit.comment,
                    defaultSystem: .azureBoards
                )
                for ticket in extracted where ticket.system == .azureBoards {
                    if let numStr = ticket.key.replacingOccurrences(of: "AB#", with: "").components(separatedBy: CharacterSet.decimalDigits.inverted).first,
                       let num = Int(numStr) {
                        potentialTicketIds.insert(num)
                    }
                }
            }

            // Batch validate ticket IDs against Azure DevOps API
            let validTicketIds = await validateWorkItemIds(
                Array(potentialTicketIds),
                organization: organization,
                token: token
            )

            if !potentialTicketIds.isEmpty {
                ActivityLogger.shared.log("Azure", "[\(project.name)] Validated \(validTicketIds.count)/\(potentialTicketIds.count) ticket IDs")
            }

            // Now normalize commits with validated ticket IDs
            projectCommits = pendingCommits.count
            for (commit, repoName, branchName) in pendingCommits {
                let shortId = String(commit.commitId.prefix(8))
                let branchLog = branchName ?? "NO_BRANCH"
                let titleLine = commit.comment.split(separator: "\n").first ?? ""
                ActivityLogger.shared.log("Azure", "  commit \(shortId) → \(branchLog): \(String(titleLine.prefix(50)))")

                activities.append(normalizeCommit(
                    commit,
                    accountId: account.id,
                    organization: organization,
                    project: project.name,
                    repoName: repoName,
                    branchName: branchName,
                    validTicketIds: validTicketIds
                ))
            }

            // Work Items (assigned to current user)
            if let workItems = try? await fetchWorkItems(organization: organization, project: project.name, token: token, minDate: minDate, maxDate: maxDate, userEmail: currentUser.email) {
                projectWorkItems = workItems.count
                for wi in workItems {
                    activities.append(normalizeWorkItem(wi, accountId: account.id, organization: organization, project: project.name))
                }
            }

            totalPRs += projectPRs
            totalCommits += projectCommits
            totalWorkItems += projectWorkItems

            if projectPRs > 0 || projectCommits > 0 || projectWorkItems > 0 {
                ActivityLogger.shared.log("Azure", "[\(project.name)] \(projectPRs) PRs, \(projectCommits) commits, \(projectWorkItems) work items")
            }
        }

        // Sort by timestamp descending
        activities.sort { $0.timestamp > $1.timestamp }

        // Log summary
        ActivityLogger.shared.logFetchSummary("Azure", results: [
            ("PRs", totalPRs),
            ("commits", totalCommits),
            ("work items", totalWorkItems)
        ])

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
        let items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
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
        let filtered = resp.value.filter { pr in
            let ts = DateFormatting.parseISO8601(pr.closedDate ?? pr.creationDate)?.timeIntervalSince1970 ?? 0
            return ts >= minTime && ts <= maxTime
        }
        return filtered
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

    private func fetchCommits(organization: String, project: String, repoId: String, token: String, minDate: String, maxDate: String) async throws -> [AzureCommit] {
        struct Response: Decodable { let value: [AzureCommit] }
        // Fetch commits without author filter - we'll filter client-side
        // This ensures we don't miss commits due to name format mismatches
        let resp: Response = try await get(
            organization: organization,
            project: project,
            endpoint: "/git/repositories/\(repoId)/commits",
            token: token,
            query: [
                "searchCriteria.fromDate": minDate,
                "searchCriteria.toDate": maxDate,
                "$top": "100"
            ]
        )
        return resp.value
    }

    private func fetchPushes(organization: String, project: String, repoId: String, token: String, minDate: String, maxDate: String) async throws -> [AzurePush] {
        struct Response: Decodable { let value: [AzurePush] }
        // Get pushes within date range (matching TypeScript behavior)
        let listResp: Response = try await get(
            organization: organization,
            project: project,
            endpoint: "/git/repositories/\(repoId)/pushes",
            token: token,
            query: [
                "searchCriteria.fromDate": minDate,
                "searchCriteria.toDate": maxDate,
                "searchCriteria.includeRefUpdates": "true",
                "$top": "100"
            ]
        )

        // Fetch individual push details to get commits (list endpoint doesn't include them)
        // Limit to 30 pushes to avoid excessive API calls
        var detailedPushes: [AzurePush] = []
        for push in listResp.value.prefix(30) {
            guard let pushId = push.pushId else { continue }
            if let detailed = try? await fetchPushDetail(
                organization: organization,
                project: project,
                repoId: repoId,
                pushId: pushId,
                token: token
            ) {
                detailedPushes.append(detailed)
            }
        }

        return detailedPushes
    }

    private func fetchPushDetail(organization: String, project: String, repoId: String, pushId: Int, token: String) async throws -> AzurePush {
        return try await get(
            organization: organization,
            project: project,
            endpoint: "/git/repositories/\(repoId)/pushes/\(pushId)",
            token: token,
            query: [
                "includeCommits": "true",
                "includeRefUpdates": "true"
            ]
        )
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

    /// Validate work item IDs by checking if they exist in Azure DevOps
    /// Returns the set of valid IDs
    private func validateWorkItemIds(_ ids: [Int], organization: String, token: String) async -> Set<Int> {
        guard !ids.isEmpty else { return [] }

        // Batch query - Azure DevOps supports up to 200 IDs per request
        let idsString = ids.prefix(200).map { String($0) }.joined(separator: ",")

        struct Response: Decodable {
            let value: [ValidatedWorkItem]
        }
        struct ValidatedWorkItem: Decodable {
            let id: Int
        }

        do {
            let resp: Response = try await get(
                organization: organization,
                endpoint: "/wit/workitems",
                token: token,
                query: [
                    "ids": idsString,
                    "fields": "System.Id",  // Only fetch ID to minimize response
                    "$top": "200"
                ]
            )
            return Set(resp.value.map { $0.id })
        } catch {
            // If validation fails, assume all are invalid to avoid false positives
            ActivityLogger.shared.log("Azure", "Work item validation failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Normalization

    private func normalizePullRequest(_ pr: AzurePullRequest, accountId: String, organization: String, linkedWorkItems: [AzureWorkItem] = []) -> UnifiedActivity {
        let tsStr = pr.closedDate ?? pr.creationDate
        let timestamp = DateFormatting.parseISO8601(tsStr) ?? Date()
        let url = URL(string: "https://dev.azure.com/\(organization)/\(pr.repository.project.name)/_git/\(pr.repository.name)/pullrequest/\(pr.pullRequestId)")

        // Extract branch name from refs/heads/feature/AB#123 format
        let branchName = pr.sourceRefName?.replacingOccurrences(of: "refs/heads/", with: "")
        let targetBranch = pr.targetRefName?.replacingOccurrences(of: "refs/heads/", with: "")

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
            targetRef: targetBranch,
            projectName: pr.repository.name,
            linkedTickets: linkedTickets,
            rawEventType: "pull_request:\(pr.status)"
        )
    }

    private func normalizeCommit(
        _ commit: AzureCommit,
        accountId: String,
        organization: String,
        project: String,
        repoName: String,
        branchName: String?,
        validTicketIds: Set<Int> = []
    ) -> UnifiedActivity {
        let timestamp = DateFormatting.parseISO8601(commit.author.date) ?? Date()
        let titleFirstLine = commit.comment.split(separator: "\n").first.map(String.init) ?? commit.comment
        let title = String(titleFirstLine.prefix(100))
        let summary = commit.comment.count > 100 ? String(commit.comment.prefix(200)) : nil
        let url = URL(string: "https://dev.azure.com/\(organization)/\(project)/_git/\(repoName)/commit/\(commit.commitId)")
        let shortId = String(commit.commitId.prefix(8))

        // Extract tickets from branch name and commit message
        let extractedTickets = TicketExtractor.extractFromActivity(
            branchName: branchName,
            title: titleFirstLine,
            description: commit.comment,
            defaultSystem: .azureBoards
        )

        // Filter and build URLs for Azure Boards tickets - only include validated ones
        let validatedTickets: [LinkedTicket] = extractedTickets.compactMap { ticket in
            // For Azure Boards tickets, validate against the API results
            if ticket.system == .azureBoards {
                guard let numStr = ticket.key.replacingOccurrences(of: "AB#", with: "")
                    .components(separatedBy: CharacterSet.decimalDigits.inverted).first,
                      let ticketId = Int(numStr) else {
                    return nil
                }

                // Only include if validated (or if no validation was done)
                guard validTicketIds.isEmpty || validTicketIds.contains(ticketId) else {
                    return nil
                }

                let ticketUrl = URL(string: "https://dev.azure.com/\(organization)/\(project)/_workitems/edit/\(numStr)")
                return LinkedTicket(
                    system: ticket.system,
                    key: ticket.key,
                    title: ticket.title,
                    url: ticketUrl,
                    source: ticket.source
                )
            }
            // Non-Azure tickets pass through (e.g., Jira)
            return ticket
        }

        let linkedTickets: [LinkedTicket]? = validatedTickets.isEmpty ? nil : validatedTickets

        // Debug log for commit data
        if let branch = branchName {
            ActivityLogger.shared.log("Azure", "    → branch: \(branch)")
        }
        if let tickets = linkedTickets, !tickets.isEmpty {
            let ticketKeys = tickets.map { $0.key }.joined(separator: ", ")
            ActivityLogger.shared.log("Azure", "    → tickets: \(ticketKeys)")
        }

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
            sourceRef: branchName,
            projectName: repoName,
            linkedTickets: linkedTickets,
            rawEventType: "commit"
        )
    }

    private func mapCommitBranches(from pushes: [AzurePush]) -> [String: String] {
        var map: [String: String] = [:]
        ActivityLogger.shared.log("Azure", "  mapCommitBranches: \(pushes.count) pushes")
        for push in pushes {
            let branchName = normalizeBranchName(from: push.refUpdates)
            let commitCount = push.commits?.count ?? 0
            let refNames = push.refUpdates?.compactMap { $0.name }.joined(separator: ", ") ?? "none"
            ActivityLogger.shared.log("Azure", "    push: branch=\(branchName ?? "nil") refs=[\(refNames)] commits=\(commitCount)")

            guard let branchName, !branchName.isEmpty else { continue }
            for commit in push.commits ?? [] {
                map[commit.commitId.lowercased()] = branchName
            }
        }
        ActivityLogger.shared.log("Azure", "  mapCommitBranches: mapped \(map.count) commits to branches")
        return map
    }

    private func normalizeBranchName(from refUpdates: [AzureRefUpdate]?) -> String? {
        guard let refUpdates, !refUpdates.isEmpty else { return nil }
        if let ref = refUpdates.first(where: { $0.name?.hasPrefix("refs/heads/") == true }) {
            return ref.name?.replacingOccurrences(of: "refs/heads/", with: "")
        }
        return refUpdates.first?.name?.replacingOccurrences(of: "refs/heads/", with: "")
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
            url: url,
            rawEventType: "work_item:\(workItemType)"
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

struct AzurePush: Decodable, Sendable {
    let pushId: Int?
    let date: String?
    let commits: [AzurePushCommit]?
    let refUpdates: [AzureRefUpdate]?
}

struct AzurePushCommit: Decodable, Sendable {
    let commitId: String
}

struct AzureRefUpdate: Decodable, Sendable {
    let name: String?
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
