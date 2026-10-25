import Foundation
import GRDB
import BudgetCore

/// One account the user authorised, as shown in pickers. Order is the bank's order.
public struct AuthorizedAccount: Equatable, Sendable, Codable, Identifiable {
    public var id: String { uid }
    public let uid: String
    public let title: String
    public let subtitle: String

    public init(uid: String, title: String, subtitle: String) {
        self.uid = uid
        self.title = title
        self.subtitle = subtitle
    }
}

/// Non-secret app state. Secrets (key, application id, session id) live in the Keychain.
public struct Settings: Equatable, Sendable {
    public var startDay = 25
    public var periodOverrides: [PeriodLabel: Date] = [:]
    public var retention = RetentionPolicy(months: 3)
    public var selectedAccountUID: String?
    public var bankName: String?
    public var consentValidUntil: Date?
    /// Identifiers of every account the user authorised, so transfers between them are recognized on later fetches.
    public var ownAccountIDs: Set<String> = []
    public var authorizedAccounts: [AuthorizedAccount] = []
    /// The guided plan setup has run (or been skipped) once; until then the app opens in it.
    public var planDone = false
    /// The next fetch reaches back to the retention cutoff instead of a week before the newest row. True until one
    /// such fetch has succeeded, so installs that stored rows with an older decoder repair themselves.
    public var fullFetchPending = true
    /// The savings goal and hearts from the Goal screen; nil until the user has set a goal.
    public var goal: GoalPreferences?
    /// The user's need and want flips. They point at the current account's spending, so an account switch clears them.
    public var groups = CategoryGroups()
    /// The goal setup has run once; until then an upgraded install shows the "Set a savings goal" card.
    public var goalSetupDone = false
    /// The user has answered how long to keep history on the phone.
    public var retentionAsked = false
    /// The period whose "Adjust plan?" nudge the user dismissed.
    public var nudgeDismissed: PeriodLabel?

    public init() {}
}

/// SQLite on disk, in a directory excluded from backup, protected by iOS Data Protection (class complete).
public final class LocalStore: Sendable {
    public static let fileName = "tjugofemte.sqlite"
    private let db: DatabaseQueue

    public static func inMemory() throws -> LocalStore {
        try LocalStore(try DatabaseQueue(configuration: configuration))
    }

    /// Deleted rows are zeroed on disk instead of merely unlinked.
    private static var configuration: Configuration {
        var c = Configuration()
        c.prepareDatabase { db in try db.execute(sql: "PRAGMA secure_delete = ON") }
        return c
    }

    public static func open(in directory: URL) throws -> LocalStore {
        try open(in: directory, upTo: nil)
    }

    /// `upTo` stops at an older migration, so a test can build the file an older version left behind.
    static func open(in directory: URL, upTo migration: String?) throws -> LocalStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        return try LocalStore(try DatabaseQueue(path: directory.appendingPathComponent(fileName).path, configuration: configuration), upTo: migration)
    }

    init(_ db: DatabaseQueue, upTo migration: String? = nil) throws {
        self.db = db
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "transactions") { t in
                t.primaryKey("dedup_key", .text)
                t.column("booking_date", .datetime).notNull().indexed()
                t.column("amount", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("counterparty", .text).notNull()
                t.column("category_id", .text).notNull()
                t.column("category_locked", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "rules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("keyword", .text).notNull()
                t.column("category_id", .text).notNull()
            }
            try db.create(table: "budgets") { t in
                t.primaryKey("category_id", .text)
                t.column("amount", .text).notNull()
                t.column("cadence", .text).notNull()
                t.column("first_due_month", .integer)
            }
            try db.create(table: "income_sources") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("planned_amount", .text).notNull()
                t.column("keyword", .text)
            }
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        // Savings is no longer spending: the target is what goes to savings, so a budget on it would set the same money aside twice.
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "DELETE FROM budgets WHERE category_id = 'savings'")
        }
        if let migration { try migrator.migrate(db, upTo: migration) } else { try migrator.migrate(db) }
    }

    // MARK: Transactions

    /// Inserts rows whose dedup key is new. Existing rows are left alone, so manual categories survive refetches.
    @discardableResult
    public func insertNew(_ transactions: [Transaction]) throws -> Int {
        try db.write { db in
            var inserted = 0
            for t in transactions {
                try TransactionRow(t).insert(db, onConflict: .ignore)
                inserted += db.changesCount
            }
            return inserted
        }
    }

    public func allTransactions() throws -> [Transaction] {
        try db.read { db in
            try TransactionRow.order(Column("booking_date").desc, Column("dedup_key").desc).fetchAll(db).map(\.transaction)
        }
    }

    public func setCategory(_ dedupKey: String, to categoryID: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE transactions SET category_id = ?, category_locked = 1 WHERE dedup_key = ?", arguments: [categoryID, dedupKey])
        }
    }

    /// Re-runs categorization for rows the user has not touched. Own-account transfers were decided at
    /// ingest from data that is not stored, so they are skipped.
    @discardableResult
    public func recategorizeUnlocked(_ categorize: (String, Decimal) -> String) throws -> Int {
        try db.write { db in
            let rows = try TransactionRow.filter(Column("category_locked") == false && Column("category_id") != DefaultCategory.transfer.rawValue).fetchAll(db)
            var changed = 0
            for row in rows {
                let next = categorize(row.counterparty, Decimal(string: row.amount) ?? 0)
                guard next != row.categoryID else { continue }
                try db.execute(sql: "UPDATE transactions SET category_id = ? WHERE dedup_key = ?", arguments: [next, row.dedupKey])
                changed += 1
            }
            return changed
        }
    }

    /// Stores a fetch. A row the bank sent back replaces untouched rows booked the same day for the same amount, so
    /// text and categories from an older decoder cannot survive and a booking whose fingerprint key changed with its
    /// text is not duplicated. Rows the bank did not send back are kept: which rows a `date_from` returns is the bank's
    /// rule, not ours. Rows the user categorized by hand stay. A full fetch counts as done only when the bank answered
    /// with rows, or when nothing is stored from `from` onwards.
    @discardableResult
    public func storeFetched(_ transactions: [Transaction], window from: Date, completesFullFetch: Bool) throws -> Int {
        try db.write { db in
            for t in transactions {
                try TransactionRow.filter(Column("category_locked") == false && Column("booking_date") == t.bookingDate
                                          && Column("amount") == "\(t.amount)").deleteAll(db)
            }
            var inserted = 0
            for t in transactions {
                try TransactionRow(t).insert(db, onConflict: .ignore)
                inserted += db.changesCount
            }
            if completesFullFetch {
                let stored = try TransactionRow.filter(Column("booking_date") >= from).fetchCount(db)
                if !transactions.isEmpty || stored == 0 {
                    try db.execute(sql: "INSERT INTO settings(key, value) VALUES ('full_fetch_pending', '0') ON CONFLICT(key) DO UPDATE SET value = excluded.value")
                }
            }
            return inserted
        }
    }

    /// Used when switching to another account: its history must not mix with the previous one.
    public func deleteAllTransactions() throws {
        try db.write { db in _ = try TransactionRow.deleteAll(db) }
        try db.vacuum()
    }

    @discardableResult
    public func purge(bookedBefore cutoff: Date) throws -> Int {
        let deleted = try db.write { db in try TransactionRow.filter(Column("booking_date") < cutoff).deleteAll(db) }
        if deleted > 0 { try db.vacuum() }
        return deleted
    }

    func secureDeleteEnabled() throws -> Bool {
        try db.read { db in try Bool.fetchOne(db, sql: "PRAGMA secure_delete") ?? false }
    }

    // MARK: Rules

    public func rules() throws -> [KeywordRule] {
        try db.read { db in try RuleRow.order(Column("id").desc).fetchAll(db).map { KeywordRule(keyword: $0.keyword, categoryID: $0.categoryID) } }
    }

    public func addRule(_ rule: KeywordRule) throws {
        try db.write { db in try RuleRow(id: nil, keyword: rule.keyword, categoryID: rule.categoryID).insert(db) }
    }

    public func deleteRule(keyword: String, categoryID: String) throws {
        try db.write { db in _ = try RuleRow.filter(Column("keyword") == keyword && Column("category_id") == categoryID).deleteAll(db) }
    }

    // MARK: Budgets and income

    public func budgets() throws -> [Budget] {
        try db.read { db in try BudgetRow.order(Column("category_id")).fetchAll(db).map(\.budget) }
    }

    public func saveBudget(_ budget: Budget) throws {
        try db.write { db in try BudgetRow(budget).upsert(db) }
    }

    public func deleteBudget(categoryID: String) throws {
        try db.write { db in _ = try BudgetRow.deleteOne(db, key: categoryID) }
    }

    public func incomeSources() throws -> [IncomeSource] {
        try db.read { db in try IncomeRow.order(Column.rowID).fetchAll(db).map(\.source) }
    }

    public func saveIncomeSource(_ source: IncomeSource) throws {
        try db.write { db in try IncomeRow(source).upsert(db) }
    }

    public func deleteIncomeSource(id: String) throws {
        try db.write { db in _ = try IncomeRow.deleteOne(db, key: id) }
    }

    // MARK: Settings

    public func settings() throws -> Settings {
        try db.read { db in
            let raw = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT key, value FROM settings").map { ($0["key"] as String, $0["value"] as String) })
            var s = Settings()
            if let v = raw["start_day"].flatMap(Int.init) { s.startDay = v }
            if let v = raw["retention_months"].flatMap(Int.init) { s.retention = RetentionPolicy(months: v) }
            s.planDone = raw["plan_done"] == "1"
            s.fullFetchPending = raw["full_fetch_pending"] != "0"
            s.selectedAccountUID = raw["selected_account_uid"]
            s.bankName = raw["bank_name"]
            s.consentValidUntil = raw["consent_valid_until"].flatMap { Double($0) }.map(Date.init(timeIntervalSince1970:))
            if let ids = raw["own_account_ids"], let data = ids.data(using: .utf8), let decoded = try? JSONDecoder().decode([String].self, from: data) {
                s.ownAccountIDs = Set(decoded)
            }
            if let json = raw["authorized_accounts"], let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode([AuthorizedAccount].self, from: data) {
                s.authorizedAccounts = decoded
            }
            if let json = raw["period_overrides"], let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
                for (key, seconds) in decoded {
                    let parts = key.split(separator: "-").compactMap { Int($0) }
                    guard parts.count == 2 else { continue }
                    s.periodOverrides[PeriodLabel(year: parts[0], month: parts[1])] = Date(timeIntervalSince1970: seconds)
                }
            }
            if let json = raw["goal_preferences"], let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode(GoalPreferences.self, from: data) {
                s.goal = decoded
            }
            if let json = raw["group_overrides"], let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode(CategoryGroups.self, from: data) {
                s.groups = decoded
            }
            s.goalSetupDone = raw["goal_setup_done"] == "1"
            s.retentionAsked = raw["retention_asked"] == "1"
            if let parts = raw["nudge_dismissed"]?.split(separator: "-").compactMap({ Int($0) }), parts.count == 2 {
                s.nudgeDismissed = PeriodLabel(year: parts[0], month: parts[1])
            }
            return s
        }
    }

    public func saveSettings(_ s: Settings) throws {
        let overrides = Dictionary(uniqueKeysWithValues: s.periodOverrides.map { ("\($0.key.year)-\($0.key.month)", $0.value.timeIntervalSince1970) })
        let json = String(decoding: try JSONEncoder().encode(overrides), as: UTF8.self)
        let pairs: [(String, String?)] = [
            ("start_day", String(s.startDay)),
            ("retention_months", String(s.retention.months)),
            ("plan_done", s.planDone ? "1" : "0"),
            ("full_fetch_pending", s.fullFetchPending ? "1" : "0"),
            ("selected_account_uid", s.selectedAccountUID),
            ("bank_name", s.bankName),
            ("consent_valid_until", s.consentValidUntil.map { String($0.timeIntervalSince1970) }),
            ("period_overrides", json),
            ("own_account_ids", String(decoding: try JSONEncoder().encode(s.ownAccountIDs.sorted()), as: UTF8.self)),
            ("authorized_accounts", String(decoding: try JSONEncoder().encode(s.authorizedAccounts), as: UTF8.self)),
            ("goal_preferences", try s.goal.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }),
            ("group_overrides", String(decoding: try JSONEncoder().encode(s.groups), as: UTF8.self)),
            ("goal_setup_done", s.goalSetupDone ? "1" : "0"),
            ("retention_asked", s.retentionAsked ? "1" : "0"),
            ("nudge_dismissed", s.nudgeDismissed.map { "\($0.year)-\($0.month)" }),
        ]
        try db.write { db in
            for (key, value) in pairs {
                if let value {
                    try db.execute(sql: "INSERT INTO settings(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [key, value])
                } else {
                    try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key])
                }
            }
        }
    }

    // MARK: Delete everything

    public func wipe() throws {
        try db.write { db in
            for table in ["transactions", "rules", "budgets", "income_sources", "settings"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        try db.vacuum()
    }
}

// MARK: - Rows

private struct TransactionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transactions"
    var dedupKey: String
    var bookingDate: Date
    var amount: String
    var currency: String
    var counterparty: String
    var categoryID: String
    var categoryLocked: Bool

    enum CodingKeys: String, CodingKey {
        case dedupKey = "dedup_key", bookingDate = "booking_date", amount, currency, counterparty
        case categoryID = "category_id", categoryLocked = "category_locked"
    }

    init(_ t: Transaction) {
        dedupKey = t.dedupKey; bookingDate = t.bookingDate; amount = "\(t.amount)"; currency = t.currency
        counterparty = t.counterparty; categoryID = t.categoryID; categoryLocked = false
    }

    var transaction: Transaction {
        Transaction(dedupKey: dedupKey, bookingDate: bookingDate, amount: Decimal(string: amount) ?? 0, currency: currency, counterparty: counterparty, categoryID: categoryID)
    }
}

private struct RuleRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "rules"
    var id: Int64?
    var keyword: String
    var categoryID: String
    enum CodingKeys: String, CodingKey { case id, keyword, categoryID = "category_id" }
}

private struct BudgetRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "budgets"
    var categoryID: String
    var amount: String
    var cadence: String
    var firstDueMonth: Int?
    enum CodingKeys: String, CodingKey { case categoryID = "category_id", amount, cadence, firstDueMonth = "first_due_month" }

    init(_ b: Budget) {
        categoryID = b.categoryID; amount = "\(b.amount)"
        switch b.cadence {
        case .monthly: cadence = "monthly"; firstDueMonth = nil
        case .quarterly(let month): cadence = "quarterly"; firstDueMonth = month
        }
    }

    var budget: Budget {
        Budget(categoryID: categoryID, amount: Decimal(string: amount) ?? 0,
               cadence: cadence == "quarterly" ? .quarterly(firstDueMonth: firstDueMonth ?? 1) : .monthly)
    }
}

private struct IncomeRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "income_sources"
    var id: String
    var name: String
    var plannedAmount: String
    var keyword: String?
    enum CodingKeys: String, CodingKey { case id, name, plannedAmount = "planned_amount", keyword }

    init(_ s: IncomeSource) { id = s.id; name = s.name; plannedAmount = "\(s.plannedAmount)"; keyword = s.keyword }
    var source: IncomeSource { IncomeSource(id: id, name: name, plannedAmount: Decimal(string: plannedAmount) ?? 0, keyword: keyword) }
}
