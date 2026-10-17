import Testing
import Foundation
@testable import BudgetCore

@Suite struct PayPeriodTests {
    let rule = PeriodRule(startDay: 25)

    @Test func periodIsLabeledByTheMonthItMostlyCovers() {
        let p = rule.period(containing: d(2026, 11, 10))
        #expect(p.label == PeriodLabel(year: 2026, month: 11))
    }

    @Test func startMovesToPreviousBankingDay() {
        // 25 Oct 2026 is a Sunday, so the November period starts Friday 23 Oct.
        let p = rule.period(labeled: PeriodLabel(year: 2026, month: 11))
        #expect(p.start == d(2026, 10, 23))
        #expect(p.end == d(2026, 11, 24))
    }

    @Test func dayBeforeAdjustedStartBelongsToPreviousPeriod() {
        #expect(rule.period(containing: d(2026, 10, 22)).label == PeriodLabel(year: 2026, month: 10))
        #expect(rule.period(containing: d(2026, 10, 23)).label == PeriodLabel(year: 2026, month: 11))
    }

    @Test func decemberSalaryOn23rdOpensJanuaryPeriod() {
        let p = rule.period(containing: d(2026, 12, 23))
        #expect(p.label == PeriodLabel(year: 2027, month: 1))
        #expect(p.start == d(2026, 12, 23))
        #expect(p.end == d(2027, 1, 24))  // 25 Jan 2027 is a Monday
    }

    @Test func startDayOneMeansPlainCalendarMonths() {
        let p = PeriodRule(startDay: 1).period(containing: d(2026, 11, 15))
        #expect(p.start == d(2026, 11, 1))  // a Sunday, deliberately not adjusted
        #expect(p.end == d(2026, 11, 30))
        #expect(p.label == PeriodLabel(year: 2026, month: 11))
    }

    @Test func manualOverrideMovesOnePeriodStart() {
        let custom = PeriodRule(startDay: 25, overrides: [PeriodLabel(year: 2026, month: 12): d(2026, 11, 20)])
        #expect(custom.period(containing: d(2026, 11, 21)).label == PeriodLabel(year: 2026, month: 12))
        #expect(custom.period(labeled: PeriodLabel(year: 2026, month: 11)).end == d(2026, 11, 19))
        #expect(custom.period(labeled: PeriodLabel(year: 2027, month: 1)).start == d(2026, 12, 23))
    }

    @Test func labelsStepAcrossYears() {
        #expect(PeriodLabel(year: 2026, month: 12).next == PeriodLabel(year: 2027, month: 1))
        #expect(PeriodLabel(year: 2027, month: 1).previous == PeriodLabel(year: 2026, month: 12))
    }
}
