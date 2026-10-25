import SwiftUI
import BudgetCore

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var editingSource: IncomeSource?
    @State private var editingBudget: Budget?
    @State private var revising = false

    var body: some View {
        NavigationStack {
            Screen(banner: true) {
                ScreenTitle(label: "Plan", title: String(localized: "Your plan"),
                            subtitle: String(localized: "Planned income minus every budget is the number to move on payday."))
                targetCard
                paydayCard
                SectionLabel(text: "Income").padding(.top, 8)
                incomeCard
                TextAction(title: "Add income", systemImage: "plus") {
                    editingSource = IncomeSource(id: UUID().uuidString, name: "", plannedAmount: 0, keyword: nil)
                }
                SectionLabel(text: "Budgets").padding(.top, 8)
                budgetsCard
                HStack(spacing: 20) {
                    addBudgetMenu
                    TextAction(title: "Suggest from history", systemImage: "wand.and.stars") { revising = true }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .statusBarInk()
            .sheet(item: $editingSource) { IncomeSourceForm(source: $0) }
            .sheet(item: $editingBudget) { BudgetForm(budget: $0) }
            .sheet(isPresented: $revising) { PlanSetupView(mode: .revise) }
        }
    }

    private var targetCard: some View {
        let s = model.summary
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Move to savings on payday")
                    Text(s.savingsTarget.value.sek).font(Tokens.numberFont(size: 36)).foregroundStyle(s.savingsTarget.value < 0 ? Tokens.over : Tokens.accent)
                }
                ExplanationView(explained: s.savingsTarget)
            }
        }
    }

    private var paydayCard: some View {
        RowCard {
            Row(title: String(localized: "Payday"), caption: PeriodText.range(model.period)) {
                Picker("Payday", selection: Binding(get: { model.settings.startDay }, set: { day in model.updateSettings { $0.startDay = day } })) {
                    ForEach(1...28, id: \.self) { Text(PeriodText.ordinalDay($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Tokens.accent)
            }
        }
    }

    private var incomeCard: some View {
        RowCard {
            if model.incomeSources.isEmpty {
                Row(title: String(localized: "No income yet"), caption: String(localized: "Salary, a partner's share of the rent, CSN.")) { EmptyView() }
            }
            ForEach(model.incomeSources) { source in
                Button { editingSource = source } label: {
                    Row(title: source.name,
                        caption: source.keyword.map { String(localized: "Matches “\($0)”") } ?? String(localized: "Plan only, not matched to transactions")) {
                        Text(source.plannedAmount.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
                        Chevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if source.id != model.incomeSources.last?.id { Hairline() }
            }
        }
    }

    private var budgetsCard: some View {
        RowCard {
            if model.budgets.isEmpty {
                Row(title: String(localized: "No budgets yet"), caption: String(localized: "Add one per category, or let history suggest them.")) { EmptyView() }
            }
            ForEach(sortedBudgets, id: \.categoryID) { budget in
                Button { editingBudget = budget } label: {
                    Row(title: CategoryInfo.name(budget.categoryID), caption: cadenceText(budget), symbol: CategoryInfo.symbol(budget.categoryID)) {
                        Text(budget.amount.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
                        Chevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if budget.categoryID != sortedBudgets.last?.categoryID { Hairline() }
            }
        }
    }

    private var sortedBudgets: [Budget] {
        model.budgets.sorted { ($0.amount, $1.categoryID) > ($1.amount, $0.categoryID) }
    }

    private func cadenceText(_ budget: Budget) -> String? {
        if case .quarterly(let month) = budget.cadence {
            return String(localized: "Per quarter, due \(Calendar.current.shortStandaloneMonthSymbols[month - 1]). A third is set aside each period.")
        }
        return nil
    }

    private var addBudgetMenu: some View {
        Menu {
            ForEach(availableCategories, id: \.self) { id in
                Button { editingBudget = Budget(categoryID: id, amount: 0, cadence: .monthly) } label: {
                    Label(CategoryInfo.name(id), systemImage: CategoryInfo.symbol(id))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add budget")
            }
            .appFont(size: 15, weight: .semibold)
            .foregroundStyle(availableCategories.isEmpty ? Tokens.dim : Tokens.accent)
            .frame(minHeight: Tokens.minimumTapTarget)
        }
        .disabled(availableCategories.isEmpty)
    }

    private var availableCategories: [String] {
        CategoryInfo.spending.filter { id in !model.budgets.contains { $0.categoryID == id } }
    }
}

struct IncomeSourceForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var source: IncomeSource
    @State private var keyword: String
    private let isNew: Bool

    init(source: IncomeSource) {
        _source = State(initialValue: source)
        _keyword = State(initialValue: source.keyword ?? "")
        isNew = source.name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Screen {
                RowCard {
                    Row(title: String(localized: "Name")) { PillTextField(placeholder: "Salary", text: $source.name).frame(width: 170) }
                    Hairline()
                    Row(title: String(localized: "Amount per period")) { AmountField(value: $source.plannedAmount) }
                    Hairline()
                    Row(title: String(localized: "Keyword"), caption: String(localized: "Deposits whose text contains it count as this income. Leave empty for income that never reaches this account.")) {
                        PillTextField(placeholder: "lön", text: $keyword).frame(width: 130).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                if !isNew {
                    TextAction(title: "Remove this income", systemImage: "trash", tint: Tokens.over) {
                        model.deleteIncomeSource(id: source.id)
                        dismiss()
                    }
                }
            }
            .keyboardDone()
            .navigationTitle(isNew ? String(localized: "New income") : source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
                        source.keyword = trimmed.isEmpty ? nil : trimmed
                        source.name = source.name.trimmingCharacters(in: .whitespaces)
                        model.saveIncomeSource(source)
                        dismiss()
                    }
                    .disabled(source.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(Tokens.accent)
    }
}

struct BudgetForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var budget: Budget
    @State private var quarterly: Bool
    @State private var firstDueMonth: Int
    private let isNew: Bool

    init(budget: Budget) {
        _budget = State(initialValue: budget)
        if case .quarterly(let month) = budget.cadence {
            _quarterly = State(initialValue: true)
            _firstDueMonth = State(initialValue: month)
        } else {
            _quarterly = State(initialValue: false)
            _firstDueMonth = State(initialValue: 1)
        }
        isNew = budget.amount == 0
    }

    var body: some View {
        NavigationStack {
            Screen {
                RowCard {
                    Row(title: quarterly ? String(localized: "Amount per quarter") : String(localized: "Amount per period"), symbol: CategoryInfo.symbol(budget.categoryID)) {
                        AmountField(value: $budget.amount)
                    }
                    Hairline()
                    Row(title: String(localized: "Paid quarterly"), caption: String(localized: "A third of the quarterly total is set aside each period.")) {
                        Toggle("", isOn: $quarterly).labelsHidden().tint(Tokens.accent)
                    }
                    if quarterly {
                        Hairline()
                        Row(title: String(localized: "First month it is due")) {
                            Picker("", selection: $firstDueMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(Calendar.current.standaloneMonthSymbols[month - 1].capitalized(with: .current)).tag(month)
                                }
                            }
                            .pickerStyle(.menu).tint(Tokens.accent)
                        }
                    }
                }
                if !isNew {
                    TextAction(title: "Remove this budget", systemImage: "trash", tint: Tokens.over) {
                        model.deleteBudget(categoryID: budget.categoryID)
                        dismiss()
                    }
                }
            }
            .keyboardDone()
            .navigationTitle(CategoryInfo.name(budget.categoryID))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budget.cadence = quarterly ? .quarterly(firstDueMonth: firstDueMonth) : .monthly
                        model.saveBudget(budget)
                        dismiss()
                    }
                    .disabled(budget.amount <= 0)
                }
            }
        }
        .tint(Tokens.accent)
    }
}
