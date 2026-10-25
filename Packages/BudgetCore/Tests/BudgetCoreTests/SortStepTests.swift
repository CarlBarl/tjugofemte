import Testing
import Foundation
@testable import BudgetCore

@Suite struct SortStepTests {
    func day(_ offset: Int, from start: Date = d(2026, 8, 1)) -> Date { Calendar.stockholm.date(byAdding: .day, value: offset, to: start)! }

    func tx(_ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: "\(text)-\(date.timeIntervalSince1970)", bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    @Test func spellingsOfOneMerchantBecomeOneCandidate() {
        let txs = [tx(day(9), -89, "PRESSBYRAN 5521", "unsorted"), tx(day(0), -64, "PRESSBYRAN 1234", "unsorted")]
        // One row of each spelling: the most recent wins the tie.
        #expect(SortStep.candidates(transactions: txs) == [SortCandidate(keyword: "pressbyran", name: "PRESSBYRAN 5521", total: 153, count: 2)])
    }

    @Test func theNameIsTheMostCommonSpelling() {
        let txs = [tx(day(0), -89, "PRESSBYRAN 5521", "unsorted"), tx(day(5), -40, "PRESSBYRAN 5521", "unsorted"),
                   tx(day(9), -64, "PRESSBYRAN 1234", "unsorted")]
        #expect(SortStep.candidates(transactions: txs).map(\.name) == ["PRESSBYRAN 5521"])
    }

    @Test func candidatesAreTheBiggestUnsortedByTotal() {
        let merchants = Array("ABCDEFGHIJ").enumerated().map { tx(day($0), Decimal(-100 * ($0 + 1)), "BUTIK \($1)", "unsorted") }
        // A filed row of BUTIK A would lift it to the top if sorted rows counted.
        let sorted = [tx(day(2), -50_000, "ICA NARA", "groceries"), tx(day(3), -9_000, "BUTIK A", "shopping")]
        let candidates = SortStep.candidates(transactions: merchants + sorted)
        #expect(candidates.map(\.keyword) == ["butik j", "butik i", "butik h", "butik g", "butik f", "butik e", "butik d", "butik c"])
        #expect(candidates.map(\.total) == [1_000, 900, 800, 700, 600, 500, 400, 300])
    }

    @Test func moneyInAndAnEmptyCounterpartyAreNotCandidates() {
        let txs = [tx(day(0), -300, "", "unsorted"), tx(day(1), -200, "SPRAKKURS AB", "unsorted"), tx(day(2), 500, "SPRAKKURS AB", "unsorted")]
        #expect(SortStep.candidates(transactions: txs) == [SortCandidate(keyword: "sprakkurs ab", name: "SPRAKKURS AB", total: 200, count: 1)])
    }

    @Test func sortedShareIsSpendingOutsideUnsorted() {
        let txs = [
            tx(day(0), 34_200, "Lön", "income"),
            tx(day(1), -900, "ICA NARA", "groceries"),
            tx(day(2), -100, "PRESSBYRAN 5521", "unsorted"),
            tx(day(3), -2_000, "Till sparkonto", "savings"),
            tx(day(4), -500, "Egen överföring", "transfer"),
        ]
        #expect(SortStep.sortedShare(transactions: txs) == Decimal(9) / 10)
    }

    @Test func noSpendingIsFullySorted() {
        #expect(SortStep.sortedShare(transactions: []) == 1)
    }
}
