import SwiftUI
import BudgetCore

struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Transaction?

    private var inPeriod: [Transaction] { model.transactions.filter { model.period.contains($0.bookingDate) } }

    private var grouped: [(Date, [Transaction])] {
        let byDay = Dictionary(grouping: inPeriod) { Calendar.stockholm.startOfDay(for: $0.bookingDate) }
        return byDay.keys.sorted(by: >).map { ($0, byDay[$0]!.sorted { $0.counterparty < $1.counterparty }) }
    }

    private var spent: Decimal { inPeriod.filter { categoryKind($0.categoryID) == .spending }.reduce(0) { $0 - $1.amount } }

    var body: some View {
        NavigationStack {
            Screen(banner: true) {
                PeriodHeader(subtitle: inPeriod.isEmpty ? nil : String(localized: "\(inPeriod.count) transactions · \(spent.sek) spent"))
                if grouped.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No transactions in this period").appFont(size: 16, weight: .semibold).foregroundStyle(Tokens.text)
                            Text(model.isDemo ? "The sample covers the last three periods." : "Pull down to fetch again. New transactions show up once the bank has booked them.")
                                .appFont(size: 14).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(grouped, id: \.0) { day, items in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "\(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                        RowCard {
                            ForEach(items) { t in
                                Button { editing = t } label: { row(t).contentShape(Rectangle()) }.buttonStyle(.plain)
                                if t.id != items.last?.id { Hairline() }
                            }
                        }
                    }
                }
            }
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .statusBarInk()
            .sheet(item: $editing) { CategoryPicker(transaction: $0) }
        }
    }

    private func row(_ t: Transaction) -> some View {
        Row(title: t.counterparty, caption: CategoryInfo.name(t.categoryID), symbol: CategoryInfo.symbol(t.categoryID)) {
            Text(t.amount.sekExact).font(Tokens.numberFont(size: 16, weight: .semibold))
                .foregroundStyle(t.amount > 0 ? Tokens.accent : Tokens.text)
        }
    }
}

struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let title: String
    private let detail: String
    private let categories: [String]
    /// A transaction gets the "Always put it here" toggle. Without one, `onPick` gets the choice: the sort step's
    /// merchants always get a rule.
    private let transaction: Transaction?
    private let onPick: ((String) -> Void)?
    @State private var always = false

    init(transaction: Transaction) {
        title = transaction.counterparty
        detail = "\(transaction.amount.sekExact) · \(transaction.bookingDate.formatted(.dateTime.day().month(.wide)))"
        categories = CategoryInfo.all
        self.transaction = transaction
        onPick = nil
    }

    init(title: String, detail: String, categories: [String], onPick: @escaping (String) -> Void) {
        self.title = title
        self.detail = detail
        self.categories = categories
        transaction = nil
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).appFont(size: 22, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
                    Text(detail).appFont(size: 15).foregroundStyle(Tokens.muted)
                }
                if transaction != nil {
                    RowCard {
                        Row(title: String(localized: "Always put it here"), caption: String(localized: "Creates a keyword rule you can edit under Settings.")) {
                            Toggle("", isOn: $always).labelsHidden().tint(Tokens.accent)
                        }
                    }
                }
                RowCard {
                    ForEach(categories, id: \.self) { id in
                        Button {
                            if let transaction { model.setCategory(transaction, to: id, always: always) } else { onPick?(id) }
                            dismiss()
                        } label: {
                            Row(title: CategoryInfo.name(id), symbol: CategoryInfo.symbol(id)) {
                                if id == transaction?.categoryID { Image(systemName: "checkmark").appFont(size: 15, weight: .semibold).foregroundStyle(Tokens.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if id != categories.last { Hairline() }
                    }
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Tokens.accent)
    }
}
