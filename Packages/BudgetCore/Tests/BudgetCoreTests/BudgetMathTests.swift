import Testing
import Foundation
@testable import BudgetCore

@Suite struct BudgetMathTests {
    let rule = PeriodRule(startDay: 25)
    // October 2026 period: 25 Sep to 22 Oct. November: 23 Oct to 24 Nov.
    var october: PayPeriod { rule.period(labeled: PeriodLabel(year: 2026, month: 10)) }
    var november: PayPeriod { rule.period(labeled: PeriodLabel(year: 2026, month: 11)) }

    let salary = IncomeSource(id: "salary", name: "Lön", plannedAmount: 35_000, keyword: "lön")
    let partner = IncomeSource(id: "partner", name: "Sambo", plannedAmount: 5_000, keyword: nil)
    let budgets = [
        Budget(categoryID: "rent", amount: 10_000, cadence: .monthly),
        Budget(categoryID: "groceries", amount: 4_000, cadence: .monthly),
        Budget(categoryID: "studentLoan", amount: 3_000, cadence: .quarterly(firstDueMonth: 2)),  // Feb, May, Aug, Nov
    ]

    func tx(_ key: String, _ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: key, bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    @Test func savingsTargetIsPlannedIncomeMinusBudgetsAndQuarterlySetAside() {
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: [], budgets: budgets, incomeSources: [salary, partner])
        #expect(s.savingsTarget.value == Decimal(25_000))  // 40 000 planned, 14 000 budgets, 1 000 set aside
        #expect(s.savingsTarget.terms.map(\.kind) == [.plannedIncome, .categoryBudgets, .quarterlySetAside])
    }

    @Test func categoryLineNetsRefundsAndIgnoresOtherPeriods() {
        let txs = [
            tx("1", d(2026, 10, 1), -1_200, "ICA", "groceries"),
            tx("2", d(2026, 10, 5), -800, "COOP", "groceries"),
            tx("3", d(2026, 10, 6), 200, "ICA", "groceries"),        // refund
            tx("4", d(2026, 10, 23), -500, "ICA", "groceries"),      // November period
        ]
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: txs, budgets: budgets, incomeSources: [])
        let groceries = s.categories.first { $0.categoryID == "groceries" }!
        #expect(groceries.budget == 4_000)
        #expect(groceries.actual == 1_800)
        #expect(groceries.remaining == 2_200)
    }

    @Test func spendingWithoutBudgetStillShowsAsACategoryLine() {
        let txs = [tx("1", d(2026, 10, 1), -300, "SATS", "gym")]
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: txs, budgets: [], incomeSources: [])
        let gym = s.categories.first { $0.categoryID == "gym" }!
        #expect(gym.budget == nil)
        #expect(gym.actual == 300)
    }

    @Test func incomeIsMatchedToSourcesByKeyword() {
        let txs = [
            tx("1", d(2026, 9, 25), 31_500, "Lön september", "income"),
            tx("2", d(2026, 10, 2), 500, "Swish mottagen Anna", "income"),
        ]
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: txs, budgets: budgets, incomeSources: [salary, partner])
        #expect(s.incomes.first { $0.sourceID == "salary" }?.actual == 31_500)
        #expect(s.incomes.first { $0.sourceID == "partner" }?.actual == nil)   // plan-only source
        #expect(s.otherIncome == 500)
    }

    @Test func salaryBelowPlanAdjustsTargetButNotTheOriginal() {
        let txs = [tx("1", d(2026, 9, 25), 31_500, "Lön september", "income")]
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: txs, budgets: budgets, incomeSources: [salary, partner])
        #expect(s.savingsTarget.value == 25_000)
        #expect(s.adjustedSavingsTarget?.value == 21_500)
        #expect(s.adjustedSavingsTarget?.terms.map(\.kind) == [.savingsTarget, .incomeShortfall])
    }

    @Test func salaryNotYetReceivedIsNotAShortfall() {
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: [], budgets: budgets, incomeSources: [salary])
        #expect(s.adjustedSavingsTarget == nil)
        #expect(s.incomes.first { $0.sourceID == "salary" }?.actual == 0)
    }

    @Test func leftOverSoFarIsIncomeMinusSpendingMinusTarget() {
        let txs = [
            tx("1", d(2026, 9, 25), 35_000, "Lön", "income"),
            tx("2", d(2026, 9, 28), -10_000, "Hyra", "rent"),
            tx("3", d(2026, 10, 1), -1_000, "ICA", "groceries"),
            tx("4", d(2026, 10, 1), -2_000, "Avanza", "transfer"),   // own account, excluded
            tx("5", d(2026, 10, 1), 2_000, "Överföring", "transfer"),
        ]
        let s = BudgetMath.summarize(period: october, rule: rule, transactions: txs, budgets: budgets, incomeSources: [salary, partner])
        #expect(s.leftOverSoFar.value == Decimal(-1_000))  // 35 000 in, 11 000 out, 25 000 target
        #expect(s.leftOverSoFar.terms.map(\.kind) == [.actualIncome, .actualSpending, .savingsTarget])
    }

    @Test func quarterlyLineAccruesAcrossThreePeriodsAndIsNotACategoryLine() {
        let txs = [tx("1", d(2026, 11, 2), -3_000, "CSN", "studentLoan")]
        let oct = BudgetMath.summarize(period: october, rule: rule, transactions: txs, budgets: budgets, incomeSources: [])
        let octLine = oct.quarterly.first { $0.categoryID == "studentLoan" }!
        #expect(octLine.setAsidePerPeriod == 1_000)
        #expect(octLine.setAsideSoFar == 2_000)       // Sep and Oct of the Sep-Oct-Nov quarter
        #expect(octLine.paidSoFar == 0)
        #expect(octLine.quarterlyAmount == 3_000)
        #expect(!oct.categories.contains { $0.categoryID == "studentLoan" })

        let nov = BudgetMath.summarize(period: november, rule: rule, transactions: txs, budgets: budgets, incomeSources: [])
        let novLine = nov.quarterly.first { $0.categoryID == "studentLoan" }!
        #expect(novLine.setAsideSoFar == 3_000)
        #expect(novLine.paidSoFar == 3_000)
    }
}
