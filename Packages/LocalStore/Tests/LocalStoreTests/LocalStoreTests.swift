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
        var s = try store.settings()
        s.startDay = 27
        s.periodOverrides = [PeriodLabel(year: 2026, month: 12): day(2026, 11, 20)]
        s.retention = RetentionPolicy(months: 12)
        s.selectedAccountUID = "acc-1"
        s.bankName = "Swedbank"
        s.consentValidUntil = day(2027, 4, 15)
        try store.saveSettings(s)
        let back = try store.settings()
        #expect(back.periodRule == PeriodRule(startDay: 27, overrides: [PeriodLabel(year: 2026, month: 12): day(2026, 11, 20)]))
        #expect(back.retention == RetentionPolicy(months: 12))
        #expect(back.selectedAccountUID == "acc-1")
        #expect(back.bankName == "Swedbank")
        #expect(back.consentValidUntil == day(2027, 4, 15))
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
