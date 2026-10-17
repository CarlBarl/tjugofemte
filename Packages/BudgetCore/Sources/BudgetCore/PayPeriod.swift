import Foundation

/// A payday period is named after the month it mostly covers:
/// 23 Oct to 24 Nov is "November", because the October salary pays November's bills.
public struct PeriodLabel: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public var next: PeriodLabel { month == 12 ? PeriodLabel(year: year + 1, month: 1) : PeriodLabel(year: year, month: month + 1) }
    public var previous: PeriodLabel { month == 1 ? PeriodLabel(year: year - 1, month: 12) : PeriodLabel(year: year, month: month - 1) }

    public static func < (lhs: PeriodLabel, rhs: PeriodLabel) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

public struct PayPeriod: Equatable, Sendable {
    public let label: PeriodLabel
    /// First day, midnight in Stockholm, inclusive.
    public let start: Date
    /// Last day, midnight in Stockholm, inclusive.
    public let end: Date

    public func contains(_ date: Date) -> Bool {
        let day = Calendar.stockholm.startOfDay(for: date)
        return day >= start && day <= end
    }
}

/// How the user's calendar is cut into payday periods.
public struct PeriodRule: Equatable, Sendable {
    /// Day of month the salary is due. 1 means plain calendar months with no banking-day adjustment.
    public let startDay: Int
    /// One-off starts for periods whose employer rule differs (December, typically).
    public let overrides: [PeriodLabel: Date]

    public init(startDay: Int, overrides: [PeriodLabel: Date] = [:]) {
        precondition((1...28).contains(startDay), "startDay must exist in every month")
        self.startDay = startDay
        self.overrides = overrides
    }

    public func period(labeled label: PeriodLabel) -> PayPeriod {
        let end = Calendar.stockholm.date(byAdding: .day, value: -1, to: start(of: label.next))!
        return PayPeriod(label: label, start: start(of: label), end: end)
    }

    public func period(containing date: Date) -> PayPeriod {
        let c = Calendar.stockholm.dateComponents([.year, .month], from: date)
        let guess = PeriodLabel(year: c.year!, month: c.month!)
        for label in [guess.previous, guess, guess.next, guess.next.next] {
            let p = period(labeled: label)
            if p.contains(date) { return p }
        }
        preconditionFailure("every date belongs to some period")
    }

    private func start(of label: PeriodLabel) -> Date {
        if let override = overrides[label] { return Calendar.stockholm.startOfDay(for: override) }
        // A start day late in the month belongs to the following month's period.
        let startMonth = startDay > 15 ? label.previous : label
        let nominal = Calendar.stockholm.date(from: DateComponents(year: startMonth.year, month: startMonth.month, day: startDay))!
        return startDay == 1 ? nominal : SwedishBankingDays.previousBankingDay(onOrBefore: nominal)
    }
}
