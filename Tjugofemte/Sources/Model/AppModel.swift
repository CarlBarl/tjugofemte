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
    var selectedPeriod: PeriodLabel

    private(set) var hasKey = Keychain.privateKey() != nil
    private(set) var applicationID = Keychain.string(.applicationID)
    private(set) var sessionID = Keychain.string(.sessionID)
    private(set) var pendingAccounts: [BankAccount] = []
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
        selectedPeriod = settings.periodRule.period(containing: Date()).label
        try? purge()
    }

    var stage: Stage {
        if isDemo { return .ready }
        if !hasKey { return .needsKey }
        if applicationID == nil { return .needsApplicationID }
        if sessionID == nil { return .needsBank }
        if settings.selectedAccountUID == nil { return .needsAccount }
        return .ready
    }

    var periodRule: PeriodRule { settings.periodRule }
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
    }

    // MARK: Onboarding

    /// RSA-4096 generation can take a few seconds on a phone, so it runs off the main actor.
    func generateKey() async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await Task.detached(priority: .userInitiated) { try Keychain.generatePrivateKey() }.value
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
            banks = try await client().aspsps(country: "SE").filter { $0.beta != true }.sorted { $0.name < $1.name }
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Prefer the redirect flow for private customers. Returns the credential names the bank insists on (e.g. ssn).
    func requiredCredentials(for bank: Bank) -> [String] {
        preferredMethod(for: bank)?.requiredCredentials ?? []
    }

    private func preferredMethod(for bank: Bank) -> AuthMethod? {
        let personal = bank.authMethods.filter { $0.psuType == nil || $0.psuType == "personal" }
        return personal.first { $0.approach == "REDIRECT" } ?? personal.first
    }

    func connect(bank: Bank, psuID: String?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try client()
            let state = UUID().uuidString
            try Keychain.set(state, for: .authState)
            let validUntil = Date().addingTimeInterval(TimeInterval(bank.maximumConsentValidity) - 120)
            let start = try await client.startAuth(bank: BankRef(name: bank.name, country: bank.country), redirectURL: AuthCoordinator.redirectURL,
                                                   state: state, validUntil: validUntil, authMethod: preferredMethod(for: bank)?.name, psuID: psuID)
            let code = try await auth.authorize(url: start.url, state: state)
            let session = try await client.createSession(code: code)
            try Keychain.set(session.sessionID, for: .sessionID)
            try Keychain.set(nil, for: .authState)
            sessionID = session.sessionID
            needsReauth = false
            var s = settings
            s.bankName = bank.name
            s.consentValidUntil = session.validUntil
            s.ownAccountIDs = Set(session.accounts.flatMap(\.ownAccountIDs))
            s.selectedAccountUID = nil
            try store.saveSettings(s)
            settings = s
            pendingAccounts = session.accounts
            await ConsentReminders.schedule(validUntil: session.validUntil)
            if session.accounts.count == 1 { await chooseAccount(session.accounts[0].uid) }
        } catch AuthCoordinator.Failure.cancelled {
            // user closed the browser; nothing to report
        } catch {
            errorMessage = describe(error)
        }
    }

    func handleOpenURL(_ url: URL) {
        auth.handleOpenURL(url)
    }

    func chooseAccount(_ uid: String) async {
        do {
            var s = settings
            s.selectedAccountUID = uid
            try store.saveSettings(s)
            settings = s
            pendingAccounts = []
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
            let from = max(cutoff, overlap ?? cutoff)
            let records = try await client().transactions(accountUID: uid, from: from)
            let categorizer = Categorizer(userRules: rules, ownAccountIDs: settings.ownAccountIDs)
            let fresh = records.map { r in
                Transaction(dedupKey: DedupKey.make(transactionID: r.transactionID, entryReference: r.entryReference, bookingDate: r.bookingDate,
                                                    amount: r.amount, currency: r.currency, counterparty: r.counterparty),
                            bookingDate: r.bookingDate, amount: r.amount, currency: r.currency, counterparty: r.counterparty,
                            categoryID: categorizer.categorize(text: r.counterparty, amount: r.amount, counterpartyAccountID: r.counterpartyAccountID))
            }
            try store.insertNew(fresh)
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

    func exportCSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tjugofemte-\(CSVExporter.isoDay(Date())).csv")
        try CSVExporter.export(transactions).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Closes the Enable Banking session first so the bank consent does not linger, then wipes everything local.
    func deleteEverything() async {
        isBusy = true
        defer { isBusy = false }
        if let sessionID, let client = try? client() { try? await client.deleteSession(sessionID) }
        ConsentReminders.cancel()
        Keychain.wipe()
        try? diskStore.wipe()
        demoStore = nil
        hasKey = false
        applicationID = nil
        sessionID = nil
        pendingAccounts = []
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
        updateSettings { $0.selectedAccountUID = nil; $0.bankName = nil; $0.consentValidUntil = nil; $0.ownAccountIDs = [] }
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
