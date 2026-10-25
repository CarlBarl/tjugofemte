import Foundation

/// Between what the phone stores and the goal planner: the planner's input from the transactions, the plan as budget
/// rows, and a budget edited by hand as a heart.
public enum GoalSetup {
    /// A need with a budget is planned at that budget, a quarterly one at a third of it; a need without one at its usual.
    /// Wants are at their usual, fixed when recurring charges make them up, and Unsorted always is. A want with a budget
    /// but no usual, such as a gym set before its first charge, is fixed at its budget per period, so a plan keeps it.
    /// Wants are biggest first, as the Goal screen lists them.
    public static func input(plannedIncome: Decimal, transactions: [Transaction], rule: PeriodRule, budgets: [Budget],
                             groups: CategoryGroups, today: Date = Date()) -> GoalInput {
        var quarterly: [String: Decimal] = [:]
        for b in budgets where groups.group(of: b.categoryID) == .need {
            if case .quarterly = b.cadence { quarterly[b.categoryID] = b.amount }
        }
        let usual = Usual.perCategory(transactions: transactions, rule: rule, quarterly: quarterly, today: today)
        let charges = RecurringDetector.detect(transactions: transactions)
        let fixed = RecurringDetector.fixedCategories(transactions: transactions, charges: charges, groups: groups)
            .union([DefaultCategory.unsorted.rawValue])

        var needs: [String: Decimal] = [:]
        var wants: [WantInput] = []
        for (id, u) in usual {
            switch groups.group(of: id) {
            case .need: needs[id] = u.amount
            case .want: wants.append(WantInput(categoryID: id, usual: u.amount, fixed: fixed.contains(id)))
            case .saving, nil: break
            }
        }
        for b in budgets where usual[b.categoryID] == nil && groups.group(of: b.categoryID) == .want {
            wants.append(WantInput(categoryID: b.categoryID, usual: planned(b), fixed: true))
        }
        // Quarterly need budgets are already in `usual` as a third of themselves.
        for b in budgets where b.cadence == .monthly && groups.group(of: b.categoryID) == .need { needs[b.categoryID] = b.amount }
        wants.sort { ($0.usual, $1.categoryID) > ($1.usual, $0.categoryID) }
        let periods = Usual.completePeriods(transactions: transactions, rule: rule, today: today, maxPeriods: SpendingAnalysis.maxPeriods).count
        return GoalInput(plannedIncome: plannedIncome, needs: needs, wants: wants, quarterly: quarterly, periods: periods)
    }

    /// Needs without a budget that the recurring charges show are paid once a quarter, such as CSN on a first run: a
    /// quarterly budget at the charge, due in the month of the period it was last paid in. Given to `input` and
    /// `budgets` with the stored budgets, they plan a third each period instead of the payment averaged over every
    /// period, which would leave a CSN month 3 300 kr over. The biggest charge wins when a need has two.
    public static func quarterlyNeeds(transactions: [Transaction], rule: PeriodRule, groups: CategoryGroups, budgets: [Budget]) -> [Budget] {
        let budgeted = Set(budgets.map(\.categoryID))
        var found: [String: Budget] = [:]
        // Rent and CSN are kept in here; the detector leaves them out only for the Your money list.
        for c in RecurringDetector.detect(transactions: transactions, excluding: []) where c.cadence == .quarterly
            && groups.group(of: c.categoryID) == .need && !budgeted.contains(c.categoryID) && found[c.categoryID] == nil {
            found[c.categoryID] = Budget(categoryID: c.categoryID, amount: c.amount,
                                         cadence: .quarterly(firstDueMonth: rule.period(containing: c.lastSeen).label.month))
        }
        return found.values.sorted { $0.categoryID < $1.categoryID }
    }

    /// A need keeps its budget as it was, amount and cadence; a need without one gets its usual, monthly. Each want gets
    /// its planned budget, monthly, except a want budgeted quarterly: kept as it was when the plan leaves it at its third,
    /// else three times the plan rounded up to 50 kr, due in the same month. Sorted by category, as the store returns them.
    public static func budgets(input: GoalInput, prefs: GoalPreferences, existing: [Budget]) -> [Budget] {
        let plan = GoalPlanner.plan(input, prefs)
        let needs = input.needs.map { id, amount -> Budget in
            existing.first { $0.categoryID == id } ?? Budget(categoryID: id, amount: amount, cadence: .monthly)
        }
        let wants = plan.budgets.map { id, amount -> Budget in
            guard let old = existing.first(where: { $0.categoryID == id }), old.cadence != .monthly else {
                return Budget(categoryID: id, amount: amount, cadence: .monthly)
            }
            let third = PlanSuggestions.roundUp(amount, to: GoalPlanner.budgetStep)
            return third == planned(old) ? old : Budget(categoryID: id, amount: third * 3, cadence: old.cadence)
        }
        return (needs + wants).sorted { $0.categoryID < $1.categoryID }
    }

    /// The goal before the user moves anything: `GoalPlanner.defaultGoal` against the rate reachable with no hearts.
    public static func defaultPreferences(input: GoalInput, currentRate: Decimal?) -> GoalPreferences {
        let none = GoalPreferences(goalPercent: 0, hearted: [], amounts: [:])
        var prefs = none
        prefs.goalPercent = GoalPlanner.defaultGoal(currentRate: currentRate, reachablePercent: GoalPlanner.plan(input, none).reachablePercent)
        return prefs
    }

    /// The saved budgets per period, as the Goal screen shows a saved plan: a quarterly budget is a third.
    public static func perPeriod(_ budgets: [Budget]) -> [String: Decimal] {
        Dictionary(budgets.map { ($0.categoryID, $0.cadence == .monthly ? $0.amount : $0.amount / 3) }) { $1 }
    }

    /// A want budget set by hand in the Plan tab counts as hearted at that amount, a third of it each period when it is
    /// quarterly, on the planner's 50 kr grid. Any other budget leaves the preferences alone.
    public static func edited(_ budget: Budget, groups: CategoryGroups, prefs: GoalPreferences) -> GoalPreferences {
        guard groups.group(of: budget.categoryID) == .want else { return prefs }
        var next = prefs
        next.hearted.insert(budget.categoryID)
        next.amounts[budget.categoryID] = planned(budget)
        return next
    }

    /// A budget per period as the planner counts it: a quarterly one at a third rounded up to 50 kr, as `Usual` plans a
    /// quarterly need.
    static func planned(_ budget: Budget) -> Decimal {
        budget.cadence == .monthly ? budget.amount : PlanSuggestions.roundUp(budget.amount / 3, to: GoalPlanner.budgetStep)
    }
}
