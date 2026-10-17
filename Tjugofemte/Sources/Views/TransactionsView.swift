import SwiftUI
import BudgetCore

struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Transaction?

    private var grouped: [(Date, [Transaction])] {
        let inPeriod = model.transactions.filter { model.period.contains($0.bookingDate) }
        let byDay = Dictionary(grouping: inPeriod) { Calendar.stockholm.startOfDay(for: $0.bookingDate) }
        return byDay.keys.sorted(by: >).map { ($0, byDay[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                if grouped.isEmpty {
                    ContentUnavailableView("No transactions in this period", systemImage: "tray")
                }
                ForEach(grouped, id: \.0) { day, items in
                    Section(day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                        ForEach(items) { t in
                            Button { editing = t } label: { row(t) }.tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle(PeriodText.title(model.selectedPeriod))
            .refreshable { await model.refresh() }
            .sheet(item: $editing) { CategoryPicker(transaction: $0) }
        }
    }

    private func row(_ t: Transaction) -> some View {
        HStack {
            Image(systemName: CategoryInfo.symbol(t.categoryID)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading) {
                Text(t.counterparty).lineLimit(1)
                Text(CategoryInfo.name(t.categoryID)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(t.amount.sekExact).monospacedDigit().foregroundStyle(t.amount > 0 ? .green : .primary)
        }
    }
}

struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction
    @State private var always = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Always put \(transaction.counterparty) here", isOn: $always)
                } footer: {
                    Text("Creates a keyword rule you can edit under Settings.")
                }
                Section {
                    ForEach(CategoryInfo.all, id: \.self) { id in
                        Button {
                            model.setCategory(transaction, to: id, always: always)
                            dismiss()
                        } label: {
                            HStack {
                                Label(CategoryInfo.name(id), systemImage: CategoryInfo.symbol(id))
                                Spacer()
                                if id == transaction.categoryID { Image(systemName: "checkmark") }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle(transaction.amount.sekExact)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
