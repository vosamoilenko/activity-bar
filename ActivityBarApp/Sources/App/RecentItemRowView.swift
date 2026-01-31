import SwiftUI

/// Generic base layout for activity items following RepoBar's design pattern.
///
/// Provides a flexible HStack with leading view (avatar/icon), content area, and configurable spacing/padding.
/// Handles tap gestures and provides proper content shape for interaction.
///
/// Usage:
/// ```swift
/// RecentItemRowView(onOpen: { openURL(activity.url) }) {
///     AvatarView(url: activity.authorAvatarURL)
/// } content: {
///     VStack(alignment: .leading, spacing: 2) {
///         Text(activity.title)
///         Text(activity.summary)
///     }
/// }
/// ```
struct RecentItemRowView<Leading: View, Content: View>: View {
    let alignment: VerticalAlignment
    let leadingSpacing: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let onOpen: () -> Void
    let leading: Leading
    let content: Content

    init(
        alignment: VerticalAlignment = .top,
        leadingSpacing: CGFloat = 8,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 6,
        onOpen: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.leadingSpacing = leadingSpacing
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.onOpen = onOpen
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        HStack(alignment: self.alignment, spacing: self.leadingSpacing) {
            self.leading
            self.content
            Spacer(minLength: 2)
        }
        .padding(.horizontal, self.horizontalPadding)
        .padding(.vertical, self.verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { self.onOpen() }
    }
}
