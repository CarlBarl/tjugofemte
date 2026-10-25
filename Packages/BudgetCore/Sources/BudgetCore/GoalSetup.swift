import Foundation

/// Between what the phone stores and the goal planner: the planner's input from the transactions, the plan as budget
/// rows, and a budget edited by hand as a heart.
public enum GoalSetup {
    /// A need with a budget is planned at that budget, a quarterly one at a third of it; a need without one at its usual.
    /// Wants are at their usual, fixed when recurring charges make them up, and Unsorted always is. Wants are biggest
    /// first, as the Goal screen lists them.
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
        // Quarterly need budgets are already in `usual` as a third of themselves.
        for b in budgets where b.cadence == .monthly && groups.group(of: b.categoryID) == .need { needs[b.categoryID] = b.amount }
        wants.sort { ($0.usual, $1.categoryID) > ($1.usual, $0.categoryID) }
        return GoalInput(plannedIncome: plannedIncome, needs: needs, wants: wants)
    }

    /// A need keeps its budget as it was, amount and cadence; a need without one gets its usual, monthly. Each want gets
    /// its planned budget, monthly. Sorted by category, as the store returns them.
    public static func budgets(input: GoalInput, prefs: GoalPreferences, existing: [Budget]) -> [Budget] {
        let plan = GoalPlanner.plan(input, prefs)
        let needs = input.needs.map { id, amount -> Budget in
            existing.first { $0.categoryID == id } ?? Budget(categoryID: id, amount: amount, cadence: .monthly)
        }
        let wants = plan.budgets.map { Budget(categoryID: $0.key, amount: $0.value, cadence: .monthly) }
        return (needs + wants).sorted { $0.categoryID < $1.categoryID }
    }

    /// The goal before the user moves anything: `GoalPlanner.defaultGoal` against the rate reachable with no hearts.
    public static func defaultPreferences(input: GoalInput, currentRate: Decimal?) -> GoalPreferences {
        let none = GoalPreferences(goalPercent: 0, hearted: [], amounts: [:])
        var prefs = none
        prefs.goalPercent = GoalPlanner.defaultGoal(currentRate: currentRate, reachablePercent: GoalPlanner.plan(input, none).reachablePercent)
        return prefs
    }

    /// A want budget set by hand in the Plan tab counts as hearted at that amount, a third of it each period when it is
    /// quarterly. Any other budget leaves the preferences alone.
    public static func edited(_ budget: Budget, groups: CategoryGroups, prefs: GoalPreferences) -> GoalPreferences {
        guard groups.group(of: budget.categoryID) == .want else { return prefs }
        var next = prefs
        next.hearted.insert(budget.categoryID)
        next.amounts[budget.categoryID] = budget.cadence == .monthly ? budget.amount : budget.amount / 3
        return next
    }
}
