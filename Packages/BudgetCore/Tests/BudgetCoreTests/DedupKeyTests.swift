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

    let coffee = DedupKey.Item(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 17), amount: -51.95, currency: "SEK", counterparty: "ESPRESSO HOUSE")
    let paper = DedupKey.Item(transactionID: nil, entryReference: nil, bookingDate: d(2026, 10, 17), amount: -51.95, currency: "SEK", counterparty: "PRESSBYRAN")

    func make(_ i: DedupKey.Item) -> String {
        DedupKey.make(transactionID: i.transactionID, entryReference: i.entryReference, bookingDate: i.bookingDate, amount: i.amount, currency: i.currency, counterparty: i.counterparty)
    }

    @Test func identicalPaymentsWithoutAReferenceGetDifferentKeys() {
        let keys = DedupKey.makeAll([coffee, coffee])
        #expect(keys[0] != keys[1])
        #expect(keys[0] == make(coffee))                              // rows already stored keep their keys
        #expect(keys[0] == "fp:d6b1bcca64d86ff63616b92e13e6ed14")     // the key make gave before repeats were numbered
        #expect(keys[1].hasPrefix("fp:"))
    }

    @Test func threeIdenticalPaymentsGetThreeKeys() {
        #expect(Set(DedupKey.makeAll([coffee, coffee, coffee])).count == 3)
    }

    @Test func identicalPaymentsWithABankIdentifierKeepIt() {
        let ref = DedupKey.Item(transactionID: nil, entryReference: "E1", bookingDate: coffee.bookingDate, amount: coffee.amount, currency: "SEK", counterparty: coffee.counterparty)
        let id = DedupKey.Item(transactionID: "T1", entryReference: nil, bookingDate: coffee.bookingDate, amount: coffee.amount, currency: "SEK", counterparty: coffee.counterparty)
        #expect(DedupKey.makeAll([ref, ref, id, id, coffee]) == ["ref:E1", "ref:E1", "id:T1", "id:T1", make(coffee)])
    }

    @Test func differentTextsOnTheSameDayAndAmountAreUnaffected() {
        #expect(DedupKey.makeAll([coffee, paper]) == [make(coffee), make(paper)])
    }
}
