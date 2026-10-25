import SwiftUI
import BudgetCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var explaining: ExplanationSheet.Content?
    @State private var planning = false
    @State private var reconnecting = false
    @State private var adjusting = false
    @State private var upgrading = false
    @State private var taps = 0

    var body: some View {
        NavigationStack {
            Screen(banner: true) {
                PeriodHeader(subtitle: PeriodText.status(model.period))
                if model.needsReauth {
                    Banner(message: "Bank access has expired.", systemImage: "exclamationmark.triangle", tint: Tokens.over,
                           action: ("Reconnect", { reconnecting = true }))
                }
                // The upgrade card leads to the same setup as "Plan my budget", with the history question first, so one is shown.
                if model.hasPlan { heroCard } else if !model.showsGoalCard { planCard }
                if model.showsNudge { nudgeCard }
                if model.showsGoalCard { goalCard }
                soFarCard
                if !model.summary.categories.isEmpty { budgetsCard }
                if !model.summary.quarterly.isEmpty { quarterlyCard }
                if !model.summary.incomes.isEmpty || model.summary.otherIncome != 0 { incomeCard }
            }
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .statusBarInk()
            .navigationDestination(isPresented: $reconnecting) { BankPickerView() }
            .sheet(item: $explaining) { ExplanationSheet(content: $0) }
            .sheet(isPresented: $planning) { PlanSetupView(mode: .revise) }
            .sheet(isPresented: $adjusting) { GoalSheet() }
            .sheet(isPresented: $upgrading) { GoalUpgradeFlow() }
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
        }
    }

    // MARK: Cards

    private var heroCard: some View {
        let s = model.summary
        let shown = s.adjustedSavingsTarget ?? s.savingsTarget
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Move to savings on payday")
                    Text(shown.value.sek).font(Tokens.numberFont(size: 44)).foregroundStyle(shown.value < 0 ? Tokens.over : Tokens.accent)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let goal = model.settings.goal {
                        Text(goalLine(goal)).appFont(size: 14).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if s.adjustedSavingsTarget != nil {
                        Text("Income came in below plan, so the target is lowered from \(s.savingsTarget.value.sek).")
                            .appFont(size: 13).foregroundStyle(Tokens.over).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 12) {
                    StatTile(label: "Planned income", value: term(s.savingsTarget, .plannedIncome).sek)
                    StatTile(label: "Budgets", value: (-term(s.savingsTarget, .categoryBudgets)).sek)
                    if term(s.savingsTarget, .quarterlySetAside) != 0 {
                        StatTile(label: "Set aside", value: (-term(s.savingsTarget, .quarterlySetAside)).sek)
                    }
                }
                TextAction(title: "How is this calculated?") {
                    explaining = .init(title: "Move to savings on payday", explained: shown,
                                       note: "Planned income minus every budget, fixed when the period starts. Move it on payday and the rest of the month takes care of itself.")
                }
                .padding(.top, -6)
            }
        }
    }

    /// "Goal 20 %, last period 13 %"; the goal alone until a whole period with income is on the phone.
    private func goalLine(_ goal: GoalPreferences) -> String {
        let percent = GoalView.percent(goal.goalPercent)
        guard let last = model.lastPeriodPercent else { return String(localized: "Goal \(percent)") }
        return String(localized: "Goal \(percent), last period \(GoalView.percent(last))")
    }

    /// "Adjust plan?": the last complete period ran more than 5 % of planned income past the plan.
    private var nudgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                Text(nudgeText).appFont(size: 14).foregroundStyle(Tokens.text).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Spacer(minLength: 0)
                Button {
                    taps += 1
                    withAnimation(.snappy) { model.dismissNudge() }
                } label: {
                    Image(systemName: "xmark").appFont(size: 13, weight: .semibold).foregroundStyle(Tokens.muted)
                        .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedback())
                .padding(.trailing, -10)
                .accessibilityLabel(Text("Not now"))
            }
            Button {
                taps += 1
                adjusting = true
            } label: {
                Text("Adjust plan").appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.onAccent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: Tokens.minimumTapTarget)
                    .background(Tokens.accent, in: Capsule())
            }
            .buttonStyle(PressFeedback())
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.ground, in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
    }

    /// "Last period you saved 13 %, 7 points under your goal. Takeaway went 1 210 kr over." Each half only when it holds.
    private var nudgeText: String {
        var parts: [String] = []
        if let last = model.lastPeriodPercent {
            let saved = GoalView.percent(last)
            let under = (model.settings.goal?.goalPercent ?? 0) - last
            parts.append(under > 1 ? String(localized: "Last period you saved \(saved), \(under)\u{00A0}points under your goal.")
                         : under == 1 ? String(localized: "Last period you saved \(saved), 1\u{00A0}point under your goal.")
                         : String(localized: "Last period you saved \(saved)."))
        }
        if let over = model.lastPeriodOverrun, let remaining = over.remaining {
            parts.append(String(localized: "\(CategoryInfo.name(over.categoryID)) went \((-remaining).sek) over."))
        }
        return parts.isEmpty ? String(localized: "Last period you spent more than planned.") : parts.joined(separator: " ")
    }

    /// For an install from before the goal setup. Never forced; until it is done the old budgets keep working.
    private var goalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Savings goal")
                (model.hasPlan
                    ? Text("Pick how much of your income to save, and the app suggests budgets from your history. Until then your budgets work as before. Spending the app could not sort sits in Unsorted, which has no budget yet.")
                    : Text("Pick how much of your income to save, and the app suggests budgets from your history."))
                    .appFont(size: 15).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                BigButton(title: "Set a savings goal") {
                    taps += 1
                    upgrading = true
                }
            }
        }
    }

    private var planCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "No plan yet")
                Text("Set your income and budgets and this card becomes one number: what to move to savings on payday.")
                    .appFont(size: 15).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                BigButton(title: "Plan my budget") { planning = true }
            }
        }
    }

    private var soFarCard: some View {
        let s = model.summary
        let received = term(s.leftOverSoFar, .actualIncome)
        let spent = -term(s.leftOverSoFar, .actualSpending)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "So far this period")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(s.leftOverSoFar.value.sek).font(Tokens.numberFont(size: 28)).foregroundStyle(s.leftOverSoFar.value < 0 ? Tokens.over : Tokens.text)
                        Text("left over").appFont(size: 15).foregroundStyle(Tokens.muted)
                    }
                }
                HStack(spacing: 12) {
                    StatTile(label: "Received", value: received.sek)
                    StatTile(label: "Spent", value: spent.sek)
                    StatTile(label: "Savings target", value: term(s.leftOverSoFar, .savingsTarget) == 0 ? "–" : (-term(s.leftOverSoFar, .savingsTarget)).sek)
                }
                TextAction(title: "How is this calculated?") {
                    explaining = .init(title: "Left over so far", explained: s.leftOverSoFar,
                                       note: "Income received minus what you have spent, minus the savings target you move on payday. Negative means the month is running ahead of the plan.")
                }
                .padding(.top, -6)
            }
        }
    }

    private var budgetsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Budgets")
                ForEach(sortedCategories, id: \.categoryID) { line in
                    categoryRow(line)
                    if line.categoryID != sortedCategories.last?.categoryID { Hairline() }
                }
            }
        }
    }

    private var sortedCategories: [CategoryLine] {
        model.summary.categories.sorted {
            switch ($0.budget, $1.budget) {
            case let (a?, b?): a != b ? a > b : $0.categoryID < $1.categoryID
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): $0.actual != $1.actual ? $0.actual > $1.actual : $0.categoryID < $1.categoryID
            }
        }
    }

    private func categoryRow(_ line: CategoryLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CategoryGlyph(symbol: CategoryInfo.symbol(line.categoryID), tint: (line.remaining ?? 0) < 0 ? Tokens.over : Tokens.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CategoryInfo.name(line.categoryID)).appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text)
                    Text(remainingText(line)).appFont(size: 13).foregroundStyle((line.remaining ?? 0) < 0 ? Tokens.over : Tokens.dim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(line.actual.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
                    if let budget = line.budget { Text("of \(budget.sek)").appFont(size: 12).foregroundStyle(Tokens.dim) }
                }
            }
            AmountBar(actual: line.actual, budget: line.budget)
        }
    }

    private func remainingText(_ line: CategoryLine) -> String {
        guard let remaining = line.remaining else { return String(localized: "No budget") }
        return remaining >= 0 ? String(localized: "\(remaining.sek) left") : String(localized: "\((-remaining).sek) over")
    }

    private var quarterlyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Quarterly costs")
                ForEach(model.summary.quarterly, id: \.categoryID) { line in
                    Row(title: CategoryInfo.name(line.categoryID),
                        caption: String(localized: "Set aside \(line.setAsideSoFar.sek) of \(line.quarterlyAmount.sek) so far, paid \(line.paidSoFar.sek) this quarter."),
                        symbol: CategoryInfo.symbol(line.categoryID)) {
                        Text(line.setAsidePerPeriod.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
                    }
                }
            }
        }
    }

    private var incomeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Income")
                ForEach(model.summary.incomes, id: \.sourceID) { line in
                    HStack {
                        Text(model.incomeSources.first { $0.id == line.sourceID }?.name ?? line.sourceID).appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text)
                        Spacer()
                        incomeValue(line)
                    }
                }
                if model.summary.otherIncome != 0 {
                    HStack {
                        Text("Other income").appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text)
                        Spacer()
                        Text(model.summary.otherIncome.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder private func incomeValue(_ line: IncomeLine) -> some View {
        if let actual = line.actual {
            if actual == 0 {
                Text("Not yet · \(line.planned.sek) planned").appFont(size: 14).foregroundStyle(Tokens.muted)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(actual.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.accent)
                    Text("of \(line.planned.sek)").appFont(size: 12).foregroundStyle(Tokens.dim)
                }
            }
        } else {
            Text("\(line.planned.sek) planned").appFont(size: 14).foregroundStyle(Tokens.muted)
        }
    }

    private func term(_ explained: Explained, _ kind: Explained.Kind) -> Decimal {
        explained.terms.first { $0.kind == kind }?.amount ?? 0
    }
}

/// "How is this calculated": the terms, the total, one sentence of why.
struct ExplanationSheet: View {
    struct Content: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let lines: [(label: String, amount: Decimal)]
        let note: LocalizedStringKey

        init(title: LocalizedStringKey, explained: Explained, note: LocalizedStringKey) {
            self.init(title: title, lines: ExplanationView.lines(explained), note: note)
        }

        init(title: LocalizedStringKey, lines: [(label: String, amount: Decimal)], note: LocalizedStringKey) {
            self.title = title
            self.lines = lines
            self.note = note
        }
    }

    @Environment(\.dismiss) private var dismiss
    let content: Content

    var body: some View {
        NavigationStack {
            Screen {
                Text(content.title).appFont(size: 26, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
                Card { ExplanationView(lines: content.lines) }
                Text(content.note).appFont(size: 15).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Tokens.accent)
        .presentationDetents([.medium, .large])
    }
}
