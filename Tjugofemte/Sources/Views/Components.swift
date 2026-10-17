import SwiftUI
import BudgetCore

extension Decimal {
    var sek: String { formatted(.currency(code: "SEK").precision(.fractionLength(0))) }
    var sekExact: String { formatted(.currency(code: "SEK").precision(.fractionLength(0...2))) }
}

enum CategoryInfo {
    static func name(_ id: String) -> String {
        switch DefaultCategory(rawValue: id) {
        case .rent: String(localized: "Rent")
        case .studentLoan: String(localized: "Student loan (CSN)")
        case .subscriptions: String(localized: "Subscriptions")
        case .streaming: String(localized: "Streaming")
        case .insurance: String(localized: "Insurance")
        case .gym: String(localized: "Gym")
        case .groceries: String(localized: "Groceries")
        case .takeaway: String(localized: "Takeaway & restaurants")
        case .transport: String(localized: "Transport")
        case .entertainment: String(localized: "Entertainment")
        case .health: String(localized: "Health")
        case .shopping: String(localized: "Shopping & other")
        case .savings: String(localized: "Savings")
        case .income: String(localized: "Income & deposits")
        case .transfer: String(localized: "Transfer, own accounts")
        case nil: id
        }
    }

    static func symbol(_ id: String) -> String {
        switch DefaultCategory(rawValue: id) {
        case .rent: "house"
        case .studentLoan: "graduationcap"
        case .subscriptions: "repeat"
        case .streaming: "play.rectangle"
        case .insurance: "shield"
        case .gym: "dumbbell"
        case .groceries: "cart"
        case .takeaway: "fork.knife"
        case .transport: "tram"
        case .entertainment: "ticket"
        case .health: "cross.case"
        case .shopping: "bag"
        case .savings: "banknote"
        case .income: "arrow.down.circle"
        case .transfer: "arrow.left.arrow.right"
        case nil: "tag"
        }
    }

    static let spending = DefaultCategory.allCases.filter { $0.kind == .spending }.map(\.rawValue)
    static let all = DefaultCategory.allCases.map(\.rawValue)
}

enum PeriodText {
    static func title(_ label: PeriodLabel) -> String {
        let date = Calendar.stockholm.date(from: DateComponents(year: label.year, month: label.month, day: 1))!
        return date.formatted(.dateTime.month(.wide).year()).capitalized(with: .current)
    }

    static func range(_ period: PayPeriod) -> String {
        "\(period.start.formatted(.dateTime.day().month(.abbreviated))) – \(period.end.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// "How is this calculated": one line per term and the total.
struct ExplanationView: View {
    let explained: Explained

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(explained.terms.enumerated()), id: \.offset) { _, term in
                HStack {
                    Text(label(term.kind))
                    Spacer()
                    Text(term.amount.sek).monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text("Total").bold()
                Spacer()
                Text(explained.value.sek).bold().monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func label(_ kind: Explained.Kind) -> String {
        switch kind {
        case .plannedIncome: String(localized: "Planned income")
        case .categoryBudgets: String(localized: "Category budgets")
        case .quarterlySetAside: String(localized: "Set aside for quarterly costs")
        case .actualIncome: String(localized: "Income received")
        case .actualSpending: String(localized: "Spent so far")
        case .savingsTarget: String(localized: "Savings target")
        case .incomeShortfall: String(localized: "Income below plan")
        }
    }
}

struct AmountBar: View {
    let actual: Decimal
    let budget: Decimal?

    var body: some View {
        GeometryReader { geo in
            let fraction = budget.map { $0 > 0 ? min(1, Double(truncating: (actual / $0) as NSNumber)) : 1 } ?? 0
            let over = budget.map { actual > $0 } ?? false
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(over ? Color.red : Color.accentColor).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}

struct DemoBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.isDemo {
            HStack {
                Image(systemName: "sparkles")
                Text("Sample data. Nothing here is real.")
                Spacer()
                Button("Exit") { model.stopDemo() }
            }
            .font(.footnote)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.yellow.opacity(0.25))
        }
    }
}
