import Testing
import Foundation
@testable import BudgetCore

@Suite struct PlanSuggestionsTests {
    let rule = PeriodRule(startDay: 25)
    // Friday 17 Oct 2026: October period (25 Sep to 22 Oct) is current; September and August are complete.
    let today = d(2026, 10, 17)

    func start(_ month: Int) -> Date { rule.period(labeled: PeriodLabel(year: 2026, month: month)).start }
    func day(_ month: Int, _ offset: Int) -> Date { Calendar.stockholm.date(byAdding: .day, value: offset, to: start(month))! }

    func tx(_ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: "\(text)-\(date.timeIntervalSince1970)", bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    @Test func salaryRowsWithChangingTextCollapseToOneIncome() {
        let txs = [
            tx(start(8), 34_200, "LÖN 2026-08", "income"),
            tx(start(9), 34_200, "LÖN 2026-09", "income"),
            tx(start(10), 34_900, "LÖN 2026-10", "income"),
            tx(day(9, 3), 300, "Swish mottagen Kim", "income"),
        ]
        let incomes = PlanSuggestions.incomes(transactions: txs, rule: rule, today: today)
        #expect(incomes.count == 1)
        #expect(incomes[0].name == "Lön")
        #expect(incomes[0].keyword == "lön")
        #expect(incomes[0].amount == Decimal(34_200))  // median, not the latest
        #expect(incomes[0].periodsSeen == 3)
    }

    @Test func oneOffDepositsAreNotIncomeWhenThereIsHistory() {
        let txs = [
            tx(start(8), 30_000, "Lön", "income"),
            tx(start(9), 30_000, "Lön", "income"),
            tx(day(9, 5), 5_000, "Skatteverket", "income"),
        ]
        let incomes = PlanSuggestions.incomes(transactions: txs, rule: rule, today: today)
        #expect(incomes.map(\.name) == ["Lön"])
    }

    @Test func incomeSeenOnceIsKeptWhenOnlyOnePeriodOfData() {
        let txs = [tx(start(10), 30_000, "Lön", "income"), tx(day(10, 2), -500, "ICA", "groceries")]
        let incomes = PlanSuggestions.incomes(transactions: txs, rule: rule, today: today)
        #expect(incomes.map(\.amount) == [Decimal(30_000)])
    }

    @Test func budgetsAverageCompletePeriodsAndRoundUpToFifty() {
        let txs = [
            tx(start(8), 34_200, "Lön", "income"),
            tx(day(8, 2), -11_500, "Hyra", "rent"), tx(day(9, 2), -11_500, "Hyra", "rent"),
            tx(day(8, 4), -2_110, "ICA", "groceries"), tx(day(9, 4), -2_290, "ICA", "groceries"),
            tx(day(8, 6), -40, "Apoteket", "health"),             // 20 kr average: too small to budget
            tx(day(10, 3), -800, "Foodora", "takeaway"),           // current period only
        ]
        let result = PlanSuggestions.budgets(transactions: txs, rule: rule, today: today)
        #expect(result.completePeriods == 2)
        #expect(result.lines.map(\.categoryID) == ["rent", "groceries"])
        #expect(result.lines.map(\.amount) == [Decimal(11_500), Decimal(2_200)])
    }

    @Test func partiallyCoveredOldestPeriodIsIgnored() {
        // Data starts mid-August: the August period is only half covered and would understate spending.
        let txs = [
            tx(day(8, 15), -1_000, "ICA", "groceries"),
            tx(day(9, 4), -2_000, "ICA", "groceries"),
        ]
        let result = PlanSuggestions.budgets(transactions: txs, rule: rule, today: today)
        #expect(result.completePeriods == 1)
        #expect(result.lines.map(\.amount) == [Decimal(2_000)])
    }

    @Test func currentPeriodIsUsedWhenNoPeriodIsComplete() {
        let txs = [tx(day(10, 2), -1_234, "ICA", "groceries")]
        let result = PlanSuggestions.budgets(transactions: txs, rule: rule, today: today)
        #expect(result.completePeriods == 0)
        #expect(result.lines.map(\.amount) == [Decimal(1_250)])
    }

    @Test func paydayIsTheLatestDepositDayOfTheMainIncome() {
        // 25 Sep 2026 is a Friday; 25 Oct is a Sunday so that salary lands on Friday 23 Oct.
        let txs = [
            tx(d(2026, 8, 25), 30_000, "Lön", "income"),
            tx(d(2026, 9, 25), 30_000, "Lön", "income"),
            tx(d(2026, 10, 23), 30_000, "Lön", "income"),
            tx(d(2026, 9, 30), 2_000, "Swish mottagen Kim", "income"),
        ]
        #expect(PlanSuggestions.payday(transactions: txs, rule: rule, today: d(2026, 10, 24)) == 25)
    }

    @Test func monthEndPaydayBecomesCalendarMonths() {
        let txs = [tx(d(2026, 8, 31), 30_000, "Lön", "income"), tx(d(2026, 9, 30), 30_000, "Lön", "income")]
        #expect(PlanSuggestions.payday(transactions: txs, rule: rule, today: today) == 1)
        #expect(PlanSuggestions.payday(transactions: [], rule: rule, today: today) == nil)
    }

    @Test func roundUpToStep() {
        #expect(PlanSuggestions.roundUp(2_310, to: 50) == Decimal(2_350))
        #expect(PlanSuggestions.roundUp(2_300, to: 50) == Decimal(2_300))
        #expect(PlanSuggestions.roundUp(0, to: 50) == Decimal(0))
    }
}
