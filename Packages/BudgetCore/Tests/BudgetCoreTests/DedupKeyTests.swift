import Testing
import Foundation
@testable import BudgetCore

@Suite struct DedupKeyTests {
    @Test func prefersBankTransactionID() {
        let key = DedupKey.make(transactionID: "T1", entryReference: "E1", bookingDate: d(2026, 10, 1), amount: -10, currency: "SEK", counterparty: "ICA")
        #expect(key == "id:T1")
    }

    @Test func fallsBackToEntryReference() {
        let key = DedupKey.make(transactionID: nil, entryReference: "E1", bookingDate: d(2026, 10, 1), amount: -10, currency: "SEK", counterparty: "ICA")
        #expect(key == "ref:E1")
    }

    @Test func blankIdentifiersCountAsMissing() {
        let key = DedupKey.make(transactionID: " ", entryReference: "", bookingDate: d(2026, 10, 1), amount: -10, currency: "SEK", counterparty: "ICA")
        #expect(key.hasPrefix("fp:"))
    }

    @Test func fingerprintIgnoresCaseAndSpacingInCounterparty() {
        let a = DedupKey.make(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 1), amount: -10, currency: "SEK", counterparty: "ICA  Supermarket")
        let b = DedupKey.make(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 1), amount: -10, currency: "SEK", counterparty: "ica supermarket")
        #expect(a == b)
    }

    @Test func fingerprintChangesWithAmountOrDate() {
        let a = DedupKey.make(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 1), amount: -10, currency: "SEK", counterparty: "ICA")
        let b = DedupKey.make(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 1), amount: -10.5, currency: "SEK", counterparty: "ICA")
        let c = DedupKey.make(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 2), amount: -10, currency: "SEK", counterparty: "ICA")
        #expect(a != b)
        #expect(a != c)
    }
}
