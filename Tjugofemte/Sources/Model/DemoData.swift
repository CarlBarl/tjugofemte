import Foundation
import BudgetCore

/// Twelve payday periods of Swedish-looking transactions for App Review, screenshots and curious users: ten recurring
/// charges, a quarterly CSN, unsorted merchants for the sort step and takeaway on the rise. Deterministic, so the demo
/// always looks the same.
enum DemoData {
    static let periodCount = 12

    static func transactions(rule: PeriodRule, today: Date = Date()) -> [Transaction] {
        var rng = SeededGenerator(seed: 25)
        var out: [Transaction] = []
        var labels = [rule.period(containing: today).label]
        while labels.count < periodCount { labels.insert(labels[0].previous, at: 0) }
        let categorizer = Categorizer(userRules: rules, ownAccountIDs: [])
        let cal = Calendar.stockholm

        for (index, period) in labels.map(rule.period(labeled:)).enumerated() {
            func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: period.start)! }
            func add(_ offset: Int, _ amount: Decimal, _ text: String) {
                let date = day(offset)
                guard date <= period.end, date <= today else { return }
                let key = "demo-\(period.label.year)-\(period.label.month)-\(out.count)"
                out.append(Transaction(dedupKey: key, bookingDate: date, amount: amount, currency: "SEK", counterparty: text,
                                       categoryID: categorizer.categorize(text: text, amount: amount)))
            }
            add(0, 34_200, "Lön")
            add(0, 5_000, "Swish mottagen Alex")
            add(2, -11_500, "Hyra Bostadsbolaget")
            add(3, -2_000, "Avanza Bank")
            // No travel card in January and July. Six months apart, one gap always falls inside the twelve periods, so the
            // card is never a monthly charge.
            if ![1, 7].contains(period.label.month) { add(7, -890, "SL Access") }
            if period.label.month % 3 == 2 { add(9, -4_950, "CSN") }
            for (offset, amount, text) in charges { add(offset, -amount, text) }
            for (text, offset, visits) in oneOffs {
                if let amount = visits[index] { add(offset, -amount, text) }
            }
            for (count, base, name) in shops {
                for _ in 0..<count {
                    let offset = Int.random(in: 1...28, using: &rng)
                    let percent = Int.random(in: -10...20, using: &rng)
                    add(offset, -Decimal(base * (100 + percent) / 100), name)
                }
            }
            // The last three complete periods and the current one order in more, so Biggest wants shows a rise.
            if index >= periodCount - 4 {
                add(12, -289, "FOODORA AB")
                add(19, -245, "WOLT")
                add(24, -312, "FOODORA AB")
            }
        }
        return out
    }

    /// Everyday spending: visits each period, the usual amount in kronor and the merchant. Each visit falls on a random
    /// day at 10 % under to 20 % over the usual amount.
    static let shops: [(Int, Int, String)] = [
        (6, 320, "ICA SUPERMARKET STHLM"), (4, 280, "COOP KONSUM"), (2, 700, "WILLYS"), (2, 150, "HEMKÖP"),
        (9, 230, "FOODORA AB"), (5, 250, "WOLT"), (8, 65, "ESPRESSO HOUSE"),
        (4, 800, "H&M"), (5, 260, "SYSTEMBOLAGET"), (3, 170, "FILMSTADEN"), (1, 320, "STEAM"),
        (2, 210, "APOTEKET"), (3, 140, "UBR* TRIP"), (2, 75, "PRESSBYRAN 5521"),
    ]

    /// Day in the period, amount and merchant text of each monthly charge.
    static let charges: [(Int, Decimal, String)] = [
        (1, 129, "Spotify"), (4, 149, "Netflix"), (5, 499, "Fitness24Seven"), (6, 600, "Folksam"), (8, 259, "Bonnier News"),
        (10, 147, "HBO Max"), (13, 229, "Storytel"), (15, 139, "Telia"), (17, 99, "Apple"), (20, 29, "Google One"),
    ]

    /// Merchants no rule knows, with the periods they were visited in (0 is the oldest) and the amount, spaced unevenly
    /// so none looks like a recurring charge.
    static let oneOffs: [(String, Int, [Int: Decimal])] = [
        ("KLARNA*ZALANDO", 14, [0: 899, 3: 649, 5: 1_195, 8: 749, 10: 788]),
        ("IKEA KUNGENS KURVA", 22, [2: 2_340, 9: 810]),
        ("SUSHI YAMA", 11, [0: 245, 1: 228, 3: 262, 4: 240, 6: 251, 7: 233, 8: 270, 9: 238, 10: 255, 11: 248]),
        ("BAUHAUS BARKARBY", 9, [1: 689, 6: 455, 7: 576]),
        ("CLAS OHLSON", 16, [4: 349, 5: 199, 9: 412, 11: 280]),
    ]

    /// Rules a user would have saved by now, so Shopping and Subscriptions have something in them.
    static let rules = [
        KeywordRule(keyword: "h&m", categoryID: DefaultCategory.shopping.rawValue),
        KeywordRule(keyword: "bonnier news", categoryID: DefaultCategory.subscriptions.rawValue),
        KeywordRule(keyword: "storytel", categoryID: DefaultCategory.subscriptions.rawValue),
        KeywordRule(keyword: "google one", categoryID: DefaultCategory.subscriptions.rawValue),
    ]

    static let incomeSources = [
        IncomeSource(id: "demo-salary", name: String(localized: "Salary"), plannedAmount: 34_200, keyword: "lön"),
        IncomeSource(id: "demo-partner", name: String(localized: "Partner, rent share"), plannedAmount: 5_000, keyword: "swish mottagen"),
    ]

    /// The student loan, due every third month. `-demo` plans its goal from it, so the Goal screen has a quarterly need.
    static let quarterlyBudgets = [
        Budget(categoryID: DefaultCategory.studentLoan.rawValue, amount: 4_950, cadence: .quarterly(firstDueMonth: 2)),
    ]

    /// The plan an install made before the goal setup, for `-demo-upgrade`.
    static let budgets = quarterlyBudgets + [
        Budget(categoryID: DefaultCategory.rent.rawValue, amount: 11_500, cadence: .monthly),
        Budget(categoryID: DefaultCategory.groceries.rawValue, amount: 4_500, cadence: .monthly),
        Budget(categoryID: DefaultCategory.takeaway.rawValue, amount: 1_500, cadence: .monthly),
        Budget(categoryID: DefaultCategory.streaming.rawValue, amount: 425, cadence: .monthly),
        Budget(categoryID: DefaultCategory.transport.rawValue, amount: 1_200, cadence: .monthly),
        Budget(categoryID: DefaultCategory.gym.rawValue, amount: 499, cadence: .monthly),
        Budget(categoryID: DefaultCategory.insurance.rawValue, amount: 600, cadence: .monthly),
    ]

    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
