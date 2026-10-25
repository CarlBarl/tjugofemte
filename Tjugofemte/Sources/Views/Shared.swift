import SwiftUI
import BudgetCore

extension Decimal {
    var sek: String { formatted(.currency(code: "SEK").precision(.fractionLength(0))) }
    var sekExact: String { formatted(.currency(code: "SEK").precision(.fractionLength(0...2))) }

    /// A share such as 0.56 as a whole percent, "56 %", with a space that does not break.
    func percentText(rounding mode: NSDecimalNumber.RoundingMode) -> String {
        var value = self * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, mode)
        return "\(rounded.formatted())\u{00A0}%"
    }
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
        case .shopping: String(localized: "Shopping")
        case .unsorted: String(localized: "Unsorted")
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
        case .unsorted: "questionmark.circle"
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
    /// Signed amounts; the total is their sum.
    let lines: [(label: String, amount: Decimal)]

    init(explained: Explained) {
        lines = Self.lines(explained)
    }

    /// Lines that are not one of BudgetMath's terms, such as the savings rate's.
    init(lines: [(label: String, amount: Decimal)]) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.label).appFont(size: 15).foregroundStyle(Tokens.body)
                    Spacer()
                    Text(line.amount.sek).font(Tokens.numberFont(size: 15, weight: .medium)).foregroundStyle(Tokens.text)
                }
            }
            Hairline()
            HStack {
                Text("Total").appFont(size: 15, weight: .semibold).foregroundStyle(Tokens.text)
                Spacer()
                Text(lines.reduce(Decimal(0)) { $0 + $1.amount }.sek).font(Tokens.numberFont(size: 17)).foregroundStyle(Tokens.accent)
            }
        }
    }

    nonisolated static func lines(_ explained: Explained) -> [(label: String, amount: Decimal)] {
        explained.terms.map { (label($0.kind), $0.amount) }
    }

    private nonisolated static func label(_ kind: Explained.Kind) -> String {
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

struct DemoBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.isDemo {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Sample data. Nothing here is real.")
                Spacer()
                Button("Exit") { model.stopDemo() }.foregroundStyle(Tokens.accent).fontWeight(.semibold)
            }
            .appFont(size: 13, weight: .medium)
            .foregroundStyle(Tokens.text)
            .padding(.horizontal, Tokens.screenPadding)
            .padding(.vertical, 8)
            .background(Tokens.ground)
        }
    }
}

extension View {
    /// For a stack root that hides the navigation bar: nothing else sits behind the status bar, so scrolled text would land on the clock.
    /// The ink covers the top safe area, which with the bar hidden is the status bar and no more. Sheets with a bar never get it.
    func statusBarInk() -> some View { modifier(StatusBarInk()) }
}

private struct StatusBarInk: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        // With sample data the banner's own ground already covers the status bar; the ink would paint over it.
        content.safeAreaInset(edge: .top, spacing: 0) {
            if !model.isDemo { Color.clear.frame(height: 0).background(Tokens.bg) }
        }
    }
}

/// The period, its dates and the arrows to move between periods. Overview and Transactions share it.
struct PeriodHeader: View {
    @Environment(AppModel.self) private var model
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "\(PeriodText.range(model.period))")
                Text(PeriodText.title(model.selectedPeriod)).appFont(size: 30, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
                if let subtitle { Text(subtitle).appFont(size: 15).foregroundStyle(Tokens.muted) }
            }
            Spacer(minLength: 0)
            if model.isBusy { ProgressView().tint(Tokens.muted).padding(.top, 10) }
            HStack(spacing: 8) {
                arrow("chevron.left") { model.selectedPeriod = model.selectedPeriod.previous }
                arrow("chevron.right") { model.selectedPeriod = model.selectedPeriod.next }
            }
        }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).appFont(size: 14, weight: .semibold).foregroundStyle(Tokens.text)
                .frame(width: 40, height: 40).background(Tokens.card)
                .clipShape(Circle()).overlay(Circle().strokeBorder(Tokens.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension PeriodText {
    /// "12 days left", "Ends today", "Starts in 5 days" or "Ended 22 Oct".
    static func status(_ period: PayPeriod, today: Date = Date()) -> String {
        let cal = Calendar.stockholm
        let day = cal.startOfDay(for: today)
        if day < period.start {
            let n = cal.dateComponents([.day], from: day, to: period.start).day ?? 0
            return String(localized: "Starts in \(n) days")
        }
        if day > period.end { return String(localized: "Ended \(period.end.formatted(.dateTime.day().month(.abbreviated)))") }
        let n = (cal.dateComponents([.day], from: day, to: period.end).day ?? 0) + 1
        return n == 1 ? String(localized: "Last day today") : String(localized: "\(n) days left")
    }

    static func ordinalDay(_ day: Int) -> String {
        if day == 1 { return String(localized: "Calendar months") }
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = .current
        return f.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}
