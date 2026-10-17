import Foundation

extension Calendar {
    /// Gregorian calendar in Europe/Stockholm. All period math in BudgetCore uses it.
    public static let stockholm: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.locale = Locale(identifier: "sv_SE")
        return calendar
    }()
}
