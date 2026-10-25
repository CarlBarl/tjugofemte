import SwiftUI
import BudgetCore

/// The savings goal and the budgets that follow from it: the goal on a slider, each want with minus, plus and a heart,
/// the needs kept as they are. The setup and the Plan tab each put their own title above it. Every number comes from
/// `GoalPlanner`, and only the slider and "Settle" move the goal.
struct GoalView: View {
    let input: GoalInput
    @Binding var prefs: GoalPreferences
    /// The savings rate over the history, for the "Now" marker. nil without income.
    let currentRate: Decimal?
    /// The plan as saved, shown until the user moves the slider, a heart or a step.
    let savedBudgets: [String: Decimal]?
    /// Called on every move, so a container showing the saved plan knows when the screen has left it.
    let onMove: () -> Void

    @State private var moved = false
    @State private var needsOpen = false
    @State private var taps = 0

    init(input: GoalInput, prefs: Binding<GoalPreferences>, currentRate: Decimal?, savedBudgets: [String: Decimal]? = nil,
         onMove: @escaping () -> Void = {}) {
        self.input = input
        _prefs = prefs
        self.currentRate = currentRate
        self.savedBudgets = savedBudgets
        self.onMove = onMove
    }

    /// What minus and plus move a want by.
    private static let step: Decimal = 100
    /// Sources named in the "comes from" line before "and 2 more".
    private static let namedSources = 3

    var body: some View {
        let plan = GoalPlanner.plan(input, prefs)
        let shown = shownPlan(plan)
        VStack(alignment: .leading, spacing: 16) {
            goalCard(shown, planned: shown.plannedSavings)
            if !input.wants.isEmpty { wantsCard(shown.budgets) }
            // The line explains how the planner shares out a raise, so it shows only while the planner's budgets do.
            if shown == plan, let from = fromText(plan) {
                Text(from).appFont(size: 14).foregroundStyle(Tokens.text).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.ground, in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
            }
            if !input.needs.isEmpty { needsCard }
            Text(usualNote).appFont(size: 13).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    /// The saved plan until the user moves something, then the planner's. While it shows, the savings, the status line
    /// and the gap banner all describe the saved budgets; a saved plan the planner would make the same is the planner's.
    private func shownPlan(_ plan: GoalPlan) -> GoalPlan {
        guard let savedBudgets, !moved else { return plan }
        let saved = GoalPlanner.summary(of: savedBudgets, input: input, prefs: prefs)
        return saved.budgets == plan.budgets ? plan : saved
    }

    private var needsTotal: Decimal { input.needs.values.reduce(0, +) }

    // MARK: Goal

    private func goalCard(_ plan: GoalPlan, planned: Decimal) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Savings goal")
                        Text(Self.percent(prefs.goalPercent)).font(Tokens.numberFont(size: 56))
                            .foregroundStyle(plan.outOfReach ? Tokens.over : Tokens.accent)
                            .lineLimit(1).fixedSize()
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(planned.sek).font(Tokens.numberFont(size: 22)).foregroundStyle(planned < 0 ? Tokens.over : Tokens.text)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("to savings each payday").appFont(size: 13).foregroundStyle(Tokens.dim).multilineTextAlignment(.trailing)
                    }
                    .padding(.bottom, 4)
                }
                if input.plannedIncome > 0 {
                    GoalSlider(value: prefs.goalPercent, reachable: plan.reachablePercent, now: nowPercent) { setGoal($0) }
                    if plan.outOfReach {
                        gapBanner(plan)
                    } else if let status = statusText(plan) {
                        Text(status).appFont(size: 14).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("No planned income yet, so there is nothing to save from. Go back and add your income.")
                        .appFont(size: 14).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Rounded down, the way `GoalPlanner.defaultGoal` reads the current rate.
    private var nowPercent: Int? {
        guard var value = currentRate.map({ $0 * 100 }) else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private func gapBanner(_ plan: GoalPlan) -> some View {
        let goal = Self.percent(prefs.goalPercent)
        let reachable = Self.percent(plan.reachablePercent)
        // At the rounding edge the goal can miss by a few kronor while the reachable rate equals it; settling would not move.
        let canSettle = plan.reachableMax >= 0 && plan.reachablePercent < prefs.goalPercent
        let message = if plan.reachableMax < 0 {
            String(localized: "Needs, fixed charges and hearted wants come to \((-plan.reachableMax).sek) more than your income. Lower one of them or add income.")
        } else if canSettle {
            String(localized: "To reach \(goal) you need \(plan.shortfall.sek) more each month. Lower a hearted want, lower a need, or settle at \(reachable).")
        } else {
            String(localized: "To reach \(goal) you need \(plan.shortfall.sek) more each month. Lower a hearted want or lower a need.")
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(message).appFont(size: 14).foregroundStyle(Tokens.text).fixedSize(horizontal: false, vertical: true)
            if canSettle {
                Button { setGoal(plan.reachablePercent) } label: {
                    Text("Settle at \(reachable)").appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.text)
                        .padding(.horizontal, 16)
                        .frame(minHeight: Tokens.minimumTapTarget)
                        .background(Tokens.pill, in: Capsule())
                }
                .buttonStyle(PressFeedback())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.over.opacity(0.12), in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
    }

    private func statusText(_ plan: GoalPlan) -> String? {
        if plan.beyondGoal {
            let saves = (plan.plannedSavings / input.plannedIncome).percentText(rounding: .down)
            return String(localized: "Your usual spending already saves \(saves), so your wants stay at your usual.")
        }
        guard plan.cutPercent > 0 else { return nil }
        return String(localized: "Wants you have not hearted are trimmed by \(Self.percent(plan.cutPercent)) to reach \(Self.percent(prefs.goalPercent)). None is cut by more than half; fixed charges and Unsorted are left alone.")
    }

    private func setGoal(_ percent: Int) {
        guard percent != prefs.goalPercent else { return }
        prefs.goalPercent = percent
        move()
    }

    private func move() {
        moved = true
        onMove()
    }

    // MARK: Wants

    private func wantsCard(_ budgets: [String: Decimal]) -> some View {
        let total = budgets.values.reduce(0, +)
        let usual = input.wants.reduce(Decimal(0)) { $0 + $1.usual }
        return RowCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionLabel(text: "Wants")
                    Spacer(minLength: 8)
                    Text("\(total.sek), usually \(usual.sek)").appFont(size: 13).foregroundStyle(Tokens.dim).multilineTextAlignment(.trailing)
                }
                Text("Heart what matters to you. Hearted wants are never cut, and minus or plus sets them yourself.")
                    .appFont(size: 13).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 10)
            ForEach(input.wants, id: \.categoryID) { want in
                Hairline()
                wantRow(want, budget: budgets[want.categoryID] ?? want.usual)
            }
        }
    }

    private func wantRow(_ want: WantInput, budget: Decimal) -> some View {
        let id = want.categoryID
        let name = CategoryInfo.name(id)
        let hearted = prefs.hearted.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                CategoryGlyph(symbol: CategoryInfo.symbol(id))
                Text(name).appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text).lineLimit(2)
                Spacer(minLength: 8)
                Text(budget.sek).font(Tokens.numberFont(size: 17)).foregroundStyle(Tokens.text).lineLimit(1).fixedSize()
            }
            HStack(spacing: 4) {
                Text(caption(want, budget: budget, hearted: hearted)).appFont(size: 13).foregroundStyle(Tokens.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget, alignment: .leading)
                RoundStepButton(symbol: "minus", label: Text("Lower \(name) by \(Self.step.sek)")) { step(id, by: -Self.step, from: budget) }
                    .disabled(budget <= 0)
                // A fixed want can only go down, for a charge about to be cancelled, and is never hearted.
                if !want.fixed {
                    RoundStepButton(symbol: "plus", label: Text("Raise \(name) by \(Self.step.sek)")) { step(id, by: Self.step, from: budget) }
                    Button { heart(id, !hearted) } label: {
                        Image(systemName: hearted ? "heart.fill" : "heart").appFont(size: 22, weight: .medium)
                            .foregroundStyle(hearted ? Tokens.accent : Tokens.dim)
                            .symbolEffect(.bounce, value: hearted)
                            .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFeedback())
                    .accessibilityLabel(hearted ? Text("Stop protecting \(name)") : Text("Protect \(name) from cuts"))
                }
            }
            .padding(.leading, 48)
        }
        .padding(.vertical, 12)
    }

    /// "Usually 3 600 kr, −1 750 kr": what history says, and how far the budget is from it.
    private func caption(_ want: WantInput, budget: Decimal, hearted: Bool) -> String {
        let usual = want.usual.sek
        let change = Self.signed(budget - want.usual)
        if want.categoryID == DefaultCategory.unsorted.rawValue {
            return budget < want.usual ? String(localized: "Never trimmed, you set \(change)") : String(localized: "Never trimmed, may hold bills")
        }
        if want.fixed {
            return budget < want.usual ? String(localized: "Fixed charges, you set \(change)") : String(localized: "Fixed charges, never trimmed")
        }
        if hearted {
            return budget == want.usual ? String(localized: "Usually \(usual), kept") : String(localized: "Usually \(usual), you set \(change)")
        }
        return budget < want.usual ? String(localized: "Usually \(usual), \(change)") : String(localized: "Usually \(usual)")
    }

    /// "Takeaway & restaurants +500 kr comes from Shopping −350 kr, Entertainment −200 kr." Only while the goal is in reach.
    private func fromText(_ plan: GoalPlan) -> String? {
        guard !plan.outOfReach else { return nil }
        let raised = input.wants.compactMap { w -> String? in
            guard !w.fixed, prefs.hearted.contains(w.categoryID), let amount = prefs.amounts[w.categoryID], amount > w.usual else { return nil }
            return "\(CategoryInfo.name(w.categoryID)) \(Self.signed(amount - w.usual))"
        }
        guard !raised.isEmpty else { return nil }
        let raisedText = ListFormatter.localizedString(byJoining: raised)
        let sources = GoalPlanner.raiseSources(input: input, prefs: prefs)
        if sources.isEmpty {
            return raised.count == 1 ? String(localized: "\(raisedText) comes out of what you save beyond your goal.")
                                     : String(localized: "\(raisedText) come out of what you save beyond your goal.")
        }
        var named = sources.prefix(Self.namedSources).map { "\(CategoryInfo.name($0.categoryID)) \(Self.signed(-$0.amount))" }.joined(separator: ", ")
        if sources.count > Self.namedSources { named = String(localized: "\(named) and \(sources.count - Self.namedSources) more") }
        return raised.count == 1 ? String(localized: "\(raisedText) comes from \(named).") : String(localized: "\(raisedText) come from \(named).")
    }

    /// From the amount on the row, which is the saved one while a saved plan is shown.
    private func step(_ id: String, by delta: Decimal, from shown: Decimal) {
        withAnimation(.snappy) { prefs = GoalPlanner.step(id, by: delta, from: shown, input: input, prefs: prefs) }
        move()
        taps += 1
    }

    private func heart(_ id: String, _ on: Bool) {
        withAnimation(.snappy) { prefs = GoalPlanner.heart(id, on, prefs: prefs) }
        move()
        taps += 1
    }

    // MARK: Needs

    private var needsCard: some View {
        let needs = input.needs.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        return RowCard {
            Button { withAnimation(.snappy) { needsOpen.toggle() } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Needs").appFont(size: 16, weight: .semibold).foregroundStyle(Tokens.text)
                        Text("Kept at your budget, or your usual where you have none. The app never trims these.").appFont(size: 13).foregroundStyle(Tokens.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(needsTotal.sek).font(Tokens.numberFont(size: 17)).foregroundStyle(Tokens.text).lineLimit(1).fixedSize()
                    Image(systemName: "chevron.down").appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.muted)
                        .rotationEffect(.degrees(needsOpen ? 180 : 0))
                }
                .padding(.vertical, 12)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFeedback())
            .accessibilityValue(needsOpen ? Text("Expanded") : Text("Collapsed"))
            if needsOpen {
                ForEach(needs, id: \.key) { id, amount in
                    Hairline()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CategoryInfo.name(id)).appFont(size: 15).foregroundStyle(Tokens.body)
                            Text(needNote(id)).appFont(size: 12).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(amount.sek).font(Tokens.numberFont(size: 15, weight: .semibold)).foregroundStyle(Tokens.text)
                    }
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func needNote(_ id: String) -> String {
        guard let quarter = input.quarterly[id] else { return String(localized: "Monthly") }
        return String(localized: "\(quarter.sek) a quarter, a third each period")
    }

    private var usualNote: String {
        switch input.periods {
        case 0: String(localized: "Usual means what you have spent this period so far.")
        case 1: String(localized: "Usual means what you spent in the last complete period.")
        default: String(localized: "Usual means your average over the last \(input.periods) complete periods.")
        }
    }

    // MARK: Text

    /// A whole percent, "20 %", as the rest of the app writes it.
    static func percent(_ value: Int) -> String { (Decimal(value) / 100).percentText(rounding: .plain) }

    /// "+500 kr" or "−350 kr", with a real minus sign.
    static func signed(_ amount: Decimal) -> String { (amount < 0 ? "\u{2212}" : "+") + abs(amount).sek }
}

/// Minus or plus in a soft circle, with the full 44 pt to tap.
private struct RoundStepButton: View {
    let symbol: String
    let label: Text
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.body)
                .frame(width: 32, height: 32)
                .background(Tokens.pill, in: Circle())
                .frame(width: Tokens.minimumTapTarget, height: Tokens.minimumTapTarget)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressFeedback())
        .accessibilityLabel(label)
    }
}

/// The goal from 0 to 50 %: filled up to the goal, the rest of the reachable range plain, beyond it a faint coral; when
/// the goal is past the reachable rate, the stretch between them is coral. "Now" and "Reachable" are marked under it.
private struct GoalSlider: View {
    let value: Int
    let reachable: Int
    let now: Int?
    let set: (Int) -> Void

    static let maxPercent = 50
    static let thumb: CGFloat = 28

    /// The thumb's centre for a value: it stops half a thumb from each end, and the markers line up with it.
    static func x(_ value: Int, in width: CGFloat) -> CGFloat {
        thumb / 2 + (width - thumb) * CGFloat(min(max(value, 0), maxPercent)) / CGFloat(maxPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Tokens.over.opacity(0.16))
                        Rectangle().fill(value > reachable ? Tokens.over : Tokens.pill).frame(width: Self.x(max(value, reachable), in: width))
                        Rectangle().fill(Tokens.accent).frame(width: Self.x(min(value, reachable), in: width))
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())
                    Circle().fill(Tokens.text)
                        .frame(width: Self.thumb, height: Self.thumb)
                        .shadow(color: Tokens.bg.opacity(0.6), radius: 2, y: 1)
                        .offset(x: Self.x(value, in: width) - Self.thumb / 2)
                }
                .frame(width: width, height: Self.thumb)
                .contentShape(Rectangle())
                // Ahead of the scroll view, so a quick drag along the track moves the goal rather than the page.
                .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let fraction = (drag.location.x - Self.thumb / 2) / max(1, width - Self.thumb)
                    set(min(max(Int((fraction * CGFloat(Self.maxPercent)).rounded()), 0), Self.maxPercent))
                })
            }
            .frame(height: Self.thumb)
            markers
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Savings goal in percent of income"))
        .accessibilityValue(Text(GoalView.percent(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(value + 1, Self.maxPercent))
            case .decrement: set(max(value - 1, 0))
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private var marks: [(value: Int, text: String, tick: Color, label: Color)] {
        var marks: [(value: Int, text: String, tick: Color, label: Color)] = []
        if let now { marks.append((value: now, text: String(localized: "Now \(GoalView.percent(now))"), tick: Tokens.muted, label: Tokens.muted)) }
        marks.append((value: reachable, text: String(localized: "Reachable \(GoalView.percent(reachable))"), tick: Tokens.accent, label: Tokens.body))
        return marks
    }

    private var markers: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ForEach(marks, id: \.text) { mark in
                    Capsule().fill(mark.tick).frame(width: 2, height: 8)
                        .position(x: Self.x(mark.value, in: geo.size.width), y: 4)
                }
            }
            .frame(height: 8)
            MarkerLabels(values: marks.map(\.value)) {
                ForEach(marks, id: \.text) { mark in
                    Text(mark.text).appFont(size: 12).foregroundStyle(mark.label).fixedSize()
                }
            }
        }
    }
}

/// The marker labels, each centred under its tick, kept inside the track; two that would touch move apart evenly.
private struct MarkerLabels: Layout {
    let values: [Int]
    var gap: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        var lefts = zip(values, widths).map { value, w in
            min(max(GoalSlider.x(value, in: bounds.width) - w / 2, 0), max(0, bounds.width - w))
        }
        if lefts.count == 2 {
            let (l, r) = lefts[0] <= lefts[1] ? (0, 1) : (1, 0)
            let overlap = lefts[l] + widths[l] + gap - lefts[r]
            if overlap > 0 {
                lefts[l] -= overlap / 2
                lefts[r] += overlap / 2
                if lefts[l] < 0 { lefts[r] -= lefts[l]; lefts[l] = 0 }
                let past = lefts[r] + widths[r] - bounds.width
                if past > 0 { lefts[l] -= past; lefts[r] -= past }
            }
        }
        for (subview, left) in zip(subviews, lefts) {
            subview.place(at: CGPoint(x: bounds.minX + left, y: bounds.minY), proposal: .unspecified)
        }
    }
}
