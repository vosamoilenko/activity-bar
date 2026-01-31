import SwiftUI
import Core

/// Small badge showing provider icon.
///
/// Displays a compact icon representing the data source provider:
/// - GitLab: `g.square` SF Symbol
/// - Azure DevOps: `cloud.fill` SF Symbol
/// - Google Calendar: `calendar` SF Symbol
///
/// Integrates with MenuHighlighting environment for automatic color adaptation.
///
/// Usage:
/// ```swift
/// ProviderBadgeView(provider: .gitlab)
/// ```
struct ProviderBadgeView: View {
    let provider: Provider

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 10))
            .frame(width: 12, height: 12)
            .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
    }

    // MARK: - Helpers

    /// Maps Provider to SF Symbol name
    private var symbolName: String {
        switch provider {
        case .gitlab:
            return "g.square"
        case .azureDevops:
            return "cloud.fill"
        case .googleCalendar:
            return "calendar"
        }
    }
}

// MARK: - Previews

#Preview("GitLab Badge") {
    ProviderBadgeView(provider: .gitlab)
        .environment(\.menuItemHighlighted, false)
}

#Preview("Azure DevOps Badge") {
    ProviderBadgeView(provider: .azureDevops)
        .environment(\.menuItemHighlighted, false)
}

#Preview("Google Calendar Badge") {
    ProviderBadgeView(provider: .googleCalendar)
        .environment(\.menuItemHighlighted, false)
}

#Preview("Highlighted State") {
    HStack(spacing: 12) {
        ProviderBadgeView(provider: .gitlab)
        ProviderBadgeView(provider: .azureDevops)
        ProviderBadgeView(provider: .googleCalendar)
    }
    .environment(\.menuItemHighlighted, true)
}
