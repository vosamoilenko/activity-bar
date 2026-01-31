import Foundation
import Core

/// Maps ActivityType to SF Symbol names for visual representation
public enum ActivityIconMapper {
    /// Returns the SF Symbol name for a given ActivityType
    public static func symbolName(for activityType: ActivityType) -> String {
        switch activityType {
        case .commit:
            return "arrow.up.circle"
        case .pullRequest:
            return "arrow.triangle.branch"
        case .issue:
            return "exclamationmark.circle"
        case .issueComment:
            return "text.bubble"
        case .codeReview:
            return "checkmark.bubble"
        case .meeting:
            return "calendar"
        case .workItem:
            return "checklist"
        case .deployment:
            return "shippingbox"
        case .release:
            return "tag"
        case .wiki:
            return "book"
        case .other:
            return "clock"
        }
    }
}
