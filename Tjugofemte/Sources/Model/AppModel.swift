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
    /// Payday, the salary's booking days and manual starts, rebuilt on every reload; only a reload changes those inputs.
    private(set) var periodRule = PeriodRule(startDay: Settings().startDay)
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
        // Rows stored before Unsorted existed fell back to shopping; the rules run over them once more.
        if settings.categorizerVersion < Self.categorizerVersion {
            do {
                try recategorize()
                updateSettings { $0.categorizerVersion = Self.categorizerVersion }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        // An install that already keeps 12 months or more has nothing to gain from the history prompt, so it is never shown.
        if !settings.retentionAsked && settings.retention.months >= Self.promptedRetention { updateSettings { $0.retentionAsked = true } }
        try? purge()
        // Screenshots, UI tests and App Review notes: `-demo` opens straight into sample data, `-demo-upgrade` into
        // sample data from before the goal setup.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demo") || arguments.contains("-demo-upgrade") { startDemo() }
    }

    /// Raised when the categorizer's fallback or default rules change, so stored rows are recategorized on the next launch.
    private static let categorizerVersion = 2

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

    var period: PayPeriod { periodRule.period(labeled: selectedPeriod) }

    var summary: PeriodSummary {
        BudgetMath.summarize(period: period, rule: periodRule, transactions: transactions, budgets: budgets, incomeSources: incomeSources)
    }

    func reload() {
        let before = periodRule
        do {
            settings = try store.settings()
            transactions = try store.allTransactions()
            rules = try store.rules()
            budgets = try store.budgets()
            incomeSources = try store.incomeSources()
        } catch {
            errorMessage = error.localizedDescription
        }
        periodRule = .resolved(startDay: settings.startDay, manual: settings.periodOverrides, transactions: transactions, incomeSources: incomeSources)
        // A fetched salary, a recategorized row, an edited income source or a settings change can move the boundaries;
        // today's period follows them, any other selected period stays, and a new payday shows today's.
        selectedPeriod = periodRule.keepingToday(selectedPeriod, from: before)
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
            s.goal = nil
            s.groups = CategoryGroups()
            s.goalSetupDone = false
            s.nudgeDismissed = nil
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
            let keys = DedupKey.makeAll(fetched.records.map { r in
                DedupKey.Item(transactionID: r.transactionID, entryReference: r.entryReference, bookingDate: r.bookingDate,
                              amount: r.amount, currency: r.currency, counterparty: r.counterparty)
            })
            let fresh = zip(fetched.records, keys).map { r, key in
                Transaction(dedupKey: key, bookingDate: r.bookingDate, amount: r.amount, currency: r.currency, counterparty: r.counterparty,
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

    /// A want budget edited here counts as hearted at that amount on the Goal screen.
    func saveBudget(_ budget: Budget) {
        do {
            try store.saveBudget(budget)
            if let goal = settings.goal {
                var s = settings
                s.goal = GoalSetup.edited(budget, groups: settings.groups, prefs: goal)
                try store.saveSettings(s)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    func deleteBudget(categoryID: String) { do { try store.deleteBudget(categoryID: categoryID); reload() } catch { errorMessage = error.localizedDescription } }
    func saveIncomeSource(_ source: IncomeSource) { do { try store.saveIncomeSource(source); reload() } catch { errorMessage = error.localizedDescription } }
    func deleteIncomeSource(id: String) { do { try store.deleteIncomeSource(id: id); reload() } catch { errorMessage = error.localizedDescription } }

    // MARK: Plan setup

    func incomeSuggestions(rule: PeriodRule) -> [IncomeSuggestion] { PlanSuggestions.incomes(transactions: transactions, rule: rule) }
    func paydayGuess() -> Int? { PlanSuggestions.payday(transactions: transactions, rule: periodRule) }

    /// The periods for a payday and income sources the setup has not saved yet, resolved as `reload` resolves the saved ones.
    func periodRule(startDay: Int, incomes: [IncomeSource]) -> PeriodRule {
        .resolved(startDay: startDay, manual: settings.periodOverrides, transactions: transactions, incomeSources: incomes)
    }

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

    func analysis() -> SpendingAnalysis { analysis(rule: periodRule, incomes: incomeSources) }

    /// The setup's steps 3 to 6 pass the payday and income sources it has not saved yet.
    func analysis(rule: PeriodRule, incomes: [IncomeSource]) -> SpendingAnalysis {
        SpendingAnalysis.analyze(transactions: transactions, rule: rule, groups: settings.groups, incomeSources: incomes)
    }

    func sortCandidates() -> [SortCandidate] { SortStep.candidates(transactions: transactions) }
    func sortedShare() -> Decimal { SortStep.sortedShare(transactions: transactions) }

    /// Files the merchant from now on. The candidates and the share are read again from the recategorized rows.
    func file(_ candidate: SortCandidate, as categoryID: String) { addRule(KeywordRule(keyword: candidate.keyword, categoryID: categoryID)) }

    func recurringCharges() -> [RecurringCharge] { RecurringDetector.detect(transactions: transactions) }

    func goalInput(plannedIncome: Decimal) -> GoalInput { goalInput(plannedIncome: plannedIncome, rule: periodRule) }

    /// With the setup's payday when it is not saved yet.
    func goalInput(plannedIncome: Decimal, rule: PeriodRule) -> GoalInput {
        GoalSetup.input(plannedIncome: plannedIncome, transactions: transactions, rule: rule, budgets: planningBudgets(rule: rule), groups: settings.groups)
    }

    /// Writes the goal's budgets the way `applyPlan` writes a plan, then keeps the goal and hearts.
    func applyGoalPlan(startDay: Int, incomes: [IncomeSource], input: GoalInput, prefs: GoalPreferences) {
        let existing = planningBudgets(rule: periodRule(startDay: startDay, incomes: incomes))
        applyPlan(startDay: startDay, incomes: incomes, budgets: GoalSetup.budgets(input: input, prefs: prefs, existing: existing))
        updateSettings { $0.goal = prefs; $0.goalSetupDone = true }
    }

    /// The stored budgets, and a quarterly one for each need the transactions show is paid once a quarter and has none,
    /// so a first run plans CSN at a third each period rather than its payments averaged over every period.
    private func planningBudgets(rule: PeriodRule) -> [Budget] {
        budgets + GoalSetup.quarterlyNeeds(transactions: transactions, rule: rule, groups: settings.groups, budgets: budgets)
    }

    /// "Keep up to 12 months on this phone?" before the setup and the upgrade card: only while the phone keeps less.
    var asksRetention: Bool { !settings.retentionAsked && settings.retention.months < Self.promptedRetention }
    private static let promptedRetention = 12

    /// The answer to "Keep up to 12 months on this phone?". It never shortens the history, which only Settings does. A
    /// longer history needs one fetch back to the new cutoff, because a normal refresh starts a week before the newest
    /// stored row.
    func chooseRetention(months: Int) {
        let kept = max(months, settings.retention.months)
        let longer = kept > settings.retention.months
        updateSettings {
            $0.retention = RetentionPolicy(months: kept)
            $0.retentionAsked = true
            if longer { $0.fullFetchPending = true }
        }
        Task { await refresh() }
    }

    /// Overview's "Set a savings goal", for installs set up before the goal setup existed.
    var showsGoalCard: Bool { isSetUp && !settings.goalSetupDone }

    /// Overview's "Adjust plan?": the last complete period, the one before today's, ended more than 5 % of planned income
    /// in the red. At most once per period.
    var showsNudge: Bool {
        guard settings.goalSetupDone, settings.nudgeDismissed != selectedPeriod else { return false }
        return GoalNudge.shouldShow(lastComplete: lastCompleteSummary, plannedIncome: incomeSources.reduce(0) { $0 + $1.plannedAmount },
                                    budgets: budgets, transactions: transactions)
    }

    func dismissNudge() { updateSettings { $0.nudgeDismissed = selectedPeriod } }

    /// "Takeaway went 1 210 kr over" on the nudge: the budget the last complete period overran the most.
    var lastPeriodOverrun: CategoryLine? { GoalNudge.biggestOverrun(lastComplete: lastCompleteSummary) }

    /// Overview's "last period 13 %": the last complete period's savings rate alone, rounded down as the Goal screen's
    /// "Now" is. nil when the phone does not hold all of that period, or it had no income.
    var lastPeriodPercent: Int? {
        let last = SpendingAnalysis.analyze(transactions: transactions, rule: periodRule, groups: settings.groups, incomeSources: incomeSources, maxPeriods: 1)
        guard last.periods == 1, var value = last.savingsRate.map({ $0 * 100 }) else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// The period before today's, the last one that is over.
    private var lastCompleteSummary: PeriodSummary {
        let last = periodRule.period(labeled: periodRule.period(containing: Date()).label.previous)
        return BudgetMath.summarize(period: last, rule: periodRule, transactions: transactions, budgets: budgets, incomeSources: incomeSources)
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        var s = settings
        change(&s)
        do {
            try store.saveSettings(s)
            settings = s
            try purge()
            reload()  // keeps the selected period, so editing a past period's start stays on it
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
            // `-demo-upgrade` opens as an install from before the goal setup: the old budgets and the "Set a savings goal" card.
            let upgrade = ProcessInfo.processInfo.arguments.contains("-demo-upgrade")
            for r in DemoData.rules { try demo.addRule(r) }
            try demo.insertNew(DemoData.transactions(rule: rule))
            for b in upgrade ? DemoData.budgets : DemoData.quarterlyBudgets { try demo.saveBudget(b) }
            for s in DemoData.incomeSources { try demo.saveIncomeSource(s) }
            var s = try demo.settings()
            s.bankName = "Demo"
            // Twelve periods of history: the default three months would purge most of it on the first settings change.
            s.retention = RetentionPolicy(months: 12)
            try demo.saveSettings(s)
            demoStore = demo
            reload()
            selectedPeriod = periodRule.period(containing: Date()).label
            // `-demo` opens finished: the goal setup has run at its default goal.
            if !upgrade {
                let input = goalInput(plannedIncome: incomeSources.reduce(0) { $0 + $1.plannedAmount })
                applyGoalPlan(startDay: rule.startDay, incomes: incomeSources, input: input,
                              prefs: GoalSetup.defaultPreferences(input: input, currentRate: analysis().savingsRate))
            }
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
