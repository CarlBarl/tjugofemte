import SwiftUI
import BudgetCore

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var editingSource: IncomeSource?
    @State private var editingBudget: Budget?
    @State private var addingBudget = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Savings target per period")
                        Spacer()
                        Text(model.summary.savingsTarget.value.sek).bold().monospacedDigit()
                    }
                } footer: {
                    Text("Planned income minus every budget below. This is the amount to move on payday.")
                }

                Section {
                    ForEach(model.incomeSources) { source in
                        Button { editingSource = source } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(source.name)
                                    Text(source.keyword.map { String(localized: "Matches “\($0)”") } ?? String(localized: "Plan only, not matched to transactions"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(source.plannedAmount.sek).monospacedDigit()
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in offsets.map { model.incomeSources[$0].id }.forEach(model.deleteIncomeSource) }
                    Button { editingSource = IncomeSource(id: UUID().uuidString, name: "", plannedAmount: 0, keyword: nil) } label: {
                        Label("Add income source", systemImage: "plus")
                    }
                } header: {
                    Text("Planned income")
                } footer: {
                    Text("Salary, a partner's share of the rent, CSN. A keyword lets the app match the real deposit against the plan.")
                }

                Section {
                    ForEach(model.budgets, id: \.categoryID) { budget in
                        Button { editingBudget = budget } label: {
                            HStack {
                                Label(CategoryInfo.name(budget.categoryID), systemImage: CategoryInfo.symbol(budget.categoryID))
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(budget.amount.sek).monospacedDigit()
                                    if case .quarterly = budget.cadence { Text("per quarter").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in offsets.map { model.budgets[$0].categoryID }.forEach { model.deleteBudget(categoryID: $0) } }
                    Button { addingBudget = true } label: { Label("Add budget", systemImage: "plus") }
                        .disabled(availableCategories.isEmpty)
                } header: {
                    Text("Budgets")
                } footer: {
                    Text("Quarterly costs are spread as a third per period.")
                }
            }
            .navigationTitle("Plan")
            .sheet(item: $editingSource) { IncomeSourceForm(source: $0) }
            .sheet(item: $editingBudget) { BudgetForm(budget: $0) }
            .confirmationDialog("Which category?", isPresented: $addingBudget, titleVisibility: .visible) {
                ForEach(availableCategories, id: \.self) { id in
                    Button(CategoryInfo.name(id)) { editingBudget = Budget(categoryID: id, amount: 0, cadence: .monthly) }
                }
            }
        }
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

    init(source: IncomeSource) {
        _source = State(initialValue: source)
        _keyword = State(initialValue: source.keyword ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $source.name)
                TextField("Amount per period", value: $source.plannedAmount, format: .number).keyboardType(.numberPad)
                Section {
                    TextField("Keyword, for example lön", text: $keyword).textInputAutocapitalization(.never)
                } footer: {
                    Text("Deposits whose text contains the keyword count as this income. Leave empty for income that never reaches this account.")
                }
            }
            .navigationTitle(source.name.isEmpty ? String(localized: "New income source") : source.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        source.keyword = keyword.trimmingCharacters(in: .whitespaces).isEmpty ? nil : keyword.trimmingCharacters(in: .whitespaces)
                        model.saveIncomeSource(source)
                        dismiss()
                    }
                    .disabled(source.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct BudgetForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var budget: Budget
    @State private var quarterly: Bool
    @State private var firstDueMonth: Int

    init(budget: Budget) {
        _budget = State(initialValue: budget)
        if case .quarterly(let month) = budget.cadence {
            _quarterly = State(initialValue: true)
            _firstDueMonth = State(initialValue: month)
        } else {
            _quarterly = State(initialValue: false)
            _firstDueMonth = State(initialValue: 1)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", value: $budget.amount, format: .number).keyboardType(.numberPad)
                Toggle("Paid quarterly", isOn: $quarterly)
                if quarterly {
                    Picker("First month it is due", selection: $firstDueMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Calendar.current.standaloneMonthSymbols[month - 1].capitalized(with: .current)).tag(month)
                        }
                    }
                    Text("The amount is the quarterly total. A third is set aside each period.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(CategoryInfo.name(budget.categoryID))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budget.cadence = quarterly ? .quarterly(firstDueMonth: firstDueMonth) : .monthly
                        model.saveBudget(budget)
                        dismiss()
                    }
                }
            }
        }
    }
}
