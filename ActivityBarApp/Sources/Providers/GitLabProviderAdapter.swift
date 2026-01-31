import Foundation
import Core

/// GitLab provider adapter implementing activity fetching via REST API
///
/// Supports both gitlab.com and self-hosted instances via baseURL.
/// Ported from activity-discovery/providers/gitlab/fetch.ts
public final class GitLabProviderAdapter: ProviderAdapter, Sendable {
    public let provider = Provider.gitlab

    private let httpClient: HTTPClient

    /// Default base URL for gitlab.com
    public static let defaultBaseURL = "https://gitlab.com"

    public init(httpClient: HTTPClient = .shared) {
        self.httpClient = httpClient
    }

    // MARK: - ProviderAdapter Protocol

    public func fetchActivities(for account: Account, token: String, from: Date, to: Date) async throws -> [UnifiedActivity] {
        // Reconstruct full URL with protocol if host is normalized (stripped protocol)
        let baseURL: String
        if let host = account.host {
            baseURL = host.hasPrefix("http") ? host : "https://\(host)"
        } else {
            baseURL = Self.defaultBaseURL
        }

        // Get current user ID to fetch user-specific events
        let user = try await fetchCurrentUser(baseURL: baseURL, token: token, authMethod: account.authMethod)

        // Build time window params (YYYY-MM-DD format)
        // GitLab API uses exclusive bounds: after=X means > X, before=Y means < Y
        // To include today's events, we need before=(tomorrow)
        let afterDate = DateFormatting.dateString(from: from)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: to)!
        let beforeDate = DateFormatting.dateString(from: tomorrow)

        // Fetch user's events with pagination (user-specific endpoint returns the user's own activity)
        let events = try await fetchAllPages(
            baseURL: baseURL,
            token: token,
            authMethod: account.authMethod,
            endpoint: "/users/\(user.id)/events",
            params: ["after": afterDate, "before": beforeDate]
        )
        print("[ActivityBar][GitLab] Fetched \(events.count) raw events from API")
        // Log event types for debugging
        let eventTypes = events.map { "\($0.actionName):\($0.targetType ?? "nil")" }
        let typeCounts = Dictionary(grouping: eventTypes, by: { $0 }).mapValues { $0.count }
        print("[ActivityBar][GitLab] Event types: \(typeCounts)")

        // Get unique project IDs to fetch project details for URLs and names
        let projectIds = Set(events.compactMap { $0.projectId })

        // Fetch project details for URL building and project names
        var projectInfoMap: [Int: (path: String, name: String)] = [:]
        for projectId in projectIds {
            if let project = try? await fetchProject(baseURL: baseURL, token: token, authMethod: account.authMethod, projectId: projectId) {
                projectInfoMap[projectId] = (path: project.pathWithNamespace, name: project.name)
            }
        }

        // Fetch MR details for MR events to get reviewer/assignee avatars
        var mrDetailsMap: [String: GitLabMergeRequest] = [:]  // key: "projectId:mrIid"
        for event in events where event.targetType == "MergeRequest" {
            if let projectId = event.projectId, let mrIid = event.targetIid {
                let key = "\(projectId):\(mrIid)"
                if mrDetailsMap[key] == nil {
                    if let mr = try? await fetchMergeRequest(baseURL: baseURL, token: token, authMethod: account.authMethod, projectId: projectId, mrIid: mrIid) {
                        mrDetailsMap[key] = mr
                    }
                }
            }
        }

        // Fetch user avatars for event authors
        let authorIds = Set(events.map { $0.authorId })
        var authorAvatarMap: [Int: URL] = [:]  // authorId -> avatarURL
        for authorId in authorIds {
            if let userInfo = try? await fetchUser(baseURL: baseURL, token: token, authMethod: account.authMethod, userId: authorId),
               let avatarUrlString = userInfo.avatarUrl,
               let avatarUrl = URL(string: avatarUrlString) {
                authorAvatarMap[authorId] = avatarUrl
            }
        }

        // Normalize events to activities
        var activities: [UnifiedActivity] = []
        var skippedEvents: [String] = []
        for event in events {
            if let activity = normalizeEvent(event, accountId: account.id, baseURL: baseURL, projectInfoMap: projectInfoMap, mrDetailsMap: mrDetailsMap, authorAvatarMap: authorAvatarMap) {
                activities.append(activity)
            } else {
                skippedEvents.append("\(event.actionName):\(event.targetType ?? "nil")")
            }
        }
        print("[ActivityBar][GitLab] Normalized to \(activities.count) activities, skipped \(skippedEvents.count) events: \(Set(skippedEvents))")

        // Sort by timestamp descending
        activities.sort { $0.timestamp > $1.timestamp }

        return activities
    }

    public func fetchHeatmap(for account: Account, token: String, from: Date, to: Date) async throws -> [HeatMapBucket] {
        let activities = try await fetchActivities(for: account, token: token, from: from, to: to)
        return HeatmapGenerator.generateBuckets(from: activities)
    }

    // MARK: - API Fetching

    /// Fetch all pages of a paginated endpoint
    private func fetchAllPages(
        baseURL: String,
        token: String,
        authMethod: AuthMethod,
        endpoint: String,
        params: [String: String],
        maxPages: Int = 10
    ) async throws -> [GitLabEvent] {
        var results: [GitLabEvent] = []
        var page = 1

        while page <= maxPages {
            var pageParams = params
            pageParams["page"] = String(page)
            pageParams["per_page"] = "100"

            let request = try RequestBuilder.buildGitLabRequest(
                baseURL: baseURL,
                path: endpoint,
                queryItems: pageParams.map { URLQueryItem(name: $0.key, value: $0.value) },
                token: token,
                authMethod: authMethod
            )

            let data = try await httpClient.executeRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let pageResults = try decoder.decode([GitLabEvent].self, from: data)

            if pageResults.isEmpty {
                break
            }

            results.append(contentsOf: pageResults)
            page += 1
        }

        return results
    }

    /// Fetch a single project by ID
    private func fetchProject(baseURL: String, token: String, authMethod: AuthMethod, projectId: Int) async throws -> GitLabProject {
        let request = try RequestBuilder.buildGitLabRequest(
            baseURL: baseURL,
            path: "/projects/\(projectId)",
            token: token,
            authMethod: authMethod
        )

        let data = try await httpClient.executeRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitLabProject.self, from: data)
    }

    /// Fetch the current authenticated user
    private func fetchCurrentUser(baseURL: String, token: String, authMethod: AuthMethod) async throws -> GitLabUser {
        let request = try RequestBuilder.buildGitLabRequest(
            baseURL: baseURL,
            path: "/user",
            token: token,
            authMethod: authMethod
        )

        let data = try await httpClient.executeRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitLabUser.self, from: data)
    }

    /// Fetch merge request details (for reviewer/assignee avatars)
    private func fetchMergeRequest(baseURL: String, token: String, authMethod: AuthMethod, projectId: Int, mrIid: Int) async throws -> GitLabMergeRequest {
        let request = try RequestBuilder.buildGitLabRequest(
            baseURL: baseURL,
            path: "/projects/\(projectId)/merge_requests/\(mrIid)",
            token: token,
            authMethod: authMethod
        )

        let data = try await httpClient.executeRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitLabMergeRequest.self, from: data)
    }

    /// Fetch user details by ID (for author avatars)
    private func fetchUser(baseURL: String, token: String, authMethod: AuthMethod, userId: Int) async throws -> GitLabUser {
        let request = try RequestBuilder.buildGitLabRequest(
            baseURL: baseURL,
            path: "/users/\(userId)",
            token: token,
            authMethod: authMethod
        )

        let data = try await httpClient.executeRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitLabUser.self, from: data)
    }

    // MARK: - Event Type Mapping

    /// Map GitLab event to ActivityType
    private func mapEventToActivityType(_ event: GitLabEvent) -> ActivityType? {
        // Handle push events - GitLab API returns "pushed to" or "pushed new"
        if (event.actionName == "pushed to" || event.actionName == "pushed new") && event.pushData != nil {
            return .commit
        }

        // Handle comment events - GitLab API returns "commented on"
        if event.actionName == "commented on" {
            if event.note?.noteableType == "MergeRequest" {
                return .codeReview  // MR comments treated as code review activity
            }
            return .issueComment
        }

        // Look up in mapping table
        let key = "\(event.actionName):\(event.targetType ?? "")"
        if let mappedType = Self.eventTypeMapping[key] {
            return mappedType
        }

        // Default mapping based on target type
        if event.targetType == "MergeRequest" {
            return .pullRequest
        }
        if event.targetType == "Issue" {
            return .issue
        }

        return nil
    }

    /// Mapping from GitLab event action + target to ActivityType
    /// Note: GitLab API returns action names like "pushed to", "commented on", "created", etc.
    private static let eventTypeMapping: [String: ActivityType] = [
        // Push events (handled explicitly in mapEventToActivityType, but keep for fallback)
        "pushed to:Project": .commit,
        "pushed new:Project": .commit,

        // Merge Request events
        "created:MergeRequest": .pullRequest,
        "updated:MergeRequest": .pullRequest,
        "closed:MergeRequest": .pullRequest,
        "reopened:MergeRequest": .pullRequest,
        "merged:MergeRequest": .pullRequest,
        "approved:MergeRequest": .codeReview,

        // Issue events
        "created:Issue": .issue,
        "updated:Issue": .issue,
        "closed:Issue": .issue,
        "reopened:Issue": .issue,

        // Comment events - GitLab uses DiffNote, DiscussionNote for MR comments
        "commented on:DiffNote": .codeReview,
        "commented on:DiscussionNote": .codeReview,
        "commented on:Note": .issueComment,
    ]

    // MARK: - URL Building

    /// Build URL for GitLab event
    private func buildEventURL(baseURL: String, event: GitLabEvent, projectPath: String?) -> URL? {
        guard let projectPath = projectPath else {
            return nil
        }

        let base = "\(baseURL)/\(projectPath)"

        if event.targetType == "MergeRequest", let targetIid = event.targetIid {
            return URL(string: "\(base)/-/merge_requests/\(targetIid)")
        }

        if event.targetType == "Issue", let targetIid = event.targetIid {
            return URL(string: "\(base)/-/issues/\(targetIid)")
        }

        if (event.actionName == "pushed to" || event.actionName == "pushed new"), let commitTo = event.pushData?.commitTo {
            return URL(string: "\(base)/-/commit/\(commitTo)")
        }

        if let note = event.note, let noteableIid = note.noteableIid {
            if note.noteableType == "MergeRequest" {
                return URL(string: "\(base)/-/merge_requests/\(noteableIid)#note_\(note.id)")
            }
            if note.noteableType == "Issue" {
                return URL(string: "\(base)/-/issues/\(noteableIid)#note_\(note.id)")
            }
        }

        return nil
    }

    // MARK: - Event Normalization

    /// Normalize a GitLab event to UnifiedActivity
    private func normalizeEvent(
        _ event: GitLabEvent,
        accountId: String,
        baseURL: String,
        projectInfoMap: [Int: (path: String, name: String)],
        mrDetailsMap: [String: GitLabMergeRequest] = [:],
        authorAvatarMap: [Int: URL] = [:]
    ) -> UnifiedActivity? {
        guard let activityType = mapEventToActivityType(event) else {
            return nil
        }

        let projectInfo = event.projectId.flatMap { projectInfoMap[$0] }
        let url = buildEventURL(baseURL: baseURL, event: event, projectPath: projectInfo?.path)
        let projectName = projectInfo?.name

        // Get MR details for reviewer avatars (if this is an MR event)
        var reviewers: [Participant]?
        if event.targetType == "MergeRequest", let projectId = event.projectId, let mrIid = event.targetIid {
            let mrKey = "\(projectId):\(mrIid)"
            if let mr = mrDetailsMap[mrKey] {
                // Combine reviewers and assignees, avoiding duplicates
                var participantSet = Set<String>()
                var participants: [Participant] = []

                // Add reviewers first
                for reviewer in mr.reviewers ?? [] {
                    if !participantSet.contains(reviewer.username) {
                        participantSet.insert(reviewer.username)
                        participants.append(Participant(
                            username: reviewer.username,
                            avatarURL: reviewer.avatarUrl.flatMap { URL(string: $0) }
                        ))
                    }
                }

                // Add assignees
                for assignee in mr.assignees ?? [] {
                    if !participantSet.contains(assignee.username) {
                        participantSet.insert(assignee.username)
                        participants.append(Participant(
                            username: assignee.username,
                            avatarURL: assignee.avatarUrl.flatMap { URL(string: $0) }
                        ))
                    }
                }

                if !participants.isEmpty {
                    reviewers = participants
                }
            }
        }

        // Build title based on event type
        let title: String
        let summary: String?
        var sourceRef: String?
        var commitSHA: String?

        if (event.actionName == "pushed to" || event.actionName == "pushed new"), let pushData = event.pushData {
            // Use commit message as title, branch info as summary
            title = pushData.commitTitle ?? "Commit to \(pushData.ref)"
            let count = pushData.commitCount
            if count > 1 {
                summary = "\(count) commits pushed to \(pushData.ref)"
            } else {
                summary = nil
            }
            sourceRef = pushData.ref  // Branch name for grouping
            commitSHA = pushData.commitTo  // Actual commit SHA
        } else if let note = event.note {
            let noteableId = note.noteableIid ?? note.noteableId
            title = "Comment on \(note.noteableType) #\(noteableId)"
            summary = note.body.map { String($0.prefix(200)) }
        } else {
            title = event.targetTitle ?? "\(event.actionName) \(event.targetType ?? "item")"
            summary = nil
        }

        // Parse timestamp
        let timestamp = DateFormatting.parseISO8601(event.createdAt) ?? Date()

        // Use commit SHA as sourceId for commits (for display), otherwise event ID
        let sourceId = commitSHA ?? String(event.id)

        // Get author avatar URL from the map
        let authorAvatarURL = authorAvatarMap[event.authorId]

        return UnifiedActivity(
            id: "gitlab:\(accountId):event-\(event.id)",
            provider: .gitlab,
            accountId: accountId,
            sourceId: sourceId,
            type: activityType,
            timestamp: timestamp,
            title: title,
            summary: summary,
            participants: [event.authorUsername],
            url: url,
            authorAvatarURL: authorAvatarURL,
            sourceRef: sourceRef,
            projectName: projectName,
            reviewers: reviewers
        )
    }
}

// MARK: - GitLab API Types

/// GitLab Event from the Events API
struct GitLabEvent: Codable, Sendable {
    let id: Int
    let actionName: String
    let createdAt: String
    let targetId: Int?
    let targetIid: Int?
    let targetType: String?
    let targetTitle: String?
    let authorId: Int
    let authorUsername: String
    let projectId: Int?
    let pushData: GitLabPushData?
    let note: GitLabNote?
}

/// Push data for push events
struct GitLabPushData: Codable, Sendable {
    let commitCount: Int
    let action: String
    let refType: String
    let commitFrom: String?
    let commitTo: String?
    let ref: String
    let commitTitle: String?
}

/// Note data for comment events
struct GitLabNote: Codable, Sendable {
    let id: Int
    let body: String?
    let noteableType: String
    let noteableId: Int
    let noteableIid: Int?
}

/// GitLab Project (minimal fields)
struct GitLabProject: Codable, Sendable {
    let id: Int
    let name: String
    let nameWithNamespace: String
    let pathWithNamespace: String
    let webUrl: String
}

/// GitLab User (minimal fields for current user endpoint)
struct GitLabUser: Codable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarUrl: String?
}

/// GitLab Merge Request (for fetching reviewer/assignee details)
struct GitLabMergeRequest: Codable, Sendable {
    let id: Int
    let iid: Int
    let title: String
    let author: GitLabUser?
    let assignees: [GitLabUser]?
    let reviewers: [GitLabUser]?
}
