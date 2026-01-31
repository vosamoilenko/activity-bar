import Foundation

/// Formats dates as time strings.
public enum RelativeTimeFormatter {
    private static let exactTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Formats a date as exact time (HH:MM)
    /// - Parameter date: The date to format
    /// - Returns: Time string (e.g., "14:30")
    public static func string(from date: Date) -> String {
        exactTimeFormatter.string(from: date)
    }

    /// Formats a date as a relative string compared to a reference date.
    /// - Parameters:
    ///   - date: The date to format
    ///   - now: The reference date to compare against
    /// - Returns: Localized relative time string (e.g., "2h ago", "1d ago")
    public static func relativeString(from date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
