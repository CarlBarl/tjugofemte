import SwiftUI
import BudgetCore

/// Payday, income, budgets, summary: four screens, the numbers prefilled from the transactions already on the phone
/// so the user confirms rather than types. First run writes the plan and marks setup done; revise replaces the plan.
struct PlanSetupView: View {
    enum Mode { case firstRun, revise }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var step = 0
    @State private var startDay = 25
    @State private var paydayGuess: Int?
    @State private var incomes: [DraftIncome] = []
    @State private var budgets: [DraftBudget] = []
    @State private var completePeriods = 0
    @State private var showMore = false
    @State private var seededFromData = false

    struct DraftIncome: Identifiable {
        let id: String
        var name: String
        var amount: Decimal
        var keyword: String?
        var included = true
        var periodsSeen = 0
    }

    struct DraftBudget: Identifiable {
        var id: String { categoryID }
        let categoryID: String
        var amount: Decimal
        /// What history says, when it says anything.
        var suggested: Decimal?
        var existing: Budget?
        var isMain: Bool { suggested != nil || existing != nil }
        var isQuarterly: Bool { if case .quarterly = existing?.cadence { return true } else { return false } }
        var perPeriod: Decimal { isQuarterly ? amount / 3 : amount }
    }

    private let stepCount = 4
    private var rule: PeriodRule { model.periodRule(startDay: startDay) }
    private var plannedIncome: Decimal { incomes.filter(\.included).reduce(0) { $0 + $1.amount } }
    /// Per period: a quarterly budget counts a third.
    private var budgetTotal: Decimal { budgets.reduce(0) { $0 + $1.perPeriod } }
    private var target: Decimal { plannedIncome - budgetTotal }
    private var hasData: Bool { !model.transactions.isEmpty }
    private var fetching: Bool { model.isBusy && !hasData }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: paydayStep
                case 1: incomeStep
                case 2: budgetStep
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
            ScreenTitle(label: "Step 1 of 4", title: String(localized: "When is payday?"),
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
                Row(title: String(localized: "This period"), caption: String(localized: "When payday is a weekend or holiday, the period starts on the banking day before.")) {
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

    private var incomeStep: some View {
        Screen {
            ScreenTitle(label: "Step 2 of 4", title: String(localized: "Your income"),
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

    private var budgetStep: some View {
        let main = budgets.indices.filter { budgets[$0].isMain }
        let more = budgets.indices.filter { !budgets[$0].isMain }
        return Screen {
            ScreenTitle(label: "Step 3 of 4", title: String(localized: "Your budgets"), subtitle: budgetBasis)
            if !main.isEmpty {
                RowCard {
                    ForEach(main, id: \.self) { i in
                        BudgetDraftRow(row: $budgets[i])
                        if i != main.last { Hairline() }
                    }
                }
            }
            if !more.isEmpty {
                TextAction(title: showMore ? "Fewer categories" : "More categories", systemImage: showMore ? "chevron.up" : "chevron.down") {
                    withAnimation(.snappy) { showMore.toggle() }
                }
                if showMore || main.isEmpty {
                    RowCard {
                        ForEach(more, id: \.self) { i in
                            BudgetDraftRow(row: $budgets[i])
                            if i != more.last { Hairline() }
                        }
                    }
                }
            }
            Card {
                HStack {
                    Text("Budgets per period").appFont(size: 15, weight: .medium).foregroundStyle(Tokens.body)
                    Spacer()
                    Text(budgetTotal.sek).font(Tokens.numberFont(size: 17)).foregroundStyle(Tokens.text)
                }
            }
        }
    }

    private var budgetBasis: String {
        if completePeriods > 0 {
            return String(localized: "Averages from your last \(completePeriods) complete periods, rounded up to 50 kr. Change what you like. 0 means no budget.")
        }
        return hasData
            ? String(localized: "Based on this period so far, rounded up. Change what you like. 0 means no budget.")
            : String(localized: "An amount per category and period. 0 means no budget.")
    }

    private var summaryStep: some View {
        Screen {
            ScreenTitle(label: "Step 4 of 4", title: String(localized: "Your plan"),
                        subtitle: String(localized: "The savings number is fixed when a period starts. Spend less than a budget and the difference is yours on top."))
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Move to savings on payday")
                        Text(target.sek).font(Tokens.numberFont(size: 44)).foregroundStyle(target < 0 ? Tokens.over : Tokens.accent)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Hairline()
                    summaryLine("Planned income", plannedIncome, kind: .plain)
                    summaryLine("Budgets", -budgetTotal, kind: .plain)
                    summaryLine("Savings target", target, kind: .total)
                }
            }
            if target < 0 {
                Banner(message: "The budgets add up to more than the income. Lower a budget, add income, or start anyway and adjust under Plan.",
                       systemImage: "exclamationmark.triangle", tint: Tokens.over)
            }
            Text(summaryCaption).appFont(size: 14).foregroundStyle(Tokens.dim)
        }
    }

    private var summaryCaption: String {
        let n = budgets.filter { $0.amount > 0 }.count
        let m = incomes.filter { $0.included && $0.amount > 0 }.count
        return String(localized: "Payday \(PeriodText.ordinalDay(startDay).lowercased()) · \(m) income sources · \(n) budgets")
    }

    private enum LineKind { case plain, total }
    private func summaryLine(_ label: LocalizedStringKey, _ amount: Decimal, kind: LineKind) -> some View {
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
                    if step > 0 { TextAction(title: "Back") { withAnimation(.snappy) { step -= 1 } } }
                }
                .frame(width: 110, alignment: .leading)
                Spacer()
                StepDots(count: stepCount, current: step)
                Spacer()
                Group {
                    if mode == .revise { TextAction(title: "Cancel", tint: Tokens.muted) { dismiss() } }
                    else if step == 0 { TextAction(title: "Skip for now", tint: Tokens.muted) { model.skipPlan() } }
                }
                .frame(width: 110, alignment: .trailing)
            }
            BigButton(title: step < stepCount - 1 ? "Next" : (mode == .firstRun ? "Start my budget" : "Save plan")) {
                if step < stepCount - 1 { withAnimation(.snappy) { step += 1 } } else { apply() }
            }
        }
        .padding(.horizontal, Tokens.screenPadding)
        .padding(.vertical, 12)
        .background(Tokens.bg)
    }

    // MARK: Seeding and saving

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

        let suggestion = model.budgetSuggestions(rule: rule)
        completePeriods = suggestion.completePeriods
        budgets = CategoryInfo.spending.map { id in
            let suggested = suggestion.lines.first { $0.categoryID == id }?.amount
            let existing = model.budgets.first { $0.categoryID == id }
            return DraftBudget(categoryID: id, amount: existing?.amount ?? suggested ?? 0, suggested: suggested, existing: existing)
        }
        .sorted { ($0.amount, $1.categoryID) > ($1.amount, $0.categoryID) }
    }

    private func apply() {
        let sources = incomes
            .filter { $0.included && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount > 0 }
            .map { IncomeSource(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces), plannedAmount: $0.amount, keyword: $0.keyword) }
        let plan = budgets
            .filter { $0.amount > 0 }
            .map { Budget(categoryID: $0.categoryID, amount: $0.amount, cadence: $0.existing?.cadence ?? .monthly) }
        model.applyPlan(startDay: startDay, incomes: sources, budgets: plan)
        if mode == .revise { dismiss() }
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

private struct BudgetDraftRow: View {
    @Binding var row: PlanSetupView.DraftBudget

    var body: some View {
        Row(title: CategoryInfo.name(row.categoryID), caption: caption, symbol: CategoryInfo.symbol(row.categoryID)) {
            AmountField(value: $row.amount)
        }
    }

    private var caption: String? {
        if row.isQuarterly { return String(localized: "Per quarter, a third each period") }
        if let suggested = row.suggested, let existing = row.existing, existing.amount != suggested {
            return String(localized: "History says \(suggested.sek)")
        }
        if let suggested = row.suggested { return String(localized: "Usually \(suggested.sek)") }
        return nil
    }
}
