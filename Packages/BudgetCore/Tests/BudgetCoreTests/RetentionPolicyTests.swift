import Testing
import Foundation
@testable import BudgetCore

@Suite struct RetentionPolicyTests {
    @Test func cutoffIsWholeMonthsBeforeToday() {
        let cutoff = RetentionPolicy(months: 3).cutoff(today: d(2026, 10, 17))
        #expect(cutoff == d(2026, 7, 17))
    }

    @Test func keepsTransactionsOnOrAfterCutoff() {
        let policy = RetentionPolicy(months: 3)
        #expect(!policy.shouldPurge(bookingDate: d(2026, 7, 17), today: d(2026, 10, 17)))
        #expect(policy.shouldPurge(bookingDate: d(2026, 7, 16), today: d(2026, 10, 17)))
    }

    @Test func onlyOfferedOptionsAreValid() {
        #expect(RetentionPolicy.options.map(\.months) == [3, 12, 24])
    }
}
