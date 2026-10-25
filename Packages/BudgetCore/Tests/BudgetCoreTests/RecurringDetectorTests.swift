import Testing
import Foundation
@testable import BudgetCore

@Suite struct RecurringDetectorTests {
    func day(_ offset: Int, from start: Date = d(2026, 5, 4)) -> Date { Calendar.stockholm.date(byAdding: .day, value: offset, to: start)! }

    func tx(_ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: "\(text)-\(date.timeIntervalSince1970)", bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    func monthly(_ amount: Decimal, _ text: String, _ category: String) -> [Transaction] {
        [0, 30, 60].map { tx(day($0), amount, text, category) }
    }

    @Test func threeMonthlyChargesOfAboutTheSameAmountAreRecurring() {
        let txs = monthly(-149, "Netflix", "streaming")
        let charges = RecurringDetector.detect(transactions: txs)
        #expect(charges == [RecurringCharge(keyword: "netflix", name: "Netflix", categoryID: "streaming", amount: 149, cadence: .monthly, lastSeen: day(60))])
        #expect(charges.first?.perPeriod == 149)
    }

    @Test func amountsThatDriftMoreThanTenPercentAreNot() {
        let txs = [tx(day(0), -149, "Netflix", "streaming"), tx(day(30), -199, "Netflix", "streaming"), tx(day(60), -149, "Netflix", "streaming")]
        #expect(RecurringDetector.detect(transactions: txs).isEmpty)
    }

    @Test func twoChargesAboutAQuarterApartAreQuarterly() {
        // 1 March to 31 May crosses the switch to summer time.
        let txs = [tx(d(2026, 3, 1), -4_950, "FOLKSAM KVARTAL", "insurance"), tx(day(91, from: d(2026, 3, 1)), -4_950, "FOLKSAM KVARTAL", "insurance")]
        let charges = RecurringDetector.detect(transactions: txs)
        #expect(charges.map(\.cadence) == [.quarterly])
        #expect(charges.first?.amount == 4_950)
        #expect(charges.first?.perPeriod == 1_650)
    }

    @Test func rentAndStudentLoanAreLeftOut() {
        let txs = monthly(-10_400, "HYRA", "rent") + monthly(-1_650, "CENTRALA STUDIESTODSNAMNDEN", "studentLoan")
        #expect(RecurringDetector.detect(transactions: txs).isEmpty)
    }

    @Test func aWantMostlyMadeOfChargesIsFixed() {
        let oneOffs = [(3, -150), (11, -230), (12, -180), (40, -210), (52, -165)].map { tx(day($0.0), Decimal($0.1), "Foodora", "takeaway") }
        let txs = monthly(-149, "Netflix", "streaming")
            + monthly(-49, "WOLT PLUS", "takeaway") + oneOffs
            + monthly(-299, "SPRAKKURS AB", "unsorted")
            + monthly(-389, "HEDVIG", "insurance")
        let charges = RecurringDetector.detect(transactions: txs)
        #expect(Set(charges.map(\.keyword)) == ["netflix", "wolt plus", "sprakkurs ab", "hedvig"])
        let fixed = RecurringDetector.fixedCategories(transactions: txs, charges: charges, groups: CategoryGroups())
        #expect(fixed == ["streaming"])   // takeaway is 147 of 1 082, unsorted is never fixed, insurance is a need
    }
}
