import SwiftUI
import BudgetCore

/// Payday, income, sort, your money, goal, summary: six screens, everything drawn from the transactions already on the
/// phone, so the user picks a savings goal rather than types budgets. First run writes the plan and marks setup done;
/// revise replaces the plan.
struct PlanSetupView: View {
    enum Mode { case firstRun, revise }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var step: Int
    @State private var startDay = 25
    @State private var paydayGuess: Int?
    @State private var incomes: [DraftIncome] = []
    /// Seeded the first time the Goal step opens; after that only its slider and "Settle" move the goal.
    @State private var prefs: GoalPreferences?
    @State private var seededFromData = false

    init(mode: Mode, startStep: Int = 0) {
        self.mode = mode
        _step = State(initialValue: startStep)
    }

    struct DraftIncome: Identifiable {
        let id: String
        var name: String
        var amount: Decimal
        var keyword: String?
        var included = true
        var periodsSeen = 0
    }

    /// Steps 2 and 3, where the upgrade card starts: Income when the install has no income yet, else Sort.
    static let incomeStep = 1
    static let sortStep = 2
    private let stepCount = 6
    private let moneyStep = 3
    private let goalStep = 4
    private var rule: PeriodRule { model.periodRule(startDay: startDay, incomes: draftSources) }
    private var plannedIncome: Decimal { incomes.filter(\.included).reduce(0) { $0 + $1.amount } }
    /// The sources as they will be saved; steps 3 to 6 plan with these before they are.
    private var draftSources: [IncomeSource] {
        incomes
            .filter { $0.included && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount > 0 }
            .map { IncomeSource(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces), plannedAmount: $0.amount, keyword: $0.keyword) }
    }
    private var goalInput: GoalInput { model.goalInput(plannedIncome: draftSources.reduce(0) { $0 + $1.plannedAmount }, rule: rule) }
    private var currentRate: Decimal? { model.analysis(rule: rule, incomes: draftSources).savingsRate }
    private var hasData: Bool { !model.transactions.isEmpty }
    private var fetching: Bool { model.isBusy && !hasData }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: paydayStep
                case Self.incomeStep: incomeStepView
                case Self.sortStep: SortStepView()
                case moneyStep: YourMoneyView(rule: rule, incomes: draftSources)
                case goalStep: goalStepView
                default: summaryStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(Tokens.bg)
        .keyboardDone()
        .onAppear { seed() }
        .onChange(of: model.transactions.count) { if !seededFromData && hasData { seed() } }
        .onChange(of: startDay) { if step == 0 { seedNumbers() } }
    }

    // MARK: Steps

    private var paydayStep: some View {
        Screen {
            ScreenTitle(label: "Step 1 of 6", title: String(localized: "When is payday?"),
                        subtitle: String(localized: "Your budget runs from one payday to the next, and the savings number is for that day."))
            if fetching {
                Card {
                    HStack(spacing: 12) {
                        ProgressView().tint(Tokens.accent)
                        Text("Fetching your transactions from the bank. The next screens fill themselves in from them.")
                            .appFont(size: 14).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            RowCard {
                Row(title: String(localized: "Payday"), caption: paydayCaption) {
                    Picker("Payday", selection: $startDay) {
                        ForEach(1...28, id: \.self) { Text(PeriodText.ordinalDay($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Tokens.accent)
                }
                Hairline()
                Row(title: String(localized: "This period"), caption: String(localized: "The period starts the day your salary arrives. Until it has, it starts on the banking day before payday when payday falls on a weekend or holiday.")) {
                    Text(PeriodText.range(rule.period(containing: Date()))).appFont(size: 15, weight: .medium).foregroundStyle(Tokens.text)
                }
            }
        }
    }

    private var paydayCaption: String? {
        guard let paydayGuess else { return nil }
        return paydayGuess == 1
            ? String(localized: "Your salary seems to land at the end of the month.")
            : String(localized: "Your salary seems to land on the \(PeriodText.ordinalDay(paydayGuess)).")
    }

    private var incomeStepView: some View {
        Screen {
            ScreenTitle(label: "Step 2 of 6", title: String(localized: "Your income"),
                        subtitle: incomes.contains { $0.periodsSeen > 0 }
                            ? String(localized: "Found in your transactions. Switch off anything that is not income, and adjust the amounts.")
                            : String(localized: "What comes in each period. Add every source you want to plan with."))
            RowCard {
                ForEach($incomes) { $row in
                    IncomeDraftRow(row: $row)
                    if row.id != incomes.last?.id { Hairline() }
                }
            }
            TextAction(title: "Add income", systemImage: "plus") {
                incomes.append(DraftIncome(id: UUID().uuidString, name: "", amount: 0, keyword: nil))
            }
            Card {
                HStack {
                    Text("Planned income per period").appFont(size: 15, weight: .medium).foregroundStyle(Tokens.body)
                    Spacer()
                    Text(plannedIncome.sek).font(Tokens.numberFont(size: 17)).foregroundStyle(Tokens.text)
                }
            }
        }
    }

    private var goalStepView: some View {
        let input = goalInput
        return Screen {
            ScreenTitle(label: "Step 5 of 6", title: String(localized: "How much do you want to save?"),
                        subtitle: String(localized: "Pick a goal. Your budgets follow from it, trimmed from the wants you care least about."))
            GoalView(input: input, prefs: Binding(get: { prefs ?? seededGoal(input) }, set: { prefs = $0 }), currentRate: currentRate)
        }
    }

    private var summaryStep: some View {
        let input = goalInput
        let goal = prefs ?? seededGoal(input)
        let plan = GoalPlanner.plan(input, goal)
        let target = plan.plannedSavings
        let changes = biggestChanges(input, plan)
        return Screen {
            ScreenTitle(label: "Step 6 of 6", title: String(localized: "Your plan"),
                        subtitle: String(localized: "The savings number is fixed when a period starts. Spend less than a budget and the difference is yours on top."))
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Move to savings on payday")
                        Text(target.sek).font(Tokens.numberFont(size: 44)).foregroundStyle(target < 0 ? Tokens.over : Tokens.accent)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(goalLine(plan, goal)).appFont(size: 14).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                    }
                    Hairline()
                    summaryLine(String(localized: "Planned income"), input.plannedIncome, kind: .plain)
                    summaryLine(String(localized: "Needs, at your budget or usual"), -input.needs.values.reduce(0, +), kind: .plain)
                    summaryLine(wantsLabel(input, plan), -plan.wantsTotal, kind: .plain)
                    summaryLine(String(localized: "Savings target"), target, kind: .total)
                }
            }
            if target < 0 {
                Banner(message: "The budgets add up to more than the income. Lower a budget, add income, or start anyway and adjust under Plan.",
                       systemImage: "exclamationmark.triangle", tint: Tokens.over)
            }
            if !changes.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Biggest changes")
                        ForEach(changes, id: \.id) { change in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(CategoryInfo.name(change.id)).appFont(size: 15).foregroundStyle(Tokens.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text("\(change.usual.formatted(.number.precision(.fractionLength(0)))) to \(change.budget.sek)")
                                    .font(Tokens.numberFont(size: 15, weight: .regular)).foregroundStyle(Tokens.body).lineLimit(1).fixedSize()
                            }
                        }
                    }
                }
            }
            // A budget for every need and every want, as `applyGoalPlan` writes them.
            Text(summaryCaption(budgets: input.needs.count + plan.budgets.count)).appFont(size: 14).foregroundStyle(Tokens.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Your goal is 20 % of income. You saved 8 % before." The current rate rounds down, as on the Goal step.
    private func goalLine(_ plan: GoalPlan, _ goal: GoalPreferences) -> String {
        var line = String(localized: "Your goal is \(GoalView.percent(goal.goalPercent)) of income.")
        if plan.outOfReach { line += " " + String(localized: "This plan saves \(plan.shortfall.sek) less than that each month.") }
        if let currentRate { line += " " + String(localized: "You saved \(currentRate.percentText(rounding: .down)) before.") }
        return line
    }

    private func wantsLabel(_ input: GoalInput, _ plan: GoalPlan) -> String {
        let usual = input.wants.reduce(Decimal(0)) { $0 + $1.usual }
        if plan.wantsTotal < usual { return String(localized: "Wants, trimmed from \(usual.sek)") }
        if plan.wantsTotal > usual { return String(localized: "Wants, usually \(usual.sek)") }
        return String(localized: "Wants, at your usual")
    }

    /// The three wants whose budget moved furthest from their usual, biggest first.
    private func biggestChanges(_ input: GoalInput, _ plan: GoalPlan) -> [(id: String, usual: Decimal, budget: Decimal)] {
        input.wants
            .compactMap { w -> (id: String, usual: Decimal, budget: Decimal)? in
                guard let budget = plan.budgets[w.categoryID], budget != w.usual else { return nil }
                return (w.categoryID, w.usual, budget)
            }
            .sorted { (abs($0.budget - $0.usual), $1.id) > (abs($1.budget - $1.usual), $0.id) }
            .prefix(3)
            .map { $0 }
    }

    private func summaryCaption(budgets n: Int) -> String {
        let payday = startDay == 1 ? String(localized: "Calendar months") : String(localized: "Payday the \(PeriodText.ordinalDay(startDay))")
        let m = draftSources.count
        let sources = m == 1 ? String(localized: "1 income source") : String(localized: "\(m) income sources")
        let budgets = n == 1 ? String(localized: "1 budget") : String(localized: "\(n) budgets")
        return String(localized: "\(payday), \(sources), \(budgets). Change any of it later under Plan.")
    }

    private enum LineKind { case plain, total }
    private func summaryLine(_ label: String, _ amount: Decimal, kind: LineKind) -> some View {
        HStack {
            Text(label).appFont(size: 15, weight: kind == .total ? .semibold : .regular).foregroundStyle(kind == .total ? Tokens.text : Tokens.body)
            Spacer()
            Text(amount.sek).font(Tokens.numberFont(size: kind == .total ? 17 : 15, weight: kind == .total ? .bold : .medium)).foregroundStyle(Tokens.text)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack {
                Group {
                    if step > 0 { TextAction(title: "Back") { go(to: step - 1) } }
                }
                .frame(width: 110, alignment: .leading)
                Spacer()
                StepDots(count: stepCount, current: step)
                Spacer()
                Group {
                    if mode == .revise { TextAction(title: "Cancel", tint: Tokens.muted) { dismiss() } }
                    else if step == 0 { TextAction(title: "Skip for now", tint: Tokens.muted) { model.skipPlan() } }
                    // Sorting is optional: the rest stays in Unsorted.
                    else if step == Self.sortStep { TextAction(title: "Skip", tint: Tokens.muted) { go(to: step + 1) } }
                }
                .frame(width: 110, alignment: .trailing)
            }
            BigButton(title: nextTitle) {
                if step < stepCount - 1 { go(to: step + 1) } else { apply() }
            }
        }
        .padding(.horizontal, Tokens.screenPadding)
        .padding(.vertical, 12)
        .background(Tokens.bg)
    }

    private var nextTitle: LocalizedStringKey {
        switch step {
        case moneyStep: "Set my goal"
        case stepCount - 1: mode == .firstRun ? "Start my budget" : "Save plan"
        default: "Next"
        }
    }

    private func go(to next: Int) {
        if next == goalStep && prefs == nil { prefs = seededGoal(goalInput) }
        withAnimation(.snappy) { step = next }
    }

    // MARK: Seeding and saving

    /// The saved goal when there is one, else 20 % or the current rate, capped at what is reachable.
    private func seededGoal(_ input: GoalInput) -> GoalPreferences {
        model.settings.goal ?? GoalSetup.defaultPreferences(input: input, currentRate: currentRate)
    }

    private func seed() {
        paydayGuess = model.paydayGuess()
        startDay = mode == .firstRun ? (paydayGuess ?? model.settings.startDay) : model.settings.startDay
        seedNumbers()
        seededFromData = hasData
    }

    private func seedNumbers() {
        let suggestedIncome = model.incomeSuggestions(rule: rule)
        var rows: [DraftIncome] = []
        if mode == .revise {
            rows = model.incomeSources.map { DraftIncome(id: $0.id, name: $0.name, amount: $0.plannedAmount, keyword: $0.keyword) }
        }
        // A suggestion already covered by an existing source's keyword ("swish mottagen" covers "swish mottagen alex") is not offered again.
        for s in suggestedIncome where !rows.contains(where: { row in
            guard let k = row.keyword?.lowercased(), !k.isEmpty else { return false }
            return s.key.contains(k) || k.contains(s.keyword)
        }) {
            rows.append(DraftIncome(id: "suggested-\(s.key)", name: s.name, amount: s.amount, keyword: s.keyword, included: mode == .firstRun, periodsSeen: s.periodsSeen))
        }
        if rows.isEmpty { rows = [DraftIncome(id: UUID().uuidString, name: String(localized: "Salary"), amount: 0, keyword: "lön")] }
        incomes = rows
    }

    private func apply() {
        let input = goalInput
        model.applyGoalPlan(startDay: startDay, incomes: draftSources, input: input, prefs: prefs ?? seededGoal(input))
        if mode == .revise { dismiss() }
    }
}

/// "Set a savings goal" for an install set up before the goal setup existed: how much history to keep, when that was
/// never asked, then the setup from step 3, Sort, with payday and income one Back away. An install without income (the
/// old setup skipped at its first step) starts at step 2, Income, since the goal is a share of it. Never forced: the
/// sheet can be closed at any step, and the old budgets keep working until the goal is saved.
struct GoalUpgradeFlow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.retentionAsked {
                PlanSetupView(mode: .revise, startStep: model.incomeSources.isEmpty ? PlanSetupView.incomeStep : PlanSetupView.sortStep)
            } else {
                RetentionPromptView { model.chooseRetention(months: $0) }
            }
        }
        // Room under the grab indicator, which these full screens otherwise start right at.
        .safeAreaPadding(.top, 12)
        .presentationDragIndicator(.visible)
    }
}

private struct IncomeDraftRow: View {
    @Binding var row: PlanSetupView.DraftIncome

    var body: some View {
        HStack(spacing: 12) {
            Button { row.included.toggle() } label: {
                Image(systemName: row.included ? "checkmark.circle.fill" : "circle")
                    .appFont(size: 22).foregroundStyle(row.included ? Tokens.accent : Tokens.dim)
                    .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.included ? Text("Included") : Text("Not included"))
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: $row.name).appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text)
                Text(caption).appFont(size: 13).foregroundStyle(Tokens.dim)
            }
            Spacer(minLength: 4)
            AmountField(value: $row.amount, width: 104)
        }
        .opacity(row.included ? 1 : 0.55)
        .frame(minHeight: 56)
        .padding(.vertical, 6)
    }

    private var caption: String {
        if row.periodsSeen > 0 { return String(localized: "Seen \(row.periodsSeen) times, matches “\(row.keyword ?? "")”") }
        if let keyword = row.keyword { return String(localized: "Matches “\(keyword)”") }
        return String(localized: "Plan only, not matched to transactions")
    }
}
