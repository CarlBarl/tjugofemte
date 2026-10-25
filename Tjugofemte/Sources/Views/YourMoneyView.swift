import SwiftUI
import BudgetCore

/// Setup step 4: the money on the phone in four cards, with nothing to fill in. Only the need chips change anything,
/// and they write the user's groups. The setup owns the bottom bar.
struct YourMoneyView: View {
    @Environment(AppModel.self) private var model
    @State private var explaining: ExplanationSheet.Content?
    @State private var showsAllCharges = false
    @State private var flips = 0

    /// Recurring charges listed until "Show all".
    private static let shortList = 5
    /// Every spending category but Unsorted, which is always a want.
    private static let flippable = CategoryInfo.spending.filter { $0 != DefaultCategory.unsorted.rawValue }

    var body: some View {
        let analysis = model.analysis()
        Screen {
            ScreenTitle(label: "Step 4 of 6", title: String(localized: "Your money"), subtitle: subtitle(analysis.periods))
            rateCard(analysis)
            splitCard(analysis)
            recurringCard(model.recurringCharges())
            if !analysis.topWants.isEmpty { wantsCard(analysis) }
        }
        .sheet(item: $explaining) { ExplanationSheet(content: $0).presentationDragIndicator(.visible) }
        .sensoryFeedback(.impact(weight: .light), trigger: flips)
    }

    private func subtitle(_ periods: Int) -> String {
        switch periods {
        case 0: String(localized: "This period so far, in four numbers. Nothing to fill in here.")
        case 1: String(localized: "One month of your transactions, in four numbers. Nothing to fill in here.")
        default: String(localized: "\(periods) months of your transactions, in four numbers. Nothing to fill in here.")
        }
    }

    // MARK: Savings rate

    private func rateCard(_ a: SpendingAnalysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Savings rate")
                if let rate = a.savingsRate {
                    HStack(alignment: .center, spacing: 12) {
                        // Rounded down, as the Goal screen marks the current rate.
                        Text(rate.percentText(rounding: .down)).font(Tokens.numberFont(size: 56))
                            .foregroundStyle(rate < 0 ? Tokens.over : Tokens.accent)
                            .lineLimit(1).fixedSize()
                        Text(savedLine(a)).appFont(size: 15).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("50/30/20 suggests saving \((Decimal(20) / 100).percentText(rounding: .plain)), which for you is \((a.incomePerPeriod * 20 / 100).sek) a month.")
                        .appFont(size: 14).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
                    TextAction(title: "How is this calculated?") { explaining = explanation(a) }
                } else {
                    Text("No income on the phone yet, so there is no rate to show.")
                        .appFont(size: 15).foregroundStyle(Tokens.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func savedLine(_ a: SpendingAnalysis) -> String {
        switch a.periods {
        case 0: String(localized: "\(a.savedPerPeriod.sek) so far this period.")
        case 1: String(localized: "\(a.savedPerPeriod.sek) over the last month.")
        default: String(localized: "\(a.savedPerPeriod.sek) a month on average, over the last \(a.periods) months.")
        }
    }

    /// Income split in two, so a month of Swish paybacks shows as its own line rather than hiding in the rate.
    private func explanation(_ a: SpendingAnalysis) -> ExplanationSheet.Content {
        .init(title: "Savings rate",
              lines: [(String(localized: "Income from your sources"), a.incomePerPeriod - a.otherIncomePerPeriod),
                      (String(localized: "Other income"), a.otherIncomePerPeriod),
                      (String(localized: "Needs"), -a.needsPerPeriod),
                      (String(localized: "Wants"), -a.wantsPerPeriod)],
              note: "The savings rate is the total, what is left of the income after needs and wants, as a share of all income. Other income is money in that no income source matches, such as Swish from friends paying you back. Money moved to savings or between your own accounts counts as neither.")
    }

    // MARK: Split

    private func splitCard(_ a: SpendingAnalysis) -> some View {
        let income = a.incomePerPeriod
        let saved = a.savedPerPeriod
        // Savings rounds down like the rate above, so the two always agree.
        func share(_ amount: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> String? {
            income > 0 ? (amount / income).percentText(rounding: mode) : nil
        }
        let legend: [(text: String, color: Color)] = [
            (share(a.needsPerPeriod, .plain).map { String(localized: "Needs \($0)") } ?? String(localized: "Needs"), Tokens.groupNeed),
            (share(a.wantsPerPeriod, .plain).map { String(localized: "Wants \($0)") } ?? String(localized: "Wants"), Tokens.groupWant),
            (share(saved, .down).map { String(localized: "Savings \($0)") } ?? String(localized: "Savings"), Tokens.groupSaving),
        ]
        let benchmark = [String(localized: "Needs \((Decimal(50) / 100).percentText(rounding: .plain))"),
                         String(localized: "Wants \((Decimal(30) / 100).percentText(rounding: .plain))"),
                         String(localized: "Savings \((Decimal(20) / 100).percentText(rounding: .plain))")]
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Where it goes")
                FlowLayout(spacing: 16, lineSpacing: 8) {
                    ForEach(legend, id: \.text) { item in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(item.color).frame(width: 10, height: 10)
                            Text(item.text).appFont(size: 14, weight: .medium).foregroundStyle(Tokens.text)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("You").appFont(size: 13).foregroundStyle(Tokens.muted)
                    SplitBar(parts: [(a.needsPerPeriod, Tokens.groupNeed), (a.wantsPerPeriod, Tokens.groupWant), (saved, Tokens.groupSaving)])
                        .accessibilityLabel(legend.map(\.text).joined(separator: ", "))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "50/30/20").appFont(size: 13).foregroundStyle(Tokens.muted)
                    SplitBar(parts: [(50, Tokens.groupNeed), (30, Tokens.groupWant), (20, Tokens.groupSaving)])
                        .opacity(0.55)
                        .accessibilityLabel(benchmark.joined(separator: ", "))
                }
                Hairline()
                VStack(alignment: .leading, spacing: 4) {
                    Text("What counts as a need?").appFont(size: 15, weight: .semibold).foregroundStyle(Tokens.text)
                    Text("Tap a category to move it. Unsorted always counts as a want.").appFont(size: 13).foregroundStyle(Tokens.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Self.flippable, id: \.self) { needChip($0) }
                }
            }
        }
    }

    private func needChip(_ id: String) -> some View {
        let isNeed = model.settings.groups.group(of: id) == .need
        let tint = isNeed ? Tokens.groupNeed : Tokens.groupWant
        return Button {
            withAnimation(.snappy) { model.updateSettings { $0.groups.overrides[id] = isNeed ? .want : .need } }
            flips += 1
        } label: {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(CategoryInfo.name(id)).appFont(size: 14, weight: .medium).foregroundStyle(Tokens.text)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: Tokens.minimumTapTarget)
            .background(tint.opacity(0.16), in: Capsule())
        }
        .buttonStyle(PressFeedback())
        .accessibilityValue(isNeed ? Text("Counts as a need") : Text("Counts as a want"))
    }

    // MARK: Recurring charges

    private func recurringCard(_ charges: [RecurringCharge]) -> some View {
        let total = charges.reduce(Decimal(0)) { $0 + $1.perPeriod }
        let shown = showsAllCharges ? charges : Array(charges.prefix(Self.shortList))
        let headline = switch charges.count {
        case 0: String(localized: "None found yet")
        case 1: String(localized: "1 charge, \(total.sek) a month")
        default: String(localized: "\(charges.count) charges, \(total.sek) a month")
        }
        return RowCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Recurring charges")
                Text(headline).font(Tokens.numberFont(size: 22)).foregroundStyle(Tokens.text).fixedSize(horizontal: false, vertical: true)
                Text("Same merchant, about the same amount, every month or quarter. Rent and CSN are left out.")
                    .appFont(size: 13).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 8)
            ForEach(shown) { charge in
                Hairline()
                Row(title: charge.name, caption: charge.cadence == .monthly ? String(localized: "Monthly") : String(localized: "Quarterly")) {
                    Text(charge.amount.sek).font(Tokens.numberFont(size: 15, weight: .semibold)).foregroundStyle(Tokens.text)
                }
            }
            if charges.count > Self.shortList {
                Hairline()
                Button { withAnimation(.snappy) { showsAllCharges.toggle() } } label: {
                    Text(showsAllCharges ? "Show fewer" : "Show all \(charges.count)").appFont(size: 15, weight: .semibold).foregroundStyle(Tokens.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedback())
            }
        }
    }

    // MARK: Biggest wants

    /// Each want at its usual, the figure the Goal screen shows next to it, rather than the analysis's unrounded mean.
    private func wantsCard(_ a: SpendingAnalysis) -> some View {
        let input = model.goalInput(plannedIncome: model.incomeSources.reduce(0) { $0 + $1.plannedAmount })
        return RowCard {
            SectionLabel(text: "Biggest wants")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 8)
            ForEach(a.topWants, id: \.categoryID) { want in
                // Usual leaves out categories under 50 kr a period; such a want is rounded the same way here.
                let usual = input.wants.first { $0.categoryID == want.categoryID }?.usual ?? PlanSuggestions.roundUp(want.perPeriod, to: 50)
                Hairline()
                Row(title: CategoryInfo.name(want.categoryID), caption: trend(want.changePercent), symbol: CategoryInfo.symbol(want.categoryID)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(usual.sek).font(Tokens.numberFont(size: 15, weight: .semibold)).foregroundStyle(Tokens.text)
                        Text("a month").appFont(size: 12).foregroundStyle(Tokens.dim)
                    }
                }
            }
        }
    }

    /// Only with enough history to compare: the last three periods against the ones before.
    private func trend(_ change: Int?) -> String? {
        guard let change else { return nil }
        if abs(change) < 5 { return String(localized: "About the same lately") }
        let text = (Decimal(abs(change)) / 100).percentText(rounding: .plain)
        return change > 0 ? String(localized: "Up \(text) the last 3 months") : String(localized: "Down \(text) the last 3 months")
    }
}

/// One bar split into its parts, 2 pt apart, each as wide as its share of the whole. Parts at or below zero are left out.
private struct SplitBar: View {
    let parts: [(amount: Decimal, color: Color)]

    var body: some View {
        GeometryReader { geo in
            let shown = parts.filter { $0.amount > 0 }
            let total = shown.reduce(Decimal(0)) { $0 + $1.amount }
            let room = max(0, geo.size.width - CGFloat(max(0, shown.count - 1)) * 2)
            HStack(spacing: 2) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(part.color)
                        .frame(width: room * CGFloat(Double(truncating: (part.amount / total) as NSNumber)))
                }
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
    }
}

/// Left to right, onto a new line when the next one does not fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = place(subviews, in: width)
        let height = frames.map(\.maxY).max() ?? 0
        let used = frames.map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(subviews, in: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func place(_ subviews: Subviews, in width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
