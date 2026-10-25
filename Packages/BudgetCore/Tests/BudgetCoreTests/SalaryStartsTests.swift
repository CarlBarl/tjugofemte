import Testing
import Foundation
@testable import BudgetCore

@Suite struct SalaryStartsTests {
    // Nominal starts for payday 25 in 2026: September 25 Aug, October 25 Sep, November 23 Oct (25 Oct is a Sunday), December 25 Nov.
    let september = PeriodLabel(year: 2026, month: 9)
    let october = PeriodLabel(year: 2026, month: 10)
    let november = PeriodLabel(year: 2026, month: 11)
    let december = PeriodLabel(year: 2026, month: 12)

    let salary = IncomeSource(id: "salary", name: "Lön", plannedAmount: 30_000, keyword: "lön")
    let partner = IncomeSource(id: "partner", name: "Sambo", plannedAmount: 5_000, keyword: "swish mottagen")

    func tx(_ key: String, _ date: Date, _ amount: Decimal, _ text: String) -> Transaction {
        Transaction(dedupKey: key, bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: "income")
    }

    // The real account: the salary booked one banking day before the nominal start three months running.
    var realSalaries: [Transaction] {
        [tx("1", d(2026, 8, 24), 31_749, "LÖN"), tx("2", d(2026, 9, 24), 30_272, "LÖN"), tx("3", d(2026, 10, 22), 24_303, "LÖN")]
    }

    @Test func periodStartsOnTheDayTheSalaryBooked() {
        let detected = SalaryStarts.detect(transactions: realSalaries, incomeSources: [salary], startDay: 25)
        #expect(detected == [september: d(2026, 8, 24), october: d(2026, 9, 24), november: d(2026, 10, 22)])
        let rule = PeriodRule(startDay: 25, overrides: detected)
        #expect(rule.period(containing: d(2026, 10, 22)).start == d(2026, 10, 22))
        #expect(rule.period(containing: d(2026, 10, 21)).end == d(2026, 10, 21))
    }

    @Test func smallCreditFromTheEmployerDoesNotMoveTheStart() {
        let expense = tx("x", d(2026, 10, 20), 550, "Lön utlägg")
        #expect(SalaryStarts.detect(transactions: [expense], incomeSources: [salary], startDay: 25).isEmpty)
        let detected = SalaryStarts.detect(transactions: [expense] + realSalaries, incomeSources: [salary], startDay: 25)
        #expect(detected[november] == d(2026, 10, 22))
    }

    @Test func earliestSalaryBookingInTheWindowOpensThePeriod() {
        let txs = realSalaries + [tx("5", d(2026, 10, 26), 20_000, "LÖN")]
        for order in [txs, txs.reversed()] {  // the store returns newest first
            #expect(SalaryStarts.detect(transactions: order, incomeSources: [salary], startDay: 25)[november] == d(2026, 10, 22))
        }
    }

    @Test func periodWithoutSalaryYetKeepsItsNominalStart() {
        let detected = SalaryStarts.detect(transactions: realSalaries, incomeSources: [salary], startDay: 25)
        #expect(detected[december] == nil)
        let rule = PeriodRule(startDay: 25, overrides: detected)
        #expect(rule.period(labeled: december).start == d(2026, 11, 25))
        #expect(rule.period(labeled: november).end == d(2026, 11, 24))
    }

    @Test func lateSalaryMovesTheStartLater() {
        let late = tx("4", d(2026, 11, 27), 30_000, "LÖN")  // nominal start Wednesday 25 Nov
        let detected = SalaryStarts.detect(transactions: realSalaries + [late], incomeSources: [salary], startDay: 25)
        #expect(detected[december] == d(2026, 11, 27))
        let rule = PeriodRule(startDay: 25, overrides: detected)
        #expect(rule.period(containing: d(2026, 11, 26)).label == november)
        #expect(rule.period(containing: d(2026, 11, 27)).label == december)
    }

    @Test func manualStartWinsOverDetectedStart() {
        let detected = SalaryStarts.detect(transactions: realSalaries, incomeSources: [salary], startDay: 25)
        let merged = SalaryStarts.overrides(detected: detected, manual: [november: d(2026, 10, 20)])
        #expect(merged == [september: d(2026, 8, 24), october: d(2026, 9, 24), november: d(2026, 10, 20)])
        let rule = PeriodRule(startDay: 25, overrides: merged)
        #expect(rule.period(labeled: november).start == d(2026, 10, 20))
        #expect(rule.period(labeled: october).start == d(2026, 9, 24))
    }

    @Test func calendarMonthsAndKeywordlessSourcesDetectNothing() {
        #expect(SalaryStarts.detect(transactions: realSalaries, incomeSources: [salary], startDay: 1).isEmpty)
        let planOnly = [IncomeSource(id: "a", name: "Lön", plannedAmount: 30_000, keyword: nil),
                        IncomeSource(id: "b", name: "Lön", plannedAmount: 30_000, keyword: " ")]
        #expect(SalaryStarts.detect(transactions: realSalaries, incomeSources: planOnly, startDay: 25).isEmpty)
    }

    @Test func onlyTheLargestKeyedSourceCounts() {
        let swish = tx("s", d(2026, 10, 19), 5_000, "Swish mottagen Alex")
        let bigPlanOnly = IncomeSource(id: "big", name: "Bonus", plannedAmount: 90_000, keyword: nil)
        let detected = SalaryStarts.detect(transactions: [swish] + realSalaries, incomeSources: [partner, bigPlanOnly, salary], startDay: 25)
        #expect(detected[november] == d(2026, 10, 22))
    }

    @Test func salaryNeverOpensTheNeighbouringMonthsPeriod() {
        let detected = SalaryStarts.detect(transactions: [tx("2", d(2026, 9, 24), 30_272, "LÖN")], incomeSources: [salary], startDay: 25)
        #expect(detected == [october: d(2026, 9, 24)])
        let rule = PeriodRule(startDay: 25, overrides: detected)
        #expect(rule.period(labeled: september).start == d(2026, 8, 25))
        #expect(rule.period(labeled: november).start == d(2026, 10, 23))
    }

    @Test func windowRunsFromSevenDaysBeforeToFiveDaysAfterTheNominalStart() {
        func detected(_ day: Date) -> [PeriodLabel: Date] {
            SalaryStarts.detect(transactions: [tx("w", day, 30_000, "LÖN")], incomeSources: [salary], startDay: 25)
        }
        #expect(detected(d(2026, 10, 15)).isEmpty)
        #expect(detected(d(2026, 10, 16)) == [november: d(2026, 10, 16)])
        #expect(detected(d(2026, 10, 28)) == [november: d(2026, 10, 28)])
        #expect(detected(d(2026, 10, 29)).isEmpty)
    }
}
