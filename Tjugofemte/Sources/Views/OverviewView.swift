import SwiftUI
import BudgetCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var showTargetMath = false
    @State private var showLeftOverMath = false

    var body: some View {
        NavigationStack {
            List {
                if model.stage != .ready { setupSection }
                if model.needsReauth { reauthSection }
                periodHeader
                targetSection
                categoriesSection
                if !model.summary.quarterly.isEmpty { quarterlySection }
                if !model.summary.incomes.isEmpty || model.summary.otherIncome != 0 { incomeSection }
            }
            .navigationTitle("Tjugofemte")
            .refreshable { await model.refresh() }
            .toolbar {
                if model.isBusy { ToolbarItem(placement: .topBarTrailing) { ProgressView() } }
            }
        }
    }

    private var setupSection: some View {
        Section {
            NavigationLink { OnboardingView() } label: {
                Label("Connect your bank", systemImage: "building.columns")
            }
            Button { model.startDemo() } label: {
                Label("Try with sample data", systemImage: "sparkles")
            }
        } header: {
            Text("Get started")
        } footer: {
            Text("Your transactions never leave this phone. Connecting takes about ten minutes the first time.")
        }
    }

    private var reauthSection: some View {
        Section {
            NavigationLink { BankPickerView() } label: {
                Label("Bank access has expired. Reconnect", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var periodHeader: some View {
        Section {
            HStack {
                Button { model.selectedPeriod = model.selectedPeriod.previous } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack {
                    Text(PeriodText.title(model.selectedPeriod)).font(.headline)
                    Text(PeriodText.range(model.period)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.selectedPeriod = model.selectedPeriod.next } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
        }
    }

    private var targetSection: some View {
        let s = model.summary
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Move to savings on payday").font(.subheadline).foregroundStyle(.secondary)
                Text(s.savingsTarget.value.sek).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                if let adjusted = s.adjustedSavingsTarget {
                    Text("Income came in below plan. Adjusted: \(adjusted.value.sek)").font(.footnote).foregroundStyle(.orange)
                }
                DisclosureGroup("How is this calculated?", isExpanded: $showTargetMath) {
                    ExplanationView(explained: s.adjustedSavingsTarget ?? s.savingsTarget).padding(.top, 4)
                }
                .font(.footnote)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Left over so far")
                    Spacer()
                    Text(s.leftOverSoFar.value.sek).monospacedDigit().foregroundStyle(s.leftOverSoFar.value < 0 ? .red : .primary)
                }
                DisclosureGroup("How is this calculated?", isExpanded: $showLeftOverMath) {
                    ExplanationView(explained: s.leftOverSoFar).padding(.top, 4)
                }
                .font(.footnote)
            }
        } footer: {
            Text("Income received minus what you have spent, minus the savings target you already moved.")
        }
    }

    private var categoriesSection: some View {
        Section("Budget vs actual") {
            if model.summary.categories.isEmpty {
                Text("No budgets yet. Add them under Plan.").foregroundStyle(.secondary)
            }
            ForEach(model.summary.categories, id: \.categoryID) { line in
                categoryRow(line)
            }
        }
    }

    private func categoryRow(_ line: CategoryLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(CategoryInfo.name(line.categoryID), systemImage: CategoryInfo.symbol(line.categoryID))
                Spacer()
                Text(amountText(line)).monospacedDigit().font(.subheadline)
            }
            AmountBar(actual: line.actual, budget: line.budget)
            if let remaining = line.remaining {
                Text(remainingText(remaining)).font(.caption).foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 2)
    }

    private func amountText(_ line: CategoryLine) -> String {
        if let budget = line.budget { return "\(line.actual.sek) / \(budget.sek)" }
        return line.actual.sek
    }

    private func remainingText(_ remaining: Decimal) -> String {
        remaining >= 0 ? String(localized: "\(remaining.sek) left") : String(localized: "\((-remaining).sek) over")
    }

    private var quarterlySection: some View {
        Section("Quarterly costs") {
            ForEach(model.summary.quarterly, id: \.categoryID) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Label(CategoryInfo.name(line.categoryID), systemImage: CategoryInfo.symbol(line.categoryID))
                    Text("Set aside \(line.setAsideSoFar.sek) of \(line.quarterlyAmount.sek) so far, paid \(line.paidSoFar.sek) this quarter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var incomeSection: some View {
        Section("Income") {
            ForEach(model.summary.incomes, id: \.sourceID) { line in
                HStack {
                    Text(model.incomeSources.first { $0.id == line.sourceID }?.name ?? line.sourceID)
                    Spacer()
                    if let actual = line.actual {
                        Text(actual == 0 ? String(localized: "Not received") : "\(actual.sek) / \(line.planned.sek)")
                            .monospacedDigit().foregroundStyle(actual == 0 ? .secondary : .primary)
                    } else {
                        Text("\(line.planned.sek) planned").foregroundStyle(.secondary)
                    }
                }
            }
            if model.summary.otherIncome != 0 {
                HStack { Text("Other income"); Spacer(); Text(model.summary.otherIncome.sek).monospacedDigit() }
            }
        }
    }
}
