import Testing
import Foundation
@testable import BudgetCore

@Suite struct GoalSetupTests {
    let rule = PeriodRule(startDay: 25)
    // Friday 17 Oct 2026: October period (25 Sep to 22 Oct) is current; July, August and September are complete.
    let today = d(2026, 10, 17)

    func start(_ month: Int) -> Date { rule.period(labeled: PeriodLabel(year: 2026, month: month)).start }
    func day(_ month: Int, _ offset: Int) -> Date { Calendar.stockholm.date(byAdding: .day, value: offset, to: start(month))! }

    func tx(_ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: "\(text)-\(date.timeIntervalSince1970)", bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    /// Three complete periods: rent and groceries are needs, takeaway a flexible want, Netflix a monthly charge, one CSN draw.
    /// Groceries and takeaway vary by more than 10 %, so neither is a recurring charge.
    var history: [Transaction] {
        zip([7, 8, 9], [(4_200, 3_000, 240), (4_800, 3_600, 260), (5_400, 4_200, 250)]).flatMap { month, amounts -> [Transaction] in
            [tx(start(month), 34_200, "Lön", "income"),
             tx(day(month, 1), -10_400, "Hyra Bostadsbolaget", "rent"),
             tx(day(month, 2), -2_000, "Avanza Bank", "savings"),
             tx(day(month, 3), -149, "Netflix", "streaming"),
             tx(day(month, 4), -Decimal(amounts.0), "ICA", "groceries"),
             tx(day(month, 5), -Decimal(amounts.1), "Foodora", "takeaway"),
             tx(day(month, 6), -Decimal(amounts.2), "SUSHI YAMA", "unsorted")]
        } + [tx(day(8, 9), -4_950, "CSN", "studentLoan")]
    }

    @Test func needsAndWantsSitAtTheirUsualAndChargesAreFixed() {
        let input = GoalSetup.input(plannedIncome: 34_200, transactions: history, rule: rule, budgets: [], groups: CategoryGroups(), today: today)
        #expect(input.plannedIncome == 34_200)
        #expect(input.needs == ["rent": 10_400, "groceries": 4_800, "studentLoan": 1_650])   // CSN once in three periods, no budget
        // Biggest first; Netflix makes Streaming fixed, Unsorted is always fixed, savings is in neither.
        #expect(input.wants == [WantInput(categoryID: "takeaway", usual: 3_600, fixed: false),
                                WantInput(categoryID: "unsorted", usual: 250, fixed: true),
                                WantInput(categoryID: "streaming", usual: 150, fixed: true)])
    }

    @Test func aQuarterlyNeedBudgetIsAThirdOfItAndMonthlyBudgetsDoNotCount() {
        let budgets = [Budget(categoryID: "studentLoan", amount: 6_000, cadence: .quarterly(firstDueMonth: 2)),
                       Budget(categoryID: "rent", amount: 12_000, cadence: .monthly),
                       Budget(categoryID: "takeaway", amount: 1_500, cadence: .monthly)]
        let input = GoalSetup.input(plannedIncome: 34_200, transactions: history, rule: rule, budgets: budgets, groups: CategoryGroups(), today: today)
        #expect(input.needs["studentLoan"] == 2_000)
        #expect(input.needs["rent"] == 10_400)
        #expect(input.wants.first == WantInput(categoryID: "takeaway", usual: 3_600, fixed: false))
    }

    @Test func aFlippedCategoryMovesBetweenNeedsAndWants() {
        let groups = CategoryGroups(overrides: ["groceries": .want, "takeaway": .need])
        let input = GoalSetup.input(plannedIncome: 34_200, transactions: history, rule: rule, budgets: [], groups: groups, today: today)
        #expect(input.needs == ["rent": 10_400, "takeaway": 3_600, "studentLoan": 1_650])
        #expect(input.wants.first == WantInput(categoryID: "groceries", usual: 4_800, fixed: false))
    }

    @Test func noHistoryGivesAnEmptyInput() {
        let input = GoalSetup.input(plannedIncome: 0, transactions: [], rule: rule, budgets: [], groups: CategoryGroups(), today: today)
        #expect(input == GoalInput(plannedIncome: 0, needs: [:], wants: []))
    }

    @Test func budgetsAreThePlanWithAQuarterlyNeedKept() {
        let input = GoalInput(plannedIncome: 34_200, needs: ["rent": 10_400, "studentLoan": 1_650],
                              wants: [WantInput(categoryID: "takeaway", usual: 3_600, fixed: false), WantInput(categoryID: "streaming", usual: 425, fixed: true)])
        let existing = [Budget(categoryID: "studentLoan", amount: 4_950, cadence: .quarterly(firstDueMonth: 2)),
                        Budget(categoryID: "rent", amount: 11_000, cadence: .monthly)]
        let prefs = GoalPreferences(goalPercent: 20, hearted: [], amounts: ["streaming": 0])
        let plan = GoalPlanner.plan(input, prefs)
        #expect(GoalSetup.budgets(input: input, prefs: prefs, existing: existing) == [
            Budget(categoryID: "rent", amount: 10_400, cadence: .monthly),
            Budget(categoryID: "streaming", amount: 0, cadence: .monthly),
            Budget(categoryID: "studentLoan", amount: 4_950, cadence: .quarterly(firstDueMonth: 2)),
            Budget(categoryID: "takeaway", amount: plan.budgets["takeaway"]!, cadence: .monthly),
        ])
    }

    @Test func aWantBudgetSetByHandIsHeartedAtThatAmount() {
        let prefs = GoalPreferences(goalPercent: 20, hearted: ["shopping"], amounts: [:])
        let takeaway = GoalSetup.edited(Budget(categoryID: "takeaway", amount: 2_000, cadence: .monthly), groups: CategoryGroups(), prefs: prefs)
        #expect(takeaway == GoalPreferences(goalPercent: 20, hearted: ["shopping", "takeaway"], amounts: ["takeaway": 2_000]))
        // A quarterly budget is a third each period, as the planner counts it.
        let quarterly = GoalSetup.edited(Budget(categoryID: "entertainment", amount: 900, cadence: .quarterly(firstDueMonth: 1)), groups: CategoryGroups(), prefs: prefs)
        #expect(quarterly.amounts["entertainment"] == 300)
        // Needs are kept at their usual, so a need's budget is no heart; a flipped category follows its group.
        #expect(GoalSetup.edited(Budget(categoryID: "groceries", amount: 4_000, cadence: .monthly), groups: CategoryGroups(), prefs: prefs) == prefs)
        let flipped = GoalSetup.edited(Budget(categoryID: "groceries", amount: 4_000, cadence: .monthly), groups: CategoryGroups(overrides: ["groceries": .want]), prefs: prefs)
        #expect(flipped.hearted.contains("groceries")); #expect(flipped.amounts["groceries"] == 4_000)
    }
}
