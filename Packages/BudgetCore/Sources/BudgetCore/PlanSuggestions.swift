import Foundation

/// A recurring deposit worth planning around: "Lön", 34 200 per period, seen three times.
public struct IncomeSuggestion: Equatable, Sendable, Identifiable {
    public var id: String { key }
    /// The counterparty text with digits and punctuation stripped, which is what makes "LÖN 2026-09" and "LÖN 2026-10" one source.
    public let key: String
    public let name: String
    public let keyword: String
    /// Median of the per-period totals, so one missing month does not halve it.
    public let amount: Decimal
    public let periodsSeen: Int
    /// Day of month of each deposit, for the payday guess.
    public let depositDays: [Int]
}

/// Plan numbers guessed from the transactions already on the phone, for the user to confirm rather than type.
public enum PlanSuggestions {
    static let minimumIncome: Decimal = 1_000

    public static func incomes(transactions: [Transaction], rule: PeriodRule, today: Date = Date()) -> [IncomeSuggestion] {
        let dataPeriods = Set(transactions.map { rule.period(containing: $0.bookingDate).label }).count
        let deposits = transactions.filter { categoryKind($0.categoryID) == .income && $0.amount > 0 }
        let groups = Dictionary(grouping: deposits) { groupingKey($0.counterparty) }
        return groups.compactMap { key, items -> IncomeSuggestion? in
            var perPeriod: [PeriodLabel: Decimal] = [:]
            for t in items { perPeriod[rule.period(containing: t.bookingDate).label, default: 0] += t.amount }
            let amount = median(Array(perPeriod.values))
            guard amount >= minimumIncome, dataPeriods < 2 || perPeriod.count >= 2 else { return nil }
            let words = key.split(separator: " ")
            let keyword = words.first { $0.count >= 2 }.map(String.init) ?? key
            return IncomeSuggestion(key: key, name: key.prefix(1).uppercased() + key.dropFirst(), keyword: keyword, amount: amount,
                                    periodsSeen: perPeriod.count, depositDays: items.map { Calendar.stockholm.component(.day, from: $0.bookingDate) })
        }
        .sorted { ($0.amount, $1.key) > ($1.amount, $0.key) }
        .prefix(4)
        .map { $0 }
    }

    /// The main income's latest deposit day: salaries move earlier around weekends, never later.
    /// A month-end salary (29th or later) becomes plain calendar months, which is what `startDay` 1 means.
    public static func payday(transactions: [Transaction], rule: PeriodRule, today: Date = Date()) -> Int? {
        guard let latest = incomes(transactions: transactions, rule: rule, today: today).first?.depositDays.max() else { return nil }
        return latest >= 29 ? 1 : latest
    }

    public static func roundUp(_ amount: Decimal, to step: Decimal) -> Decimal {
        guard amount > 0 else { return 0 }
        var quotient = amount / step
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .up)
        return rounded * step
    }

    static func groupingKey(_ text: String) -> String {
        String(Categorizer.normalize(text).map { $0.isLetter || $0.isWhitespace ? $0 : " " })
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func median(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[(sorted.count - 1) / 2]
    }
}
