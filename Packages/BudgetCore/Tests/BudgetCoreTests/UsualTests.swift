import Testing
import Foundation
@testable import BudgetCore

@Suite struct UsualTests {
    let rule = PeriodRule(startDay: 25)
    // Friday 17 Oct 2026: October period (25 Sep to 22 Oct) is current; September and earlier are complete.
    let today = d(2026, 10, 17)

    func start(_ month: Int) -> Date { rule.period(labeled: PeriodLabel(year: 2026, month: month)).start }
    func day(_ month: Int, _ offset: Int) -> Date { Calendar.stockholm.date(byAdding: .day, value: offset, to: start(month))! }

    func tx(_ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: "\(text)-\(date.timeIntervalSince1970)", bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    @Test func meanCountsPeriodsWithoutSpendingAsZero() {
        let txs = [
            tx(start(8), 34_200, "Lön", "income"),
            tx(day(8, 3), -600, "Foodora", "takeaway"),             // nothing in September
        ]
        let u = Usual.perCategory(transactions: txs, rule: rule, today: today)
        #expect(u == ["takeaway": UsualAmount(amount: 300, periods: 2)])
    }

    @Test func roundsUpToFiftyAndDropsBelowFifty() {
        let txs = [
            tx(start(9), -1_201, "ICA", "groceries"),
            tx(day(9, 3), -40, "Netflix", "streaming"),
        ]
        let u = Usual.perCategory(transactions: txs, rule: rule, today: today)
        #expect(u["groceries"] == UsualAmount(amount: 1_250, periods: 1))
        #expect(u["streaming"] == nil)
    }

    @Test func onlySpendingKindCategoriesHaveAUsual() {
        let txs = [
            tx(start(9), 34_200, "Lön", "income"),
            tx(day(9, 2), -2_000, "Till sparkonto", "savings"),
            tx(day(9, 3), -5_000, "Egen överföring", "transfer"),
            tx(day(9, 4), -300, "Okänd butik", "unsorted"),
        ]
        let u = Usual.perCategory(transactions: txs, rule: rule, today: today)
        #expect(u == ["unsorted": UsualAmount(amount: 300, periods: 1)])
    }

    @Test func usesAtMostTwelveCompletePeriods() {
        // Fourteen complete periods, September 2026 back to August 2025, each with a booking on its first day.
        var label = rule.period(containing: today).label
        var txs: [Transaction] = []
        for i in 1...14 {
            label = label.previous
            txs.append(tx(rule.period(labeled: label).start, i <= 12 ? -100 : -10_000, "ICA", "groceries"))
        }
        let u = Usual.perCategory(transactions: txs, rule: rule, today: today)
        #expect(u["groceries"] == UsualAmount(amount: 100, periods: 12))   // the two oldest would make it 1 550
    }

    @Test func aPartlyCoveredOldestPeriodIsLeftOut() {
        // Data starts mid-August: the August period is only half covered and would understate spending.
        let txs = [
            tx(day(8, 15), -1_000, "ICA", "groceries"),
            tx(day(9, 4), -2_000, "ICA", "groceries"),
        ]
        let u = Usual.perCategory(transactions: txs, rule: rule, today: today)
        #expect(u == ["groceries": UsualAmount(amount: 2_000, periods: 1)])
    }

    @Test func noCompletePeriodUsesThisPeriodSoFar() {
        // Data starts the day after the October period began, so no period before it is fully covered.
        let txs = [
            tx(d(2026, 9, 26), -734, "ICA", "groceries"),
            tx(d(2026, 10, 10), -500, "Willys", "groceries"),
        ]
        let u = Usual.perCategory(transactions: txs, rule: rule, today: today)
        #expect(u == ["groceries": UsualAmount(amount: 1_250, periods: 0)])
    }

    @Test func aQuarterlyCategoryIsAThirdOfItsQuarterlyAmount() {
        let u = Usual.perCategory(transactions: [], rule: rule, quarterly: ["studentLoan": 4_950], today: today)
        #expect(u["studentLoan"] == UsualAmount(amount: 1_650, periods: 0))
    }

    @Test func aQuarterlyAmountWinsOverItsTransactions() {
        // CSN drawn once in August: the transactions alone would say 2 475 a period.
        let txs = [
            tx(start(8), 34_200, "Lön", "income"),
            tx(day(8, 5), -4_950, "CSN", "studentLoan"),
        ]
        let u = Usual.perCategory(transactions: txs, rule: rule, quarterly: ["studentLoan": 4_950], today: today)
        #expect(u["studentLoan"] == UsualAmount(amount: 1_650, periods: 2))
    }
}
