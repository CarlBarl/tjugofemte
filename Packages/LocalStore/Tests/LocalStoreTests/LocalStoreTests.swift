import Testing
import Foundation
import BudgetCore
@testable import LocalStore

@Suite struct LocalStoreTests {
    let store = try! LocalStore.inMemory()
    let cal = Calendar.stockholm

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    func tx(_ key: String, _ date: Date, _ amount: Decimal, _ text: String, _ category: String) -> Transaction {
        Transaction(dedupKey: key, bookingDate: date, amount: amount, currency: "SEK", counterparty: text, categoryID: category)
    }

    @Test func insertNewSkipsKnownKeysAndReportsHowManyWereNew() throws {
        let first = try store.insertNew([tx("a", day(2026, 10, 1), -10, "ICA", "groceries")])
        let second = try store.insertNew([tx("a", day(2026, 10, 1), -10, "ICA", "groceries"), tx("b", day(2026, 10, 2), -20, "COOP", "groceries")])
        #expect(first == 1)
        #expect(second == 1)
        #expect(try store.allTransactions().map(\.dedupKey) == ["b", "a"])  // newest first
    }

    @Test func aFetchReplacesTheUntouchedRowsTheBankSentBack() throws {
        _ = try store.insertNew([tx("old", day(2026, 7, 22), -30, "BEFORE WINDOW", "transfer"),
                                 tx("a", day(2026, 10, 1), -245, "SPAR AURLAND", "transfer"),
                                 tx("b", day(2026, 10, 2), -89, "OLD", "shopping"),
                                 tx("d", day(2026, 10, 4), -12, "NOT SENT BACK", "shopping")])
        try store.setCategory("b", to: "takeaway")
        // The fixed decoder gives new text, so the fingerprint key of "a" changes to "a2".
        let inserted = try store.storeFetched([
            tx("a2", day(2026, 10, 1), -245, "SPAR AURLAND", "groceries"),
            tx("b", day(2026, 10, 2), -89, "PRESSBYRAN", "shopping"),
            tx("c", day(2026, 10, 3), -50, "ICA", "groceries")], window: day(2026, 7, 25), completesFullFetch: true)
        #expect(inserted == 2)
        let byKey = Dictionary(uniqueKeysWithValues: try store.allTransactions().map { ($0.dedupKey, "\($0.counterparty)|\($0.categoryID)") })
        #expect(Set(byKey.keys) == ["old", "a2", "b", "c", "d"])     // no duplicate of the 245 kr purchase
        #expect(byKey["old"] == "BEFORE WINDOW|transfer")            // not sent back: untouched
        #expect(byKey["a2"] == "SPAR AURLAND|groceries")
        #expect(byKey["b"] == "OLD|takeaway")                        // locked: neither text nor category changes
        #expect(byKey["c"] == "ICA|groceries")
        #expect(byKey["d"] == "NOT SENT BACK|shopping")              // in the window but not returned: kept
        #expect(try store.settings().fullFetchPending == false)
    }

    /// Two 51,95 kr coffees booked the same day without a bank reference, keyed the way `AppModel.refresh` keys a fetch.
    func twoCoffees() -> [Transaction] {
        let coffee = DedupKey.Item(transactionID: nil, entryReference: nil, bookingDate: day(2026, 10, 17), amount: -51.95, currency: "SEK", counterparty: "ESPRESSO HOUSE")
        return DedupKey.makeAll([coffee, coffee]).map { tx($0, day(2026, 10, 17), -51.95, "ESPRESSO HOUSE", "takeaway") }
    }

    @Test func identicalPaymentsWithoutAReferenceAreBothStoredAndARefetchDoesNotMultiplyThem() throws {
        #expect(try store.storeFetched(twoCoffees(), window: day(2026, 10, 1), completesFullFetch: false) == 2)
        #expect(try store.allTransactions().count == 2)
        try store.storeFetched(twoCoffees(), window: day(2026, 10, 1), completesFullFetch: false)
        #expect(try store.allTransactions().count == 2)
    }

    @Test func aHandCategorizedRepeatStaysLockedWhenTheFetchIsStoredAgain() throws {
        let fetch = twoCoffees()
        try store.storeFetched(fetch, window: day(2026, 10, 1), completesFullFetch: false)
        try store.setCategory(fetch[0].dedupKey, to: "groceries")
        try store.storeFetched(fetch, window: day(2026, 10, 1), completesFullFetch: false)
        let byKey = Dictionary(uniqueKeysWithValues: try store.allTransactions().map { ($0.dedupKey, $0.categoryID) })
        #expect(byKey.count == 2)
        #expect(byKey[fetch[0].dedupKey] == "groceries")                   // not replaced by the refetch
        #expect(try store.recategorizeUnlocked { _, _ in "shopping" } == 1)  // and still locked: only the other one changes
    }

    @Test func anEmptyAnswerDoesNotCompleteTheFullFetch() throws {
        _ = try store.insertNew([tx("a", day(2026, 10, 1), -245, "CARL ELELID", "transfer")])
        try store.storeFetched([], window: day(2026, 7, 25), completesFullFetch: true)
        #expect(try store.settings().fullFetchPending)
        #expect(try store.allTransactions().count == 1)
    }

    @Test func anEmptyAnswerCompletesTheFullFetchWhenNothingIsStored() throws {
        try store.storeFetched([], window: day(2026, 7, 25), completesFullFetch: true)
        #expect(try store.settings().fullFetchPending == false)
    }

    @Test func aNormalPullLeavesTheFullFetchFlagAlone() throws {
        try store.storeFetched([tx("c", day(2026, 10, 3), -50, "ICA", "groceries")], window: day(2026, 10, 1), completesFullFetch: false)
        #expect(try store.settings().fullFetchPending)
    }

    @Test func fullFetchPendingDefaultsToTrueAndRoundTrips() throws {
        #expect(Settings().fullFetchPending)
        #expect(try store.settings().fullFetchPending)
        var s = try store.settings()
        s.fullFetchPending = false
        try store.saveSettings(s)
        #expect(try store.settings().fullFetchPending == false)
    }

    @Test func manualCategorySticksWhenRulesChange() throws {
        _ = try store.insertNew([tx("a", day(2026, 10, 1), -10, "ICA", "groceries"), tx("b", day(2026, 10, 2), -20, "ICA", "groceries"),
                                 tx("c", day(2026, 10, 3), -2000, "Avanza", "transfer")])
        try store.setCategory("a", to: "takeaway")
        let changed = try store.recategorizeUnlocked { _, _ in "shopping" }
        #expect(changed == 1)
        let byKey = Dictionary(uniqueKeysWithValues: try store.allTransactions().map { ($0.dedupKey, $0.categoryID) })
        #expect(byKey == ["a": "takeaway", "b": "shopping", "c": "transfer"])  // transfers were detected at ingest and stay
    }

    @Test func purgeRemovesRowsBookedBeforeTheCutoff() throws {
        _ = try store.insertNew([tx("old", day(2026, 6, 30), -1, "x", "shopping"), tx("kept", day(2026, 7, 1), -1, "x", "shopping")])
        #expect(try store.purge(bookedBefore: day(2026, 7, 1)) == 1)
        #expect(try store.allTransactions().map(\.dedupKey) == ["kept"])
    }

    @Test func rulesAreNewestFirst() throws {
        try store.addRule(KeywordRule(keyword: "ica", categoryID: "groceries"))
        try store.addRule(KeywordRule(keyword: "ica", categoryID: "shopping"))
        #expect(try store.rules().map(\.categoryID) == ["shopping", "groceries"])
        try store.deleteRule(keyword: "ica", categoryID: "shopping")
        #expect(try store.rules().count == 1)
    }

    @Test func budgetsAndIncomeSourcesRoundTrip() throws {
        try store.saveBudget(Budget(categoryID: "rent", amount: 10_000, cadence: .monthly))
        try store.saveBudget(Budget(categoryID: "studentLoan", amount: 3_000, cadence: .quarterly(firstDueMonth: 2)))
        try store.saveBudget(Budget(categoryID: "rent", amount: 11_000, cadence: .monthly))  // upsert
        #expect(try store.budgets() == [Budget(categoryID: "rent", amount: 11_000, cadence: .monthly),
                                         Budget(categoryID: "studentLoan", amount: 3_000, cadence: .quarterly(firstDueMonth: 2))])
        try store.deleteBudget(categoryID: "rent")
        #expect(try store.budgets().count == 1)

        let salary = IncomeSource(id: "s1", name: "Lön", plannedAmount: 35_000, keyword: "lön")
        let partner = IncomeSource(id: "s2", name: "Sambo", plannedAmount: 5_000, keyword: nil)
        try store.saveIncomeSource(salary)
        try store.saveIncomeSource(partner)
        #expect(try store.incomeSources() == [salary, partner])
        try store.deleteIncomeSource(id: "s1")
        #expect(try store.incomeSources() == [partner])
    }

    @Test func settingsHoldThePeriodRuleAndRetention() throws {
        #expect(try store.settings().periodRule == PeriodRule(startDay: 25))
        #expect(try store.settings().retention == RetentionPolicy(months: 3))
        #expect(try store.settings().planDone == false)
        var s = try store.settings()
        s.startDay = 27
        s.planDone = true
        s.periodOverrides = [PeriodLabel(year: 2026, month: 12): day(2026, 11, 20)]
        s.retention = RetentionPolicy(months: 12)
        s.selectedAccountUID = "acc-1"
        s.bankName = "Swedbank"
        s.consentValidUntil = day(2027, 4, 15)
        s.ownAccountIDs = ["SE4550000000058398257466", "832791234567890"]
        s.authorizedAccounts = [AuthorizedAccount(uid: "acc-1", title: "Privatkonto", subtitle: "•••• 7466"), AuthorizedAccount(uid: "acc-2", title: "e-sparkonto", subtitle: "•••• 0402")]
        try store.saveSettings(s)
        let back = try store.settings()
        #expect(back.periodRule == PeriodRule(startDay: 27, overrides: [PeriodLabel(year: 2026, month: 12): day(2026, 11, 20)]))
        #expect(back.retention == RetentionPolicy(months: 12))
        #expect(back.selectedAccountUID == "acc-1")
        #expect(back.bankName == "Swedbank")
        #expect(back.consentValidUntil == day(2027, 4, 15))
        #expect(back.ownAccountIDs == ["SE4550000000058398257466", "832791234567890"])
        #expect(back.authorizedAccounts.map(\.uid) == ["acc-1", "acc-2"])
        #expect(back.authorizedAccounts[1].subtitle == "•••• 0402")
        #expect(back.planDone == true)
    }

    @Test func wipeEmptiesEveryTable() throws {
        _ = try store.insertNew([tx("a", day(2026, 10, 1), -10, "ICA", "groceries")])
        try store.addRule(KeywordRule(keyword: "ica", categoryID: "groceries"))
        try store.saveBudget(Budget(categoryID: "rent", amount: 1, cadence: .monthly))
        try store.saveIncomeSource(IncomeSource(id: "s", name: "x", plannedAmount: 1, keyword: nil))
        var s = try store.settings(); s.bankName = "Swedbank"; try store.saveSettings(s)
        try store.wipe()
        #expect(try store.allTransactions().isEmpty && store.rules().isEmpty && store.budgets().isEmpty && store.incomeSources().isEmpty)
        #expect(try store.settings().bankName == nil)
    }

    @Test func openingOnDiskExcludesTheDirectoryFromBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tjugofemte-\(UUID().uuidString)")
        _ = try LocalStore.open(in: dir)
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tjugofemte.sqlite").path))
    }
}

@Suite struct LocalStoreDeletionTests {
    @Test func deletedRowsAreOverwrittenNotJustUnlinked() throws {
        let store = try LocalStore.inMemory()
        #expect(try store.secureDeleteEnabled())
    }

    @Test func wipeCompactsTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tjugofemte-\(UUID().uuidString)")
        let store = try LocalStore.open(in: dir)
        let cal = Calendar.stockholm
        let rows = (0..<2000).map { i in
            Transaction(dedupKey: "k\(i)", bookingDate: cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!, amount: -1, currency: "SEK",
                        counterparty: String(repeating: "SECRET MERCHANT ", count: 8), categoryID: "shopping")
        }
        try store.insertNew(rows)
        let file = dir.appendingPathComponent(LocalStore.fileName)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int
        try store.wipe()
        let after = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int
        #expect(after < before / 4)
        let bytes = try Data(contentsOf: file)
        #expect(!bytes.range(of: Data("SECRET MERCHANT".utf8)).map { _ in true }.isTrue)
    }
}

private extension Optional where Wrapped == Bool {
    var isTrue: Bool { self == true }
}
