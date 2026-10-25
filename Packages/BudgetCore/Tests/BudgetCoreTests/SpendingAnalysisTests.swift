import Testing
import Foundation
@testable import BudgetCore

@Suite struct SpendingAnalysisTests {
    let rule = PeriodRule(startDay: 25)
    // Friday 17 Oct 2026: October period (25 Sep to 22 Oct) is current; September and earlier are complete.
    let today = d(2026, 10, 17)
    let salary = IncomeSource(id: "salary", name: "Lön", plannedAmount: 34_200, keyword: "lön")

    func start(_ month: Int) -> Date { rule.period(labeled: PeriodLabel(year: 2026, month: month)).start }
    func day(_ month: Int, _ offset: Int) -> Date { Calendar.stockholm.date(byAdding: .day, value: offset, to: start(month))! }

    func tx(_ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: "\(text)-\(date.timeIntervalSince1970)", bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    /// The mockup's month from the period's first day: salary 34 200, needs 19 300, wants 12 164 and 2 000 to savings.
    func mockupMonth(_ month: Int, takeaway: Decimal = 3_600) -> [Transaction] {
        let rows: [(Decimal, String, String)] = [
            (34_200, "Lön", "income"),
            (-10_400, "Hyra", "rent"), (-4_800, "ICA", "groceries"), (-1_650, "CSN", "studentLoan"),
            (-1_400, "SL", "transport"), (-600, "Folksam", "insurance"), (-450, "Apoteket", "health"),
            (-takeaway, "Foodora", "takeaway"), (-3_100, "Zalando", "shopping"), (-1_900, "Filmstaden", "entertainment"),
            (-1_850, "Okänd butik", "unsorted"), (-790, "Adobe", "subscriptions"), (-499, "SATS", "gym"), (-425, "Netflix", "streaming"),
            (-2_000, "Till sparkonto", "savings"),
        ]
        return rows.enumerated().map { i, row in tx(day(month, i), row.0, row.1, row.2) }
    }

    // July, August and September 2026: the salary on 25 Jun is the earliest transaction.
    var txs: [Transaction] { [7, 8, 9].flatMap { mockupMonth($0) } }

    @Test func ratesTheMockupMonthAtEightPercent() {
        let a = SpendingAnalysis.analyze(transactions: txs, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
        #expect(a.periods == 3)
        #expect(a.incomePerPeriod == 34_200)
        #expect(a.needsPerPeriod == 19_300)
        #expect(a.wantsPerPeriod == 12_164)
        #expect(a.savedPerPeriod == 2_736)
        #expect(a.savingsRate == Decimal(2_736) / Decimal(34_200))   // the 2 000 transfer is not spending
        #expect(a.topWants.map(\.categoryID) == ["takeaway", "shopping", "entertainment"])
        #expect(a.topWants[0].changePercent == nil)   // fewer than six periods: no trend
    }

    @Test func unsortedIsAWantButNeverABiggestWant() {
        // 3 000 more unsorted each period makes it 4 850, ahead of takeaway at 3 600.
        let extra = [7, 8, 9].map { tx(day($0, 20), -3_000, "PRESSBYRAN 5521", "unsorted") }
        let a = SpendingAnalysis.analyze(transactions: txs + extra, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
        #expect(a.wantsPerPeriod == 15_164)   // still in the split
        #expect(a.topWants.map(\.categoryID) == ["takeaway", "shopping", "entertainment"])
    }

    @Test func swishThatMatchesNoIncomeSourceIsOtherIncome() {
        let swish = [7, 8, 9].map { tx(day($0, 20), 1_500, "Swish mottagen Kim", "income") }
        let a = SpendingAnalysis.analyze(transactions: txs + swish, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
        #expect(a.otherIncomePerPeriod == 1_500)
        #expect(a.incomePerPeriod == 35_700)   // other income still counts in the rate
    }

    @Test func flippingGroceriesMovesItToWants() {
        let a = SpendingAnalysis.analyze(transactions: txs, rule: rule, groups: CategoryGroups(overrides: ["groceries": .want]),
                                         incomeSources: [salary], today: today)
        #expect(a.needsPerPeriod == 14_500)
        #expect(a.wantsPerPeriod == 16_964)
        #expect(a.topWants.map(\.categoryID) == ["groceries", "takeaway", "shopping"])
    }

    @Test func sixPeriodsShowATrend() {
        // April to June at 3 000 on takeaway, July to September at 3 600.
        let txs = [4, 5, 6].flatMap { mockupMonth($0, takeaway: 3_000) } + [7, 8, 9].flatMap { mockupMonth($0) }
        let a = SpendingAnalysis.analyze(transactions: txs, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
        #expect(a.periods == 6)
        #expect(a.topWants[0] == WantTrend(categoryID: "takeaway", perPeriod: 3_300, changePercent: 20))
        #expect(a.topWants[1].changePercent == 0)   // shopping is flat
    }

    @Test func noCompletePeriodUsesThisPeriodSoFar() {
        // Data starts on the October period's first day, so no period before it is fully covered.
        let a = SpendingAnalysis.analyze(transactions: mockupMonth(10), rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
        #expect(a.periods == 0)
        #expect(a.incomePerPeriod == 34_200)
        #expect(a.needsPerPeriod == 19_300)
        #expect(a.wantsPerPeriod == 12_164)
        #expect(a.savingsRate == Decimal(2_736) / Decimal(34_200))
        #expect(a.topWants[0].changePercent == nil)
    }

    @Test func transfersAndThisPeriodAreLeftOut() {
        let extra = [
            tx(day(8, 16), 5_000, "Från sparkonto", "transfer"),
            tx(day(8, 17), -5_000, "Egen överföring", "transfer"),
            tx(day(10, 2), -999, "Foodora", "takeaway"),             // the current period, not complete
        ]
        let a = SpendingAnalysis.analyze(transactions: txs + extra, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today)
        #expect(a.incomePerPeriod == 34_200)
        #expect(a.otherIncomePerPeriod == 0)
        #expect(a.needsPerPeriod == 19_300)
        #expect(a.wantsPerPeriod == 12_164)
        #expect(a.topWants[0].perPeriod == 3_600)
    }

    @Test func onePeriodRatesTheLastCompletePeriodAlone() {
        // September spent 1 400 more on takeaway than July and August, so it saved 1 336 of 34 200.
        let txs = [7, 8].flatMap { mockupMonth($0) } + mockupMonth(9, takeaway: 5_000)
        let last = SpendingAnalysis.analyze(transactions: txs, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today, maxPeriods: 1)
        #expect(last.periods == 1)
        #expect(last.savingsRate == Decimal(1_336) / Decimal(34_200))
        #expect(SpendingAnalysis.analyze(transactions: txs, rule: rule, groups: CategoryGroups(), incomeSources: [salary], today: today).periods == 3)
        // Data from September's second day: no complete period, so the current period so far stands in and says so.
        let partial = SpendingAnalysis.analyze(transactions: Array(mockupMonth(9).dropFirst()), rule: rule, groups: CategoryGroups(),
                                               incomeSources: [salary], today: today, maxPeriods: 1)
        #expect(partial.periods == 0)
    }

    @Test func noIncomeHasNoRate() {
        #expect(SpendingAnalysis.analyze(transactions: [], rule: rule, groups: CategoryGroups(), incomeSources: [], today: today).savingsRate == nil)
    }

    /// A complete period that took in 34 200, spent `spent` and had a savings target of 2 000.
    func lastComplete(spent: Decimal) -> PeriodSummary {
        PeriodSummary(period: rule.period(labeled: PeriodLabel(year: 2026, month: 9)), savingsTarget: Explained([(.plannedIncome, 34_200), (.categoryBudgets, -32_200)]),
                      adjustedSavingsTarget: nil, categories: [], quarterly: [], incomes: [], otherIncome: 0,
                      leftOverSoFar: Explained([(.actualIncome, 34_200), (.actualSpending, -spent), (.savingsTarget, -2_000)]))
    }

    @Test func theNudgeNamesTheBudgetThatWentFurthestOver() {
        func line(_ id: String, _ budget: Decimal?, _ actual: Decimal) -> CategoryLine { CategoryLine(categoryID: id, budget: budget, actual: actual) }
        let s = lastComplete(spent: 0)
        let over = PeriodSummary(period: s.period, savingsTarget: s.savingsTarget, adjustedSavingsTarget: nil,
                                 categories: [line("groceries", 4_800, 4_000), line("shopping", 1_600, 1_700), line("takeaway", 1_850, 3_060),
                                              line("unsorted", nil, 9_000)],
                                 quarterly: [], incomes: [], otherIncome: 0, leftOverSoFar: s.leftOverSoFar)
        #expect(GoalNudge.biggestOverrun(lastComplete: over) == line("takeaway", 1_850, 3_060))   // 1 210 over; a line with no budget is never over
        #expect(GoalNudge.biggestOverrun(lastComplete: s) == nil)
    }

    @Test func nudgeFiresBelowMinusFivePercentOfPlannedIncome() {
        #expect(lastComplete(spent: 33_911).leftOverSoFar.value == -1_711)
        #expect(GoalNudge.shouldShow(lastComplete: lastComplete(spent: 33_911), plannedIncome: 34_200, budgets: [], transactions: []))
        #expect(!GoalNudge.shouldShow(lastComplete: lastComplete(spent: 33_910), plannedIncome: 34_200, budgets: [], transactions: []))   // -1 710 is exactly 5 %
    }

    @Test func noPlannedIncomeNeverNudges() {
        // 5 % of nothing is nothing, so 1 kr in the red, or 7 800, would nudge without a plan to adjust.
        #expect(!GoalNudge.shouldShow(lastComplete: lastComplete(spent: 32_201), plannedIncome: 0, budgets: [], transactions: []))
        #expect(!GoalNudge.shouldShow(lastComplete: lastComplete(spent: 40_000), plannedIncome: 0, budgets: [], transactions: []))
    }

    // Rent and groceries on budget, and the student loan due every third month from February, so November pays the quarter.
    let nudgeBudgets = [Budget(categoryID: "rent", amount: 10_400, cadence: .monthly), Budget(categoryID: "groceries", amount: 4_800, cadence: .monthly),
                        Budget(categoryID: "studentLoan", amount: 4_950, cadence: .quarterly(firstDueMonth: 2))]

    func onPlan(_ month: Int) -> [Transaction] {
        [tx(start(month), 34_200, "Lön", "income"), tx(day(month, 2), -10_400, "Hyra", "rent"), tx(day(month, 4), -4_800, "ICA", "groceries")]
    }

    func nudge(_ month: Int, _ txs: [Transaction], budgets: [Budget]) -> (leftOver: Decimal, shows: Bool) {
        let summary = BudgetMath.summarize(period: rule.period(labeled: PeriodLabel(year: 2026, month: month)), rule: rule, transactions: txs,
                                           budgets: budgets, incomeSources: [salary])
        return (summary.leftOverSoFar.value, GoalNudge.shouldShow(lastComplete: summary, plannedIncome: 34_200, budgets: budgets, transactions: txs))
    }

    @Test func aQuarterlyPaymentThePlanSetAsideDoesNotNudge() {
        let csn = onPlan(11) + [tx(day(11, 9), -4_950, "CSN", "studentLoan")]
        let n = nudge(11, csn, budgets: nudgeBudgets)
        #expect(n.leftOver == -3_300)   // left over itself still counts the whole quarter
        #expect(!n.shows)
        // 2 000 of takeaway on top is past the 1 710 line once the quarter is added back.
        let over = nudge(11, csn + [tx(day(11, 12), -2_000, "Foodora", "takeaway")], budgets: nudgeBudgets)
        #expect(over.leftOver == -5_300)
        #expect(over.shows)
    }

    @Test func overspendingOutsideAQuarterlyCategoryNudgesAsBefore() {
        // October pays no quarter, so nothing is added back, and 3 500 over is -1 850 against -1 710.
        let october = nudge(10, onPlan(10) + [tx(day(10, 12), -3_500, "Foodora", "takeaway")], budgets: nudgeBudgets)
        #expect(october.leftOver == -1_850); #expect(october.shows)
        #expect(!nudge(10, onPlan(10) + [tx(day(10, 12), -3_000, "Foodora", "takeaway")], budgets: nudgeBudgets).shows)   // -1 350
        // Without a quarterly budget at all.
        let monthly = Array(nudgeBudgets.prefix(2))
        #expect(nudge(10, onPlan(10) + [tx(day(10, 12), -2_000, "Foodora", "takeaway")], budgets: monthly).shows)       // -2 000
        #expect(!nudge(10, onPlan(10) + [tx(day(10, 12), -1_000, "Foodora", "takeaway")], budgets: monthly).shows)      // -1 000
    }
}
