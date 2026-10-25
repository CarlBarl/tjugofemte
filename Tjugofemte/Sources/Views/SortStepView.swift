import SwiftUI
import BudgetCore

/// Setup step 3: the biggest merchants no rule knows, each filed with one tap. Filing saves a keyword rule, so the rows
/// already on the phone and every later fetch land in that category. The setup owns the bottom bar.
struct SortStepView: View {
    @Environment(AppModel.self) private var model
    /// The merchants as the step opened. A filed merchant leaves `sortCandidates()` but keeps its row here, with Undo;
    /// whether a row is filed is read from the rules, never kept here.
    @State private var merchants: [SortCandidate]?
    @State private var picking: SortCandidate?
    @State private var taps = 0

    private enum RowState { case open, filed(KeywordRule) }

    /// Rent and student loan first: on a real feed the landlord and CSN are among the biggest unknowns.
    private static let chips: [(id: String, label: LocalizedStringKey)] = [
        (DefaultCategory.rent.rawValue, "Rent"), (DefaultCategory.studentLoan.rawValue, "Student loan"),
        (DefaultCategory.savings.rawValue, "Savings"), (DefaultCategory.shopping.rawValue, "Shopping"),
        (DefaultCategory.takeaway.rawValue, "Takeaway"), (DefaultCategory.groceries.rawValue, "Groceries"),
    ]

    /// More offers every category a rule can file into. Transfers are decided at ingest and never re-sorted, so a rule
    /// could not make one and Undo would strand the rows; income and Unsorted are not where money out is sorted to.
    private static let pickable = CategoryInfo.all.filter {
        ![DefaultCategory.transfer, .income, .unsorted].map(\.rawValue).contains($0)
    }

    var body: some View {
        let rows = self.rows
        let filed = rows.filter { if case .filed = $0.state { true } else { false } }.count
        Screen {
            ScreenTitle(label: "Step 3 of 6", title: String(localized: "Sort your biggest unknowns"),
                        subtitle: String(localized: "These merchants matched no category. One tap files each one, now and from now on."))
            progressCard(filed: filed, of: rows.count)
            if !rows.isEmpty {
                RowCard {
                    ForEach(Array(rows.enumerated()), id: \.element.merchant.id) { index, row in
                        if index > 0 { Hairline() }
                        merchantRow(row.merchant, row.state)
                    }
                }
            }
        }
        .onAppear { if merchants == nil { merchants = model.sortCandidates() } }
        .sheet(item: $picking) { merchant in
            CategoryPicker(title: merchant.name, detail: "\(merchant.total.sek) · \(caption(merchant))", categories: Self.pickable) {
                file(merchant, as: $0)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    /// Open while the merchant is still unsorted, filed while a rule has its keyword. A merchant another rule swept up
    /// has nothing left to file and no rule of its own to undo, so it leaves the list.
    private var rows: [(merchant: SortCandidate, state: RowState)] {
        let unsorted = Set(model.sortCandidates().map(\.keyword))
        return (merchants ?? model.sortCandidates()).compactMap { m in
            if let rule = model.rules.first(where: { $0.keyword == m.keyword }) { return (m, .filed(rule)) }
            return unsorted.contains(m.keyword) ? (m, .open) : nil
        }
    }

    private func progressCard(filed: Int, of count: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Spending sorted").appFont(size: 15, weight: .medium).foregroundStyle(Tokens.body)
                    Spacer()
                    // Rounded down, so it never says 100 % while something is still unsorted.
                    Text(model.sortedShare().percentText(rounding: .down)).font(Tokens.numberFont(size: 22)).foregroundStyle(Tokens.accent)
                }
                AmountBar(actual: model.sortedShare(), budget: 1)
                Text(count > 0 ? "\(filed) of \(count) sorted. The rest stays in Unsorted and counts as a want." : "No merchants left to sort.")
                    .appFont(size: 13).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func merchantRow(_ merchant: SortCandidate, _ state: RowState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(merchant.name).appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text).lineLimit(2)
                    Text(caption(merchant)).appFont(size: 13).foregroundStyle(Tokens.dim)
                }
                Spacer(minLength: 8)
                Text(merchant.total.sek).font(Tokens.numberFont(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
            }
            switch state {
            case .open: chipRow(merchant)
            case .filed(let rule): filedBar(rule)
            }
        }
        .padding(.vertical, 14)
    }

    private func chipRow(_ merchant: SortCandidate) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.chips, id: \.id) { chip in
                    Button { file(merchant, as: chip.id) } label: {
                        Text(chip.label).appFont(size: 14, weight: .medium).foregroundStyle(Tokens.body)
                            .padding(.horizontal, 16)
                            .frame(minHeight: Tokens.minimumTapTarget)
                            .background(Tokens.pill, in: Capsule())
                    }
                    .buttonStyle(PressFeedback())
                }
                Button { picking = merchant } label: {
                    Text("More").appFont(size: 14, weight: .medium).foregroundStyle(Tokens.muted)
                        .padding(.horizontal, 16)
                        .frame(minHeight: Tokens.minimumTapTarget)
                        .overlay(Capsule().strokeBorder(Tokens.text.opacity(0.12), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressFeedback())
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        // Edge to edge inside the card, so a chip scrolls out under its border rather than stopping short of it.
        .padding(.horizontal, -16)
    }

    private func filedBar(_ rule: KeywordRule) -> some View {
        HStack(spacing: 8) {
            Text("Filed under \(CategoryInfo.name(rule.categoryID)), rule saved").appFont(size: 14).foregroundStyle(Tokens.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { undo(rule) } label: {
                Text("Undo").appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.accent)
                    .padding(.horizontal, 4)
                    .frame(minHeight: Tokens.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressFeedback())
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(minHeight: Tokens.minimumTapTarget)
        .background(Tokens.ground, in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
    }

    /// "5 times in 11 months": the purchases over the whole history on the phone, which is what the total covers.
    private func caption(_ merchant: SortCandidate) -> String {
        let times = merchant.count == 1 ? String(localized: "Once") : String(localized: "\(merchant.count) times")
        let months = monthsOnPhone == 1 ? String(localized: "1 month") : String(localized: "\(monthsOnPhone) months")
        return String(localized: "\(times) in \(months)")
    }

    /// Whole months from the oldest transaction on the phone to today, at least one.
    private var monthsOnPhone: Int {
        guard let oldest = model.transactions.map(\.bookingDate).min() else { return 1 }
        let span = Calendar.stockholm.dateComponents([.month, .day], from: oldest, to: Date())
        return max(1, (span.month ?? 0) + ((span.day ?? 0) >= 15 ? 1 : 0))
    }

    private func file(_ merchant: SortCandidate, as categoryID: String) {
        withAnimation(.snappy) { model.file(merchant, as: categoryID) }
        taps += 1
    }

    private func undo(_ rule: KeywordRule) {
        withAnimation(.snappy) { model.deleteRule(rule) }
        taps += 1
    }
}
