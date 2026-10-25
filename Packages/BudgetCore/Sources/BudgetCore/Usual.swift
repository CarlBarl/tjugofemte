import Foundation

/// What a category usually costs per period: "usually 3 600 kr, based on 12 periods".
public struct UsualAmount: Equatable, Sendable {
    public let amount: Decimal
    /// Complete periods the mean is built on. 0 means the current period so far was used.
    public let periods: Int
}

/// The mean of each spending category's per-period totals over the complete periods on the phone.
public enum Usual {
    static let minimumAmount: Decimal = 50
    static let step: Decimal = 50

    /// Periods with no spending in a category count as zero. A category in `quarterly` is a third of its quarterly amount instead.
    public static func perCategory(transactions: [Transaction], rule: PeriodRule, quarterly: [String: Decimal] = [:],
                                   today: Date = Date(), maxPeriods: Int = 12) -> [String: UsualAmount] {
        let spending = transactions.filter { categoryKind($0.categoryID) == .spending }
        var periods = completePeriods(transactions: transactions, rule: rule, today: today, maxPeriods: maxPeriods)
        let complete = periods.count
        if periods.isEmpty { periods = [rule.period(containing: today)] }

        var totals: [String: Decimal] = [:]
        for t in spending where periods.contains(where: { $0.contains(t.bookingDate) }) {
            totals[t.categoryID, default: 0] -= t.amount
        }
        var usual: [String: UsualAmount] = [:]
        for (id, total) in totals {
            let mean = total / Decimal(periods.count)
            guard mean >= minimumAmount else { continue }
            usual[id] = UsualAmount(amount: PlanSuggestions.roundUp(mean, to: step), periods: complete)
        }
        for (id, amount) in quarterly {
            usual[id] = UsualAmount(amount: PlanSuggestions.roundUp(amount / 3, to: step), periods: complete)
        }
        return usual
    }

    /// The periods before the current one that the data fully covers, newest first, at most `maxPeriods`.
    static func completePeriods(transactions: [Transaction], rule: PeriodRule, today: Date, maxPeriods: Int) -> [PayPeriod] {
        guard let dataStart = transactions.map(\.bookingDate).min() else { return [] }
        var periods: [PayPeriod] = []
        var label = rule.period(containing: today).label.previous
        while periods.count < maxPeriods {
            let p = rule.period(labeled: label)
            guard p.start >= dataStart else { break }
            periods.append(p)
            label = label.previous
        }
        return periods
    }
}
