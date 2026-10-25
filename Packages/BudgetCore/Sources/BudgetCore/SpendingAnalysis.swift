import Foundation

/// A big want and where it is heading: "Takeaway 3 600 kr a month, up 20 %".
public struct WantTrend: Equatable, Sendable {
    public let categoryID: String
    /// Mean money out per period, refunds netted.
    public let perPeriod: Decimal
    /// The last three periods' mean against the older periods' mean, in whole percent. nil with fewer than six periods,
    /// or when the older periods have no spending to compare with.
    public let changePercent: Int?
}

/// How the money splits over the complete periods on the phone, for the setup's "Your money" step.
public struct SpendingAnalysis: Equatable, Sendable {
    /// The same cap as `Usual`, so every "based on N periods" on the screens agrees.
    static let maxPeriods = 12
    static let trendPeriods = 6
    static let recentPeriods = 3
    static let topWantCount = 3

    /// Complete periods the figures are built on. 0 means the current period so far was used.
    public let periods: Int
    /// Every income-kind transaction, matched to a source or not.
    public let incomePerPeriod: Decimal
    /// The part of the income that no source's keyword matches, such as Swish received.
    public let otherIncomePerPeriod: Decimal
    public let needsPerPeriod: Decimal
    public let wantsPerPeriod: Decimal
    /// Savings and transfers are neither income nor spending, so they are not in this.
    public var savedPerPeriod: Decimal { incomePerPeriod - needsPerPeriod - wantsPerPeriod }
    /// Saved as a share of income, negative when needs and wants are more than the income. nil without income.
    public var savingsRate: Decimal? { incomePerPeriod > 0 ? savedPerPeriod / incomePerPeriod : nil }
    /// The three biggest want categories, biggest first. Unsorted is in `wantsPerPeriod` but never here: it is not a real want.
    public let topWants: [WantTrend]

    /// Up to `maxPeriods` complete periods, the same 12 as `Usual` by default; 1 is the last complete period alone, for
    /// Overview's "last period 13 %".
    public static func analyze(transactions: [Transaction], rule: PeriodRule, groups: CategoryGroups,
                               incomeSources: [IncomeSource], today: Date = Date(), maxPeriods: Int = 12) -> SpendingAnalysis {
        var periods = Usual.completePeriods(transactions: transactions, rule: rule, today: today, maxPeriods: maxPeriods)
        let complete = periods.count
        if periods.isEmpty { periods = [rule.period(containing: today)] }
        let keywords = incomeSources.compactMap(\.keyword)

        var income: Decimal = 0
        var otherIncome: Decimal = 0
        var needs: Decimal = 0
        // Money out per want category in each period, newest first; a period without spending stays zero.
        var wants: [String: [Decimal]] = [:]
        for t in transactions {
            guard let index = periods.firstIndex(where: { $0.contains(t.bookingDate) }) else { continue }
            switch categoryKind(t.categoryID) {
            case .income:
                income += t.amount
                let text = Categorizer.normalize(t.counterparty)
                if !keywords.contains(where: { Categorizer.matches($0, in: text) }) { otherIncome += t.amount }
            case .spending:
                switch groups.group(of: t.categoryID) {
                case .need: needs -= t.amount
                case .want: wants[t.categoryID, default: Array(repeating: 0, count: periods.count)][index] -= t.amount
                case .saving, nil: break
                }
            case .saving, .transfer:
                break
            }
        }

        let count = Decimal(periods.count)
        let top = wants.map { id, totals in
            WantTrend(categoryID: id, perPeriod: totals.reduce(0, +) / count, changePercent: changePercent(totals))
        }
        .filter { $0.categoryID != DefaultCategory.unsorted.rawValue && $0.perPeriod > 0 }
        .sorted { ($0.perPeriod, $1.categoryID) > ($1.perPeriod, $0.categoryID) }
        .prefix(topWantCount)
        let wantsTotal = wants.values.reduce(Decimal(0)) { $0 + $1.reduce(0, +) }
        return SpendingAnalysis(periods: complete, incomePerPeriod: income / count, otherIncomePerPeriod: otherIncome / count,
                                needsPerPeriod: needs / count, wantsPerPeriod: wantsTotal / count, topWants: Array(top))
    }

    /// `totals` is newest first: the first three periods are the recent ones, the rest are what they are compared with.
    static func changePercent(_ totals: [Decimal]) -> Int? {
        guard totals.count >= trendPeriods else { return nil }
        let recent = totals.prefix(recentPeriods).reduce(0, +) / Decimal(recentPeriods)
        let older = totals.dropFirst(recentPeriods)
        let before = older.reduce(0, +) / Decimal(older.count)
        guard before > 0 else { return nil }
        var percent = (recent - before) / before * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &percent, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

/// "Adjust plan?" on Overview, once a complete period ends more than 5 % of planned income in the red.
public enum GoalNudge {
    /// A quarterly payment beyond its third of the period was set aside by the plan in the periods before, so it is added
    /// back to left over first: a CSN month that is otherwise on plan does not nudge. Left over itself is not changed.
    public static func shouldShow(lastComplete: PeriodSummary, plannedIncome: Decimal, budgets: [Budget], transactions: [Transaction]) -> Bool {
        let period = lastComplete.period
        var setAside: Decimal = 0
        for b in budgets where b.cadence != .monthly {
            let spent = transactions.filter { $0.categoryID == b.categoryID && period.contains($0.bookingDate) }.reduce(Decimal(0)) { $0 - $1.amount }
            setAside += max(0, spent - b.amount / 3)
        }
        return lastComplete.leftOverSoFar.value + setAside < -plannedIncome * 5 / 100
    }

    /// "Takeaway went 1 210 kr over": the monthly budget the period overran by the most kronor. nil when none did.
    public static func biggestOverrun(lastComplete: PeriodSummary) -> CategoryLine? {
        lastComplete.categories
            .filter { ($0.remaining ?? 0) < 0 }
            .min { ($0.remaining ?? 0, $0.categoryID) < ($1.remaining ?? 0, $1.categoryID) }
    }
}
