import Foundation

/// A want on the Goal screen. Fixed wants (mostly recurring charges, and Unsorted, which may hold bills) are never trimmed by the planner.
public struct WantInput: Equatable, Sendable {
    public let categoryID: String
    public let usual: Decimal
    public let fixed: Bool

    public init(categoryID: String, usual: Decimal, fixed: Bool) {
        self.categoryID = categoryID
        self.usual = usual
        self.fixed = fixed
    }
}

/// What a goal is planned from, all per period. A quarterly need counts a third.
public struct GoalInput: Equatable, Sendable {
    public let plannedIncome: Decimal
    public let needs: [String: Decimal]
    public let wants: [WantInput]
    /// The needs paid once a quarter, at the quarterly amount, for "4 950 kr a quarter, a third each period".
    public let quarterly: [String: Decimal]
    /// Complete periods the usual amounts are built on. 0 means the current period so far was used.
    public let periods: Int

    public init(plannedIncome: Decimal, needs: [String: Decimal], wants: [WantInput], quarterly: [String: Decimal] = [:], periods: Int = 0) {
        self.plannedIncome = plannedIncome
        self.needs = needs
        self.wants = wants
        self.quarterly = quarterly
        self.periods = periods
    }
}

/// What the user chose on the Goal screen. Nothing here changes `goalPercent`; only the slider and "Settle" do.
public struct GoalPreferences: Equatable, Sendable, Codable {
    public var goalPercent: Int
    public var hearted: Set<String>
    /// Kronor set with minus and plus, for hearted and fixed wants. A hearted want without one sits at its usual.
    public var amounts: [String: Decimal]

    public init(goalPercent: Int, hearted: Set<String>, amounts: [String: Decimal]) {
        self.goalPercent = goalPercent
        self.hearted = hearted
        self.amounts = amounts
    }
}

/// The wants' budgets for a goal, and the gap when the goal is out of reach.
public struct GoalPlan: Equatable, Sendable {
    /// Every want's budget per period. Needs stay at their usual and are not in here.
    public let budgets: [String: Decimal]
    public let wantsTotal: Decimal
    /// Planned income minus needs and wants.
    public let plannedSavings: Decimal
    /// The highest goal with every flexible want that is not hearted at half its usual, in whole percent rounded down, never below 0.
    public let reachablePercent: Int
    /// What that highest goal saves in kronor; negative when needs, fixed and hearted wants alone are more than the income.
    public let reachableMax: Decimal
    /// The plan saves less than the goal. The goal stays where the user put it, and `shortfall` is the gap.
    public let outOfReach: Bool
    /// Usual spending already saves more than the goal, so nothing is trimmed.
    public let beyondGoal: Bool
    /// "Trimmed by 48 %": how far the flexible wants that are not hearted are cut, in whole percent.
    public let cutPercent: Int
    /// Kronor more each period the goal needs, rounded up to 10 kr. 0 when the goal is in reach.
    public let shortfall: Decimal
}

/// "Takeaway +500 kr comes from Shopping −250 kr": how much less a want gets because of a raise.
public struct RaiseSource: Equatable, Sendable {
    public let categoryID: String
    public let amount: Decimal
}

/// Budgets from a savings goal. Needs and fixed wants keep their usual, hearted wants keep what the user set, and the
/// other wants share what is left by the same factor, rounded down to 50 kr and never below half their usual.
public enum GoalPlanner {
    static let budgetStep: Decimal = 50
    static let shortfallStep: Decimal = 10
    /// A flexible want's plus stops this far above the budget on screen.
    static let maxRaise: Decimal = 5_000
    static let defaultPercent = 20
    /// The slider's end.
    static let maxPercent = 50

    public static func plan(_ input: GoalInput, _ prefs: GoalPreferences) -> GoalPlan {
        let income = input.plannedIncome
        let needs = input.needs.values.reduce(0, +)
        let goal = income * Decimal(prefs.goalPercent) / 100
        // F, P and H in the spec: fixed wants and Unsorted, hearted wants, and the usual of the rest.
        var fixed: Decimal = 0
        var protected: Decimal = 0
        var rest: Decimal = 0
        var halves: Decimal = 0
        for w in input.wants {
            if w.fixed { fixed += amount(w, prefs) }
            else if prefs.hearted.contains(w.categoryID) { protected += amount(w, prefs) }
            else { rest += w.usual; halves += half(w.usual) }
        }
        // U in the spec: what is left for the rest once the goal is put aside.
        let room = income - needs - fixed - protected - goal

        var budgets: [String: Decimal] = [:]
        for w in input.wants {
            if w.fixed || prefs.hearted.contains(w.categoryID) { budgets[w.categoryID] = amount(w, prefs) }
            else if rest == 0 || room >= rest { budgets[w.categoryID] = w.usual }
            else { budgets[w.categoryID] = max(half(w.usual), roundDown(w.usual * room / rest, to: budgetStep)) }
        }
        let wantsTotal = budgets.values.reduce(0, +)
        let plannedSavings = income - needs - wantsTotal
        let reachableMax = income - needs - fixed - protected - halves
        // Covers the spec's U < H/2, where every flexible want sits at its half, and also halves rounded up to 50 kr
        // that miss the goal by a few kronor when the room is half the usual or a little more.
        let outOfReach = plannedSavings < goal

        var cutPercent = 0
        if rest > 0, room > 0, room < rest {
            cutPercent = whole(100 - max(room * 100 / rest, 50), .plain)
        }
        return GoalPlan(budgets: budgets, wantsTotal: wantsTotal, plannedSavings: plannedSavings,
                        reachablePercent: income > 0 ? max(0, whole(reachableMax * 100 / income, .down)) : 0,
                        reachableMax: reachableMax, outOfReach: outOfReach, beyondGoal: room > rest, cutPercent: cutPercent,
                        shortfall: outOfReach ? PlanSuggestions.roundUp(goal - plannedSavings, to: shortfallStep) : 0)
    }

    /// Want budgets set elsewhere, such as a saved plan, described the way `plan` describes its own: what they save,
    /// whether that reaches the goal and the gap when not, and how far the flexible wants that are not hearted sit below
    /// their usual. A want without a budget here gets the planner's, and anything that is not a want is left out. The
    /// reachable rate depends only on the preferences, so it is the planner's.
    public static func summary(of budgets: [String: Decimal], input: GoalInput, prefs: GoalPreferences) -> GoalPlan {
        let planned = plan(input, prefs)
        let shown = planned.budgets.merging(budgets.filter { planned.budgets[$0.key] != nil }) { $1 }
        let goal = input.plannedIncome * Decimal(prefs.goalPercent) / 100
        let wantsTotal = shown.values.reduce(0, +)
        let plannedSavings = input.plannedIncome - input.needs.values.reduce(0, +) - wantsTotal
        var usual: Decimal = 0
        var kept: Decimal = 0
        for w in input.wants where !w.fixed && !prefs.hearted.contains(w.categoryID) {
            usual += w.usual
            kept += shown[w.categoryID] ?? w.usual
        }
        let cutPercent = usual > 0 && kept < usual ? whole(100 - kept * 100 / usual, .plain) : 0
        let outOfReach = plannedSavings < goal
        return GoalPlan(budgets: shown, wantsTotal: wantsTotal, plannedSavings: plannedSavings,
                        reachablePercent: planned.reachablePercent, reachableMax: planned.reachableMax,
                        outOfReach: outOfReach, beyondGoal: cutPercent == 0 && plannedSavings > goal, cutPercent: cutPercent,
                        shortfall: outOfReach ? PlanSuggestions.roundUp(goal - plannedSavings, to: shortfallStep) : 0)
    }

    /// Minus and plus move from the budget on screen: `shown` when the screen shows something other than the plan, such
    /// as a saved plan, else the planned budget. A flexible want is hearted at the result; a fixed want can go down but
    /// never above its usual, and is never hearted. A category not in the input is left alone.
    public static func step(_ categoryID: String, by delta: Decimal, from shown: Decimal? = nil, input: GoalInput, prefs: GoalPreferences) -> GoalPreferences {
        guard let want = input.wants.first(where: { $0.categoryID == categoryID }),
              let budget = shown ?? plan(input, prefs).budgets[categoryID] else { return prefs }
        let ceiling = want.fixed ? want.usual : budget + maxRaise
        var next = prefs
        next.amounts[categoryID] = max(0, min(ceiling, budget + delta))
        if !want.fixed { next.hearted.insert(categoryID) }
        return next
    }

    /// A heart on its own keeps the category at its usual; taking it off drops the amount too.
    public static func heart(_ categoryID: String, _ on: Bool, prefs: GoalPreferences) -> GoalPreferences {
        var next = prefs
        next.amounts[categoryID] = nil
        if on { next.hearted.insert(categoryID) } else { next.hearted.remove(categoryID) }
        return next
    }

    /// What each flexible want that is not hearted gives up for the hearted wants raised above their usual, biggest first.
    /// The comparison is the same preferences with only the raised wants back at their usual, so it shows the raise alone.
    /// Empty without a raise, and when the goal is out of reach.
    public static func raiseSources(input: GoalInput, prefs: GoalPreferences) -> [RaiseSource] {
        let raised = input.wants.filter { w in
            !w.fixed && prefs.hearted.contains(w.categoryID) && (prefs.amounts[w.categoryID] ?? w.usual) > w.usual
        }
        let now = plan(input, prefs)
        guard !raised.isEmpty, !now.outOfReach else { return [] }
        var unraised = prefs
        for w in raised { unraised.amounts[w.categoryID] = nil }
        let base = plan(input, unraised)
        return input.wants.compactMap { w -> RaiseSource? in
            guard !w.fixed, !prefs.hearted.contains(w.categoryID),
                  let before = base.budgets[w.categoryID], let after = now.budgets[w.categoryID], before > after else { return nil }
            return RaiseSource(categoryID: w.categoryID, amount: before - after)
        }
        .sorted { ($0.amount, $1.categoryID) > ($1.amount, $0.categoryID) }
    }

    /// 20 %, or the current savings rate rounded down when it is higher, never above the reachable rate or the slider's end.
    public static func defaultGoal(currentRate: Decimal?, reachablePercent: Int) -> Int {
        let current = currentRate.map { whole($0 * 100, .down) } ?? 0
        return min(max(defaultPercent, current), reachablePercent, maxPercent)
    }

    static func amount(_ want: WantInput, _ prefs: GoalPreferences) -> Decimal {
        prefs.amounts[want.categoryID] ?? want.usual
    }

    static func half(_ usual: Decimal) -> Decimal {
        PlanSuggestions.roundUp(usual / 2, to: budgetStep)
    }

    static func roundDown(_ amount: Decimal, to step: Decimal) -> Decimal {
        var quotient = amount / step
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .down)
        return rounded * step
    }

    static func whole(_ value: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Int {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, mode)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
