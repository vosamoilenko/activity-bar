import SwiftUI

/// Avatar view that loads remote images with placeholder fallback
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholderView: some View {
        Circle()
            .fill(Color(nsColor: .separatorColor))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Avatar Stack View

import Core

/// Overlapping avatar circles for showing multiple participants
struct AvatarStackView: View {
    let participants: [Participant]
    var size: CGFloat = 16
    var maxVisible: Int = 4
    var overlap: CGFloat = 0.35  // Overlap as fraction of size

    var body: some View {
        HStack(spacing: -(size * overlap)) {
            ForEach(Array(visibleParticipants.enumerated()), id: \.element.id) { index, participant in
                AvatarView(url: participant.avatarURL, size: size)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
                    .zIndex(Double(visibleParticipants.count - index))  // First avatar on top
            }

            // Show +N indicator if there are more participants
            if overflowCount > 0 {
                Circle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("+\(overflowCount)")
                            .font(.system(size: size * 0.45, weight: .medium))
                            .foregroundStyle(.secondary)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
            }
        }
    }

    private var visibleParticipants: [Participant] {
        Array(participants.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, participants.count - maxVisible)
    }
}

// MARK: - Previews
#Preview("With URL") {
    AvatarView(url: URL(string: "https://avatars.githubusercontent.com/u/1?v=4"))
        .padding()
}

#Preview("Without URL") {
    AvatarView(url: nil)
        .padding()
}

#Preview("Custom Size") {
    HStack(spacing: 8) {
        AvatarView(url: nil, size: 16)
        AvatarView(url: nil, size: 20)
        AvatarView(url: nil, size: 24)
        AvatarView(url: nil, size: 32)
    }
    .padding()
}

#Preview("Avatar Stack - Few") {
    AvatarStackView(participants: [
        Participant(username: "alice", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1")),
        Participant(username: "bob", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/2")),
    ])
    .padding()
}

#Preview("Avatar Stack - Many") {
    AvatarStackView(participants: [
        Participant(username: "alice", avatarURL: nil),
        Participant(username: "bob", avatarURL: nil),
        Participant(username: "charlie", avatarURL: nil),
        Participant(username: "david", avatarURL: nil),
        Participant(username: "eve", avatarURL: nil),
        Participant(username: "frank", avatarURL: nil),
    ])
    .padding()
}
