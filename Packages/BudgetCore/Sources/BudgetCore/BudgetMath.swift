import Foundation

/// A number plus the terms that produced it, so the UI can show "how is this calculated".
public struct Explained: Equatable, Sendable {
    public enum Kind: Sendable {
        case plannedIncome, categoryBudgets, quarterlySetAside, actualIncome, actualSpending, savingsTarget, incomeShortfall
    }
    public struct Term: Equatable, Sendable {
        public let kind: Kind
        /// Signed contribution to the total.
        public let amount: Decimal
    }
    public let terms: [Term]
    public var value: Decimal { terms.reduce(0) { $0 + $1.amount } }

    init(_ terms: [(Kind, Decimal)]) {
        self.terms = terms.map { Term(kind: $0.0, amount: $0.1) }
    }
}

public struct CategoryLine: Equatable, Sendable {
    public let categoryID: String
    public let budget: Decimal?
    /// Money out, positive number. Refunds in the same category reduce it.
    public let actual: Decimal
    public var remaining: Decimal? { budget.map { $0 - actual } }
}

public struct QuarterlyLine: Equatable, Sendable {
    public let categoryID: String
    public let quarterlyAmount: Decimal
    public let setAsidePerPeriod: Decimal
    public let setAsideSoFar: Decimal
    public let paidSoFar: Decimal
}

public struct IncomeLine: Equatable, Sendable {
    public let sourceID: String
    public let planned: Decimal
    /// nil for plan-only sources (no keyword), 0 when nothing matched yet.
    public let actual: Decimal?
}

public struct PeriodSummary: Equatable, Sendable {
    public let period: PayPeriod
    public let savingsTarget: Explained
    /// Present once a matched income source has arrived below plan.
    public let adjustedSavingsTarget: Explained?
    public let categories: [CategoryLine]
    public let quarterly: [QuarterlyLine]
    public let incomes: [IncomeLine]
    public let otherIncome: Decimal
    public let leftOverSoFar: Explained
}

public enum BudgetMath {
    public static func summarize(period: PayPeriod, rule: PeriodRule, transactions: [Transaction],
                                 budgets: [Budget], incomeSources: [IncomeSource]) -> PeriodSummary {
        let inPeriod = transactions.filter { period.contains($0.bookingDate) }
        let spending = inPeriod.filter { categoryKind($0.categoryID) == .spending }
        let income = inPeriod.filter { categoryKind($0.categoryID) == .income }

        let monthly = budgets.filter { $0.cadence == .monthly }
        let quarterlyBudgets = budgets.filter { $0.cadence != .monthly }
        let quarterlyIDs = Set(quarterlyBudgets.map(\.categoryID))

        // Category lines: every monthly budget, plus any spending category seen this period.
        var actualByCategory: [String: Decimal] = [:]
        for t in spending { actualByCategory[t.categoryID, default: 0] -= t.amount }
        let lineIDs = Set(monthly.map(\.categoryID)).union(actualByCategory.keys).subtracting(quarterlyIDs)
        let categories = lineIDs.sorted().map { id in
            CategoryLine(categoryID: id, budget: monthly.first { $0.categoryID == id }?.amount, actual: actualByCategory[id] ?? 0)
        }

        let quarterly = quarterlyBudgets.map { quarterlyLine(for: $0, period: period, rule: rule, transactions: transactions) }

        // Income matched to sources by keyword; the rest is "other income".
        var unmatched = income
        let incomes = incomeSources.map { source -> IncomeLine in
            guard let keyword = source.keyword else { return IncomeLine(sourceID: source.id, planned: source.plannedAmount, actual: nil) }
            let hits = unmatched.filter { Categorizer.matches(keyword, in: Categorizer.normalize($0.counterparty)) }
            unmatched.removeAll { t in hits.contains { $0.dedupKey == t.dedupKey } }
            return IncomeLine(sourceID: source.id, planned: source.plannedAmount, actual: hits.reduce(0) { $0 + $1.amount })
        }
        let otherIncome = unmatched.reduce(0) { $0 + $1.amount }

        let plannedIncome = incomeSources.reduce(0) { $0 + $1.plannedAmount }
        let monthlyTotal = monthly.reduce(0) { $0 + $1.amount }
        let setAside = quarterly.reduce(0) { $0 + $1.setAsidePerPeriod }
        let target = Explained([(.plannedIncome, plannedIncome), (.categoryBudgets, -monthlyTotal), (.quarterlySetAside, -setAside)])

        // A source that has arrived below plan lowers the target; one not yet received does not.
        let shortfall = incomes.reduce(Decimal(0)) { sum, line in
            guard let actual = line.actual, actual > 0, actual < line.planned else { return sum }
            return sum + (line.planned - actual)
        }
        let adjusted = shortfall > 0 ? Explained([(.savingsTarget, target.value), (.incomeShortfall, -shortfall)]) : nil

        let actualIncome = income.reduce(0) { $0 + $1.amount }
        let actualSpending = spending.reduce(0) { $0 - $1.amount }
        let leftOver = Explained([(.actualIncome, actualIncome), (.actualSpending, -actualSpending), (.savingsTarget, -target.value)])

        return PeriodSummary(period: period, savingsTarget: target, adjustedSavingsTarget: adjusted, categories: categories,
                             quarterly: quarterly, incomes: incomes, otherIncome: otherIncome, leftOverSoFar: leftOver)
    }

    /// The quarter is the three periods ending at the next due month on or after this period.
    static func quarterlyLine(for budget: Budget, period: PayPeriod, rule: PeriodRule, transactions: [Transaction]) -> QuarterlyLine {
        guard case .quarterly(let firstDue) = budget.cadence else { preconditionFailure("monthly budget passed as quarterly") }
        let monthsUntilDue = ((firstDue - period.label.month) % 3 + 3) % 3
        let indexInQuarter = 2 - monthsUntilDue  // 0, 1 or 2
        var first = period.label
        for _ in 0..<indexInQuarter { first = first.previous }
        let quarterStart = rule.period(labeled: first).start
        let paid = transactions
            .filter { $0.categoryID == budget.categoryID && $0.bookingDate >= quarterStart && $0.bookingDate <= period.end }
            .reduce(Decimal(0)) { $0 - $1.amount }
        let perPeriod = budget.amount / 3
        return QuarterlyLine(categoryID: budget.categoryID, quarterlyAmount: budget.amount, setAsidePerPeriod: perPeriod,
                             setAsideSoFar: perPeriod * Decimal(indexInQuarter + 1), paidSoFar: paid)
    }
}
