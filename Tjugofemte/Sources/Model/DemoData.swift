import Foundation
import BudgetCore

/// Three payday periods of Swedish-looking transactions for App Review, screenshots and curious users.
/// Deterministic, so the demo always looks the same.
enum DemoData {
    static func transactions(rule: PeriodRule, today: Date = Date()) -> [Transaction] {
        var rng = SeededGenerator(seed: 25)
        var out: [Transaction] = []
        let current = rule.period(containing: today)
        let periods = [current.label.previous.previous, current.label.previous, current.label].map(rule.period(labeled:))
        let cal = Calendar.stockholm

        for period in periods {
            func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: period.start)! }
            func add(_ offset: Int, _ amount: Decimal, _ text: String) {
                let date = day(offset)
                guard date <= period.end, date <= today else { return }
                let key = "demo-\(period.label.year)-\(period.label.month)-\(out.count)"
                out.append(Transaction(dedupKey: key, bookingDate: date, amount: amount, currency: "SEK", counterparty: text,
                                       categoryID: Categorizer(userRules: [], ownAccountIDs: []).categorize(text: text, amount: amount)))
            }
            add(0, 34_200, "Lön")
            add(0, 5_000, "Swish mottagen Alex")
            add(2, -11_500, "Hyra Bostadsbolaget")
            add(3, -2_000, "Avanza Bank")
            add(1, -169, "Spotify")
            add(4, -139, "Netflix")
            add(5, -449, "SATS")
            add(6, -312, "Folksam")
            add(7, -890, "SL Access")
            if period.label.month % 3 == 2 { add(9, -3_000, "CSN") }
            let merchants: [(Decimal, String)] = [
                (187, "ICA SUPERMARKET STHLM"), (242, "COOP KONSUM"), (96, "HEMKÖP"), (321, "WILLYS"),
                (159, "FOODORA AB"), (212, "WOLT"), (85, "ESPRESSO HOUSE"), (64, "PRESSBYRÅN"),
                (129, "APOTEKET"), (199, "SYSTEMBOLAGET"), (349, "H&M"), (90, "UBR* TRIP"),
            ]
            for offset in stride(from: 1, to: 31, by: 1) {
                for _ in 0..<Int.random(in: 0...2, using: &rng) {
                    let (base, name) = merchants[Int.random(in: 0..<merchants.count, using: &rng)]
                    let jitter = Decimal(Int.random(in: -30...60, using: &rng))
                    add(offset, -(base + jitter), name)
                }
            }
        }
        return out
    }

    static let incomeSources = [
        IncomeSource(id: "demo-salary", name: String(localized: "Salary"), plannedAmount: 34_200, keyword: "lön"),
        IncomeSource(id: "demo-partner", name: String(localized: "Partner, rent share"), plannedAmount: 5_000, keyword: "swish mottagen"),
    ]

    static let budgets = [
        Budget(categoryID: DefaultCategory.rent.rawValue, amount: 11_500, cadence: .monthly),
        Budget(categoryID: DefaultCategory.groceries.rawValue, amount: 4_500, cadence: .monthly),
        Budget(categoryID: DefaultCategory.takeaway.rawValue, amount: 1_500, cadence: .monthly),
        Budget(categoryID: DefaultCategory.streaming.rawValue, amount: 350, cadence: .monthly),
        Budget(categoryID: DefaultCategory.transport.rawValue, amount: 1_200, cadence: .monthly),
        Budget(categoryID: DefaultCategory.gym.rawValue, amount: 449, cadence: .monthly),
        Budget(categoryID: DefaultCategory.insurance.rawValue, amount: 312, cadence: .monthly),
        Budget(categoryID: DefaultCategory.studentLoan.rawValue, amount: 3_000, cadence: .quarterly(firstDueMonth: 2)),
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
