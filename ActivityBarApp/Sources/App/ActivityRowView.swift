import SwiftUI
import Core

/// Generic activity row view for displaying any UnifiedActivity type.
///
/// Uses RecentItemRowView as base layout with:
/// - Activity type icon in leading position
/// - Title in .callout.weight(.medium), lineLimit 2
/// - Metadata row: provider icon, author, relative time
/// - For meetings: shows time/duration and attendee avatars
/// - Responds to highlight state via MenuHighlighting environment
/// - Opens URL on click (if available)
///
/// Usage:
/// ```swift
/// ActivityRowView(activity: activity)
/// ```
struct ActivityRowView: View {
    let activity: UnifiedActivity

    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.showEventAuthor) private var showEventAuthor

    var body: some View {
        RecentItemRowView(onOpen: openActivityURL) {
            // Leading: Activity type icon
            activityTypeIcon
        } content: {
            // Content: Title + metadata
            VStack(alignment: .leading, spacing: 2) {
                // Title
                if let title = activity.title {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(MenuHighlightStyle.primary(isHighlighted))
                }

                // Author line (when showEventAuthor is enabled)
                if showEventAuthor, let participants = activity.participants, let author = participants.first {
                    Text("by \(author)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)
                }

                // Metadata row - specialized for meetings
                if activity.type == .meeting {
                    meetingMetadataRow
                } else {
                    metadataRow
                }
            }
        }
    }

    // MARK: - Subviews

    private var activityTypeIcon: some View {
        let symbolName = ActivityIconMapper.symbolName(for: activity.type)
        return Image(systemName: symbolName)
            .font(.system(size: 14))
            .frame(width: 20, height: 20)
            .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            // Provider icon
            providerBadge

            // Author avatar (if available)
            if let avatarURL = activity.authorAvatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        authorInitialsView
                    @unknown default:
                        authorInitialsView
                    }
                }
                .frame(width: 16, height: 16)
                .clipShape(Circle())
            }

            // Author (first participant)
            if let participants = activity.participants, let author = participants.first {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                    .lineLimit(1)
            }

            // Relative time
            Text(RelativeTimeFormatter.string(from: activity.timestamp))
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
                .lineLimit(1)
        }
    }

    /// Fallback author initials view
    private var authorInitialsView: some View {
        let name = activity.participants?.first ?? ""
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        return Text(initials.isEmpty ? String(name.prefix(1)).uppercased() : initials)
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(isHighlighted ? MenuHighlightStyle.selectionText : .white)
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(isHighlighted ? Color.white.opacity(0.3) : Color.blue.opacity(0.7))
            )
    }

    /// Specialized metadata row for calendar meetings
    private var meetingMetadataRow: some View {
        HStack(spacing: 6) {
            // Time display (e.g., "10:00 AM" or "All Day")
            if activity.isAllDay == true {
                Text("All Day")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
            } else {
                Text(formatMeetingTime())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
            }

            // Duration (if available and not all-day)
            if activity.isAllDay != true, let duration = formatDuration() {
                Text("•")
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
                Text(duration)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
            }

            Spacer()

            // Attendee avatars
            if let attendees = activity.attendees, !attendees.isEmpty {
                attendeeAvatarsView(attendees: attendees)
            }
        }
    }

    /// Format meeting start time
    private func formatMeetingTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: activity.timestamp)
    }

    /// Format meeting duration
    private func formatDuration() -> String? {
        guard let endTimestamp = activity.endTimestamp else { return nil }
        let duration = endTimestamp.timeIntervalSince(activity.timestamp)

        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        }
        return nil
    }

    /// Attendee avatar circles
    private func attendeeAvatarsView(attendees: [Participant]) -> some View {
        let maxDisplay = 4
        let displayAttendees = Array(attendees.prefix(maxDisplay))
        let extraCount = attendees.count - maxDisplay

        return HStack(spacing: -6) {
            ForEach(displayAttendees.indices, id: \.self) { index in
                let attendee = displayAttendees[index]
                avatarView(for: attendee)
                    .zIndex(Double(displayAttendees.count - index))
            }

            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isHighlighted ? MenuHighlightStyle.selectionText : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isHighlighted ? Color.white.opacity(0.2) : Color.gray.opacity(0.2))
                    )
                    .zIndex(0)
            }
        }
    }

    /// Single avatar view
    private func avatarView(for participant: Participant) -> some View {
        Group {
            if let avatarURL = participant.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        initialsView(for: participant.username)
                    @unknown default:
                        initialsView(for: participant.username)
                    }
                }
            } else {
                initialsView(for: participant.username)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(isHighlighted ? Color.white.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    /// Fallback initials view
    private func initialsView(for name: String) -> some View {
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        return Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(isHighlighted ? MenuHighlightStyle.selectionText : .white)
            .frame(width: 18, height: 18)
            .background(
                Circle()
                    .fill(isHighlighted ? Color.white.opacity(0.3) : Color.blue.opacity(0.7))
            )
    }

    private var providerBadge: some View {
        Text(providerShortName)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
    }

    // MARK: - Helpers

    private var providerShortName: String {
        switch activity.provider {
        case .gitlab: return "GL"
        case .azureDevops: return "ADO"
        case .googleCalendar: return "Cal"
        }
    }

    private func openActivityURL() {
        guard let url = activity.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Previews

#Preview("Commit Activity") {
    ActivityRowView(
        activity: UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "abc123",
            type: .commit,
            timestamp: Date().addingTimeInterval(-3600),
            title: "Fix authentication bug in login flow",
            summary: "Updated token validation logic",
            participants: ["jdoe"],
            url: URL(string: "https://gitlab.com/example/repo/-/commit/abc123")
        )
    )
    .environment(\.menuItemHighlighted, false)
}

#Preview("Pull Request Activity") {
    ActivityRowView(
        activity: UnifiedActivity(
            id: "2",
            provider: .gitlab,
            accountId: "test",
            sourceId: "pr-456",
            type: .pullRequest,
            timestamp: Date().addingTimeInterval(-86400),
            title: "Add user authentication feature",
            summary: "Implements OAuth flow with GitLab",
            participants: ["alice", "bob"],
            url: URL(string: "https://gitlab.com/example/repo/-/merge_requests/456")
        )
    )
    .environment(\.menuItemHighlighted, false)
}

#Preview("Issue Activity") {
    ActivityRowView(
        activity: UnifiedActivity(
            id: "3",
            provider: .gitlab,
            accountId: "test",
            sourceId: "issue-789",
            type: .issue,
            timestamp: Date().addingTimeInterval(-7200),
            title: "App crashes on startup in production",
            summary: "Users reporting crash on macOS 14.5",
            participants: ["charlie"],
            url: URL(string: "https://gitlab.com/example/project/-/issues/789")
        )
    )
    .environment(\.menuItemHighlighted, false)
}

#Preview("Meeting Activity") {
    ActivityRowView(
        activity: UnifiedActivity(
            id: "4",
            provider: .googleCalendar,
            accountId: "test",
            sourceId: "event-xyz",
            type: .meeting,
            timestamp: Date().addingTimeInterval(-1800),
            title: "Sprint Planning - Q1 2026",
            summary: "Discuss roadmap priorities",
            participants: ["alice", "bob", "charlie"],
            url: URL(string: "https://meet.google.com/abc-defg-hij")
        )
    )
    .environment(\.menuItemHighlighted, false)
}

#Preview("Highlighted State") {
    ActivityRowView(
        activity: UnifiedActivity(
            id: "5",
            provider: .azureDevops,
            accountId: "test",
            sourceId: "wi-123",
            type: .workItem,
            timestamp: Date().addingTimeInterval(-300),
            title: "Implement dark mode support",
            summary: "Add theme switching",
            participants: ["diana"],
            url: URL(string: "https://dev.azure.com/org/project/_workitems/edit/123")
        )
    )
    .environment(\.menuItemHighlighted, true)
}

#Preview("No Title") {
    ActivityRowView(
        activity: UnifiedActivity(
            id: "6",
            provider: .gitlab,
            accountId: "test",
            sourceId: "other-1",
            type: .other,
            timestamp: Date().addingTimeInterval(-60),
            title: nil,
            summary: nil,
            participants: nil,
            url: nil
        )
    )
    .environment(\.menuItemHighlighted, false)
}
