import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BudgetCore
import EnableBankingKit
import LocalStore

@MainActor
@Observable
final class AppModel {
    enum Stage: Equatable { case needsKey, needsApplicationID, needsBank, needsAccount, ready }

    private let diskStore: LocalStore
    private var demoStore: LocalStore?
    private let auth = AuthCoordinator()

    private(set) var settings = Settings()
    private(set) var transactions: [Transaction] = []
    private(set) var rules: [KeywordRule] = []
    private(set) var budgets: [Budget] = []
    private(set) var incomeSources: [IncomeSource] = []
    /// Period starts read off the salary's booking days, recomputed on every reload.
    private var salaryStarts: [PeriodLabel: Date] = [:]
    var selectedPeriod: PeriodLabel

    private(set) var hasKey = Keychain.privateKey() != nil
    private(set) var applicationID = Keychain.string(.applicationID)
    private(set) var sessionID = Keychain.string(.sessionID)
    private(set) var banks: [Bank] = []
    private(set) var isBusy = false
    private(set) var needsReauth = false
    var errorMessage: String?

    var isDemo: Bool { demoStore != nil }
    private var store: LocalStore { demoStore ?? diskStore }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tjugofemte")
        diskStore = try! LocalStore.open(in: support)
        selectedPeriod = PeriodLabel(year: 2000, month: 1)
        reload()
        selectedPeriod = periodRule.period(containing: Date()).label
        try? purge()
        // Screenshots, UI tests and App Review notes: `-demo` opens straight into sample data.
        if ProcessInfo.processInfo.arguments.contains("-demo") { startDemo() }
    }

    var stage: Stage {
        if isDemo { return .ready }
        if !hasKey { return .needsKey }
        if applicationID == nil { return .needsApplicationID }
        if sessionID == nil { return .needsBank }
        if settings.selectedAccountUID == nil { return .needsAccount }
        return .ready
    }

    /// Demo counts as set up. A real install is set up once an account is chosen and the plan setup has run or been skipped;
    /// until then the app opens in the start flow.
    var isSetUp: Bool { isDemo || (stage == .ready && settings.planDone) }
    var hasPlan: Bool { !budgets.isEmpty || !incomeSources.isEmpty }

    /// Each period starts the day the salary booked; a start picked by hand in Settings wins.
    var periodRule: PeriodRule {
        PeriodRule(startDay: settings.startDay, overrides: SalaryStarts.overrides(detected: salaryStarts, manual: settings.periodOverrides))
    }

    /// The same rule for a payday that is not saved yet, as the plan setup previews it.
    func periodRule(startDay: Int) -> PeriodRule {
        guard startDay != settings.startDay else { return periodRule }
        let detected = SalaryStarts.detect(transactions: transactions, incomeSources: incomeSources, startDay: startDay)
        return PeriodRule(startDay: startDay, overrides: SalaryStarts.overrides(detected: detected, manual: settings.periodOverrides))
    }

    var period: PayPeriod { periodRule.period(labeled: selectedPeriod) }

    var summary: PeriodSummary {
        BudgetMath.summarize(period: period, rule: periodRule, transactions: transactions, budgets: budgets, incomeSources: incomeSources)
    }

    func reload() {
        do {
            settings = try store.settings()
            transactions = try store.allTransactions()
            rules = try store.rules()
            budgets = try store.budgets()
            incomeSources = try store.incomeSources()
        } catch {
            errorMessage = error.localizedDescription
        }
        salaryStarts = SalaryStarts.detect(transactions: transactions, incomeSources: incomeSources, startDay: settings.startDay)
    }

    // MARK: Onboarding

    /// RSA-4096 generation can take a few seconds on a phone, so it runs off the main actor.
    func generateKey() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) { _ = try Keychain.generatePrivateKey() }.value
            hasKey = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publicKeyPEM() -> String? {
        guard let key = Keychain.privateKey() else { return nil }
        return try? RSAKey(privateKey: key, keyID: "").publicKeyPEM()
    }

    /// Local-only pasteboard: the key and id stay off Universal Clipboard.
    func copyLocally(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
    }

    /// Reads the system pasteboard once, for the Application ID copied from the control panel.
    func pasteboardString() -> String? {
        UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearApplicationID() {
        try? Keychain.set(nil, for: .applicationID)
        applicationID = nil
    }

    func saveApplicationID(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try Keychain.set(trimmed, for: .applicationID)
            applicationID = trimmed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Connecting

    private func client() throws -> EnableBankingClient {
        guard let key = Keychain.privateKey(), let appID = applicationID else { throw AuthCoordinator.Failure.noCode }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return EnableBankingClient(signer: RSAKey(privateKey: key, keyID: appID),
                                   psu: PSUHeaders(ipAddress: PSUHeaders.deviceIPv4Address(), userAgent: "Tjugofemte/\(version) iOS"))
    }

    func loadBanks() async {
        isBusy = true
        defer { isBusy = false }
        do {
            banks = try await client().aspsps(country: "SE").sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Prefer the redirect flow for private customers. Returns the credential names the bank insists on (e.g. ssn).
    func requiredCredentials(for bank: Bank) -> [String] {
        preferredMethod(for: bank)?.requiredCredentials ?? []
    }

    private func preferredMethod(for bank: Bank) -> AuthMethod? {
        let personal = (bank.authMethods ?? []).filter { $0.psuType == nil || $0.psuType == "personal" }
        return personal.first { $0.approach == "REDIRECT" } ?? personal.first
    }

    func connect(bank: Bank, psuID: String?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try client()
            let state = UUID().uuidString
            try Keychain.set(state, for: .authState)
            let validUntil = Date().addingTimeInterval(TimeInterval(bank.maximumConsentValidity ?? 90 * 24 * 3600) - 120)
            let start = try await client.startAuth(bank: BankRef(name: bank.name, country: bank.country), redirectURL: AuthCoordinator.redirectURL,
                                                   state: state, validUntil: validUntil, authMethod: preferredMethod(for: bank)?.name, psuID: psuID)
            let code = try await auth.authorize(url: start.url, state: state)
            try await completeSession(code: code)
        } catch AuthCoordinator.Failure.cancelled {
            // user closed the browser; nothing to report
        } catch {
            errorMessage = describe(error)
        }
    }

    private func completeSession(code: String) async throws {
        let session = try await client().createSession(code: code)
        try Keychain.set(session.sessionID, for: .sessionID)
        try Keychain.set(nil, for: .authState)
        sessionID = session.sessionID
        needsReauth = false
        var s = settings
        s.bankName = session.bankName
        s.consentValidUntil = session.validUntil
        s.ownAccountIDs = Set(session.accounts.flatMap(\.ownAccountIDs))
        s.authorizedAccounts = session.accounts.map(Self.listed)
        s.selectedAccountUID = nil
        try store.saveSettings(s)
        settings = s
        await ConsentReminders.schedule(validUntil: session.validUntil)
        if session.accounts.count == 1 { await chooseAccount(session.accounts[0].uid) }
    }

    private static func listed(_ account: BankAccount) -> AuthorizedAccount {
        AuthorizedAccount(uid: account.uid, title: account.product ?? account.name ?? String(localized: "Account"), subtitle: account.maskedNumber)
    }

    /// Older installs have a session but no stored account list; rebuild it from Enable Banking.
    func ensureAccountsListed() async {
        guard let sessionID, settings.authorizedAccounts.isEmpty, !isDemo else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try client()
            var accounts: [BankAccount] = []
            for uid in try await client.sessionAccountUIDs(sessionID) {
                accounts.append(try await client.accountDetails(uid: uid))
            }
            var s = settings
            s.authorizedAccounts = accounts.map(Self.listed)
            s.ownAccountIDs = Set(accounts.flatMap(\.ownAccountIDs))
            try store.saveSettings(s)
            settings = s
        } catch ClientError.sessionExpired {
            needsReauth = true
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Another authorised account, no BankID needed. The old account's history is removed first.
    func switchAccount(to uid: String) async {
        guard uid != settings.selectedAccountUID else { return }
        do {
            try store.deleteAllTransactions()
            var s = settings
            s.selectedAccountUID = uid
            try store.saveSettings(s)
            settings = s
            reload()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Callback via the scene's open-URL path. Warm app: hand it to the running flow. Cold start (iOS killed
    /// the app while the user was in BankID): the nonce persisted before the flow started decides whether
    /// the URL is ours; anything else is ignored.
    func handleOpenURL(_ url: URL) {
        if auth.hasPendingFlow {
            auth.handleOpenURL(url)
            return
        }
        guard url.scheme == AuthCoordinator.scheme, let expected = Keychain.string(.authState),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == expected,
              let code = items.first(where: { $0.name == "code" })?.value else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do { try await completeSession(code: code) } catch { errorMessage = describe(error) }
        }
    }

    func chooseAccount(_ uid: String) async {
        do {
            var s = settings
            s.selectedAccountUID = uid
            try store.saveSettings(s)
            settings = s
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Fetching

    func refresh() async {
        guard !isDemo, stage == .ready, let uid = settings.selectedAccountUID else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let cutoff = settings.retention.cutoff(today: Date())
            let overlap = transactions.first.map { Calendar.stockholm.date(byAdding: .day, value: -7, to: $0.bookingDate)! }
            let fullFetch = settings.fullFetchPending
            let from = fullFetch ? cutoff : max(cutoff, overlap ?? cutoff)
            let fetched = try await client().transactions(accountUID: uid, from: from)
            let categorizer = Categorizer(userRules: rules, ownAccountIDs: settings.ownAccountIDs)
            let fresh = fetched.records.map { r in
                Transaction(dedupKey: DedupKey.make(transactionID: r.transactionID, entryReference: r.entryReference, bookingDate: r.bookingDate,
                                                    amount: r.amount, currency: r.currency, counterparty: r.counterparty),
                            bookingDate: r.bookingDate, amount: r.amount, currency: r.currency, counterparty: r.counterparty,
                            categoryID: categorizer.categorize(text: r.counterparty, amount: r.amount, counterpartyAccountID: r.counterpartyAccountID))
            }
            try store.storeFetched(fresh, window: fetched.from, completesFullFetch: fullFetch)
            try purge()
            reload()
        } catch ClientError.sessionExpired {
            needsReauth = true
        } catch {
            errorMessage = describe(error)
        }
    }

    private func purge() throws {
        try store.purge(bookedBefore: settings.retention.cutoff(today: Date()))
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case ClientError.rateLimited: String(localized: "The bank is rate limiting requests. Try again in a few hours.")
        case ClientError.wrongPeriod: String(localized: "The bank only shares the last 90 days.")
        case ClientError.http(let status, let code, let message): "\(message ?? "HTTP \(status)")\(code.map { " (\($0))" } ?? "")"
        case ClientError.decoding(let detail): String(localized: "Unexpected response from Enable Banking: \(detail)")
        case AuthCoordinator.Failure.bankError(let text): text
        case AuthCoordinator.Failure.stateMismatch: String(localized: "The login response did not match this app's request. Try again.")
        default: error.localizedDescription
        }
    }

    // MARK: Editing

    func setCategory(_ transaction: Transaction, to categoryID: String, always: Bool) {
        do {
            try store.setCategory(transaction.dedupKey, to: categoryID)
            if always {
                try store.addRule(KeywordRule(keyword: transaction.counterparty, categoryID: categoryID))
                try recategorize()
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addRule(_ rule: KeywordRule) {
        do { try store.addRule(rule); try recategorize(); reload() } catch { errorMessage = error.localizedDescription }
    }

    func deleteRule(_ rule: KeywordRule) {
        do { try store.deleteRule(keyword: rule.keyword, categoryID: rule.categoryID); try recategorize(); reload() } catch { errorMessage = error.localizedDescription }
    }

    private func recategorize() throws {
        let categorizer = Categorizer(userRules: try store.rules(), ownAccountIDs: settings.ownAccountIDs)
        try store.recategorizeUnlocked { text, amount in categorizer.categorize(text: text, amount: amount) }
    }

    func saveBudget(_ budget: Budget) { do { try store.saveBudget(budget); reload() } catch { errorMessage = error.localizedDescription } }
    func deleteBudget(categoryID: String) { do { try store.deleteBudget(categoryID: categoryID); reload() } catch { errorMessage = error.localizedDescription } }
    func saveIncomeSource(_ source: IncomeSource) { do { try store.saveIncomeSource(source); reload() } catch { errorMessage = error.localizedDescription } }
    func deleteIncomeSource(id: String) { do { try store.deleteIncomeSource(id: id); reload() } catch { errorMessage = error.localizedDescription } }

    // MARK: Plan setup

    func incomeSuggestions(rule: PeriodRule) -> [IncomeSuggestion] { PlanSuggestions.incomes(transactions: transactions, rule: rule) }
    func budgetSuggestions(rule: PeriodRule) -> BudgetSuggestions { PlanSuggestions.budgets(transactions: transactions, rule: rule) }
    func paydayGuess() -> Int? { PlanSuggestions.payday(transactions: transactions, rule: periodRule) }

    /// The setup writes the whole plan at once; sources and budgets left out of it are removed.
    func applyPlan(startDay: Int, incomes: [IncomeSource], budgets newBudgets: [Budget]) {
        do {
            for s in incomeSources where !incomes.contains { $0.id == s.id } { try store.deleteIncomeSource(id: s.id) }
            for b in budgets where !newBudgets.contains { $0.categoryID == b.categoryID } { try store.deleteBudget(categoryID: b.categoryID) }
            for s in incomes { try store.saveIncomeSource(s) }
            for b in newBudgets { try store.saveBudget(b) }
        } catch {
            errorMessage = error.localizedDescription
        }
        updateSettings { $0.startDay = startDay; $0.planDone = true }
    }

    func skipPlan() { updateSettings { $0.planDone = true } }

    func updateSettings(_ change: (inout Settings) -> Void) {
        var s = settings
        change(&s)
        do {
            try store.saveSettings(s)
            settings = s
            try purge()
            reload()
            selectedPeriod = periodRule.period(containing: Date()).label
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Data

    /// Written with complete file protection; the share sheet deletes it when done, and so does Delete everything.
    func exportCSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tjugofemte-\(CSVExporter.isoDay(Date())).csv")
        try Data(CSVExporter.export(transactions).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func removeExports() {
        let tmp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix("tjugofemte-") && name.hasSuffix(".csv") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    /// Closes the Enable Banking session first so the bank consent does not linger, then wipes everything local.
    func deleteEverything() async {
        isBusy = true
        defer { isBusy = false }
        if let sessionID, let client = try? client() { try? await client.deleteSession(sessionID) }
        ConsentReminders.cancel()
        Keychain.wipe()
        Self.removeExports()
        try? diskStore.wipe()
        demoStore = nil
        hasKey = false
        applicationID = nil
        sessionID = nil
        needsReauth = false
        reload()
        selectedPeriod = periodRule.period(containing: Date()).label
    }

    func disconnectBank() async {
        if let sessionID, let client = try? client() { try? await client.deleteSession(sessionID) }
        ConsentReminders.cancel()
        try? Keychain.set(nil, for: .sessionID)
        sessionID = nil
        needsReauth = false
        updateSettings { $0.selectedAccountUID = nil; $0.bankName = nil; $0.consentValidUntil = nil; $0.ownAccountIDs = []; $0.authorizedAccounts = [] }
    }

    // MARK: Demo

    func startDemo() {
        do {
            let demo = try LocalStore.inMemory()
            let rule = PeriodRule(startDay: 25)
            try demo.insertNew(DemoData.transactions(rule: rule))
            for b in DemoData.budgets { try demo.saveBudget(b) }
            for s in DemoData.incomeSources { try demo.saveIncomeSource(s) }
            var s = try demo.settings()
            s.bankName = "Demo"
            try demo.saveSettings(s)
            demoStore = demo
            reload()
            selectedPeriod = periodRule.period(containing: Date()).label
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopDemo() {
        demoStore = nil
        reload()
        selectedPeriod = periodRule.period(containing: Date()).label
    }
}
