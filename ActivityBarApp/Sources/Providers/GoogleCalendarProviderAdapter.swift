import Foundation
import Core
import CommonCrypto

/// Google Calendar provider adapter implementing activity fetching via REST API
///
/// Uses Google Calendar API v3 to fetch events across the user's calendars
/// and normalizes them to UnifiedActivity records with type=.meeting.
/// Pagination is handled via pageToken. All-day events are supported.
public final class GoogleCalendarProviderAdapter: ProviderAdapter, Sendable {
    public let provider = Provider.googleCalendar

    private let httpClient: HTTPClient
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    public init(httpClient: HTTPClient = .shared) {
        self.httpClient = httpClient
    }

    // MARK: - ProviderAdapter Protocol

    public func fetchActivities(for account: Account, token: String, from: Date, to: Date) async throws -> [UnifiedActivity] {
        // Determine which calendars to fetch from:
        // - If user selected specific calendars (account.calendarIds), use only those
        // - Otherwise fall back to fetching all accessible calendars
        let calendarIdsToFetch: [String]
        if let selectedIds = account.calendarIds, !selectedIds.isEmpty {
            calendarIdsToFetch = selectedIds
        } else {
            let allCalendars = try await listCalendars(token: token)
            calendarIdsToFetch = allCalendars.map { $0.id }
        }

        var activities: [UnifiedActivity] = []

        // Fetch events for each selected calendar in the window
        for calendarId in calendarIdsToFetch {
            do {
                let events = try await listEvents(calendarId: calendarId, token: token, from: from, to: to)
                for event in events {
                    // Only include events where the current user is an attendee
                    // This filters out events from shared calendars where user isn't involved
                    guard isUserAttendee(event) else { continue }

                    // Apply response status filter if enabled
                    if account.showOnlyAcceptedEvents {
                        guard shouldIncludeBasedOnResponseStatus(event) else { continue }
                    }

                    // Apply all-day event filter if enabled
                    if account.hideAllDayEvents {
                        guard !isAllDayEvent(event) else { continue }
                    }

                    if let activity = normalizeEvent(event, accountId: account.id, calendarId: calendarId) {
                        activities.append(activity)
                    }
                }
            } catch let error as ProviderError {
                // Re-throw authentication errors so token refresh can be triggered
                if case .authenticationFailed = error {
                    throw error
                }
                // Skip other per-calendar errors (permission denied, calendar not found, etc.)
                continue
            } catch {
                // Skip non-provider errors (decoding failures, etc.)
                continue
            }
        }

        // Sort by timestamp descending
        activities.sort { $0.timestamp > $1.timestamp }

        return activities
    }

    /// Check if the current user is an attendee of this event
    /// Uses the `self` field from Google Calendar API which indicates if the attendee is the authenticated user
    private func isUserAttendee(_ event: CalendarEvent) -> Bool {
        // Events without attendees are typically personal events created by the user
        // (e.g., reminders, focus time) - include these
        guard let attendees = event.attendees, !attendees.isEmpty else {
            return true
        }

        // Check if the current user is in the attendees list
        return attendees.contains { $0.selfAttendee == true }
    }

    /// Check if event should be included based on response status filter
    /// Returns true if the event should be shown when showOnlyAcceptedEvents is enabled
    private func shouldIncludeBasedOnResponseStatus(_ event: CalendarEvent) -> Bool {
        // Events without attendees are personal events - always show
        guard let attendees = event.attendees, !attendees.isEmpty else {
            return true
        }

        // Find the current user's attendee record
        guard let userAttendee = attendees.first(where: { $0.selfAttendee == true }) else {
            return true  // No user attendee found (shouldn't happen)
        }

        // If no response status, assume it's important (e.g., organizer's event)
        guard let status = userAttendee.responseStatus else {
            return true
        }

        // Only show if status is "accepted"
        return status == "accepted"
    }

    /// Check if an event is an all-day event
    /// All-day events have a date but no dateTime
    private func isAllDayEvent(_ event: CalendarEvent) -> Bool {
        return event.start.date != nil && event.start.dateTime == nil
    }

    public func fetchHeatmap(for account: Account, token: String, from: Date, to: Date) async throws -> [HeatMapBucket] {
        let activities = try await fetchActivities(for: account, token: token, from: from, to: to)
        return HeatmapGenerator.generateBuckets(from: activities)
    }

    // MARK: - API Models

    private struct CalendarListResponse: Codable, Sendable {
        let items: [CalendarListEntry]?
    }

    private struct CalendarListEntry: Codable, Sendable {
        let id: String
        let summary: String?
        let primary: Bool?
    }

    private struct EventsResponse: Codable, Sendable {
        let items: [CalendarEvent]?
        let nextPageToken: String?
    }

    private struct EventDateTime: Codable, Sendable {
        // For all-day events
        let date: String?
        // For timed events
        let dateTime: String?
        let timeZone: String?
    }

    private struct Attendee: Codable, Sendable {
        let email: String?
        let displayName: String?
        let organizer: Bool?
        let selfAttendee: Bool?
        let responseStatus: String?  // "accepted", "declined", "tentative", "needsAction"

        private enum CodingKeys: String, CodingKey {
            case email
            case displayName
            case organizer
            case selfAttendee = "self"
            case responseStatus
        }
    }

    private struct CalendarEvent: Codable, Sendable {
        let id: String
        let summary: String?
        let description: String?
        let htmlLink: String?
        let start: EventDateTime
        let end: EventDateTime?
        let attendees: [Attendee]?
    }

    // MARK: - API Calls

    private func listCalendars(token: String) async throws -> [CalendarListEntry] {
        guard var components = URLComponents(string: "\(baseURL)/users/me/calendarList") else {
            throw ProviderError.configurationError("Invalid Google Calendar base URL")
        }
        // Minimal fields for list view
        components.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "maxResults", value: "250")
        ]

        guard let url = components.url else {
            throw ProviderError.configurationError("Failed to build calendar list URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: CalendarListResponse = try await httpClient.executeRequest(request, decoding: CalendarListResponse.self)
        return response.items ?? []
    }

    private func listEvents(calendarId: String, token: String, from: Date, to: Date) async throws -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        var pageToken: String?
        let timeMin = DateFormatting.iso8601String(from: from)
        let timeMax = DateFormatting.iso8601String(from: to)

        // Safety cap
        let maxPages = 20
        var pageCount = 0

        repeat {
            guard var components = URLComponents(string: "\(baseURL)/calendars/\(calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId)/events") else {
                throw ProviderError.configurationError("Invalid events URL components")
            }
            var query: [URLQueryItem] = [
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500"),
                URLQueryItem(name: "showDeleted", value: "false")
            ]
            if let token = pageToken { query.append(URLQueryItem(name: "pageToken", value: token)) }
            components.queryItems = query

            guard let url = components.url else {
                throw ProviderError.configurationError("Failed to build events URL")
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let response: EventsResponse = try await httpClient.executeRequest(request, decoding: EventsResponse.self)
            let pageItems = response.items ?? []
            if pageItems.isEmpty { break }
            events.append(contentsOf: pageItems)

            pageToken = response.nextPageToken
            pageCount += 1
        } while pageToken != nil && pageCount < maxPages

        return events
    }

    // MARK: - Normalization

    private func normalizeEvent(_ event: CalendarEvent, accountId: String, calendarId: String) -> UnifiedActivity? {
        // Determine timestamp and whether it's an all-day event
        let timestamp: Date
        let endTimestamp: Date?
        let isAllDay: Bool

        if let dt = event.start.dateTime, let parsed = DateFormatting.parseISO8601(dt) {
            // Timed event
            timestamp = parsed
            isAllDay = false
            // Parse end time if available
            if let endDt = event.end?.dateTime, let endParsed = DateFormatting.parseISO8601(endDt) {
                endTimestamp = endParsed
            } else {
                endTimestamp = nil
            }
        } else if let dateOnly = event.start.date, let parsed = DateFormatting.parseDate(dateOnly) {
            // All-day event -> treat as start of day
            timestamp = parsed
            isAllDay = true
            // Parse end date if available
            if let endDateOnly = event.end?.date, let endParsed = DateFormatting.parseDate(endDateOnly) {
                endTimestamp = endParsed
            } else {
                endTimestamp = nil
            }
        } else {
            // Unable to parse, skip
            return nil
        }

        // Build participant names for backward compatibility
        let participants: [String]? = {
            guard let attendees = event.attendees else { return nil }
            var names: [String] = []
            for a in attendees {
                if let name = a.displayName, !name.isEmpty {
                    names.append(name)
                } else if let email = a.email, !email.isEmpty {
                    names.append(email)
                }
            }
            return names.isEmpty ? nil : names
        }()

        // Build attendees with Gravatar avatars
        let attendeesWithAvatars: [Participant]? = {
            guard let eventAttendees = event.attendees else { return nil }
            var result: [Participant] = []
            for a in eventAttendees {
                let displayName = a.displayName ?? a.email ?? "Unknown"
                let avatarURL = a.email.flatMap { gravatarURL(for: $0) }
                result.append(Participant(username: displayName, avatarURL: avatarURL))
            }
            return result.isEmpty ? nil : result
        }()

        return UnifiedActivity(
            id: "google-calendar:\(accountId):event-\(event.id)",
            provider: .googleCalendar,
            accountId: accountId,
            sourceId: event.id,
            type: .meeting,
            timestamp: timestamp,
            title: event.summary,
            summary: event.description,
            participants: participants,
            url: event.htmlLink.flatMap(URL.init(string:)),
            endTimestamp: endTimestamp,
            isAllDay: isAllDay,
            attendees: attendeesWithAvatars,
            calendarId: calendarId
        )
    }

    /// Generate Gravatar URL from email address
    private func gravatarURL(for email: String) -> URL? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let data = trimmedEmail.data(using: .utf8) else { return nil }

        // MD5 hash for Gravatar
        var digest = [UInt8](repeating: 0, count: 16)
        _ = data.withUnsafeBytes { bytes in
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        // Return Gravatar URL with default avatar fallback
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=40&d=mp")
    }
}
