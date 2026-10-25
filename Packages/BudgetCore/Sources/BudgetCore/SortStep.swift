import Foundation

/// An unsorted merchant for the sort step to file: "PRESSBYRAN 5521, 153 kr over 2 purchases".
public struct SortCandidate: Equatable, Sendable, Identifiable {
    public let keyword: String
    /// The most common counterparty text of the group, the most recent on a tie.
    public let name: String
    /// Money out over the history on the phone, as a positive amount.
    public let total: Decimal
    public let count: Int
    public var id: String { keyword }
}

/// The setup's sort step: the biggest unsorted merchants and how much of the spending is already sorted.
public enum SortStep {
    /// Unsorted money out grouped by merchant keyword, biggest total first.
    public static func candidates(transactions: [Transaction], limit: Int = 8) -> [SortCandidate] {
        let unsorted = transactions.filter { $0.amount < 0 && $0.categoryID == DefaultCategory.unsorted.rawValue }
        let groups = Dictionary(grouping: unsorted) { MerchantKey.keyword(for: $0.counterparty) }
        return groups.compactMap { keyword, items -> SortCandidate? in
            // An empty counterparty has no keyword a rule could match.
            guard !keyword.isEmpty else { return nil }
            var seen: [String: (count: Int, last: Date)] = [:]
            for t in items {
                let s = seen[t.counterparty]
                seen[t.counterparty] = ((s?.count ?? 0) + 1, max(s?.last ?? t.bookingDate, t.bookingDate))
            }
            let name = seen.max { ($0.value.count, $0.value.last, $1.key) < ($1.value.count, $1.value.last, $0.key) }!.key
            return SortCandidate(keyword: keyword, name: name, total: items.reduce(0) { $0 - $1.amount }, count: items.count)
        }
        .sorted { ($0.total, $1.keyword) > ($1.total, $0.keyword) }
        .prefix(limit)
        .map { $0 }
    }

    /// The share of money out in spending categories that is not in Unsorted, 0 to 1. Savings and transfers are not spending.
    /// 1 when there is no spending.
    public static func sortedShare(transactions: [Transaction]) -> Decimal {
        var spending: Decimal = 0
        var unsorted: Decimal = 0
        for t in transactions where t.amount < 0 && categoryKind(t.categoryID) == .spending {
            spending -= t.amount
            if t.categoryID == DefaultCategory.unsorted.rawValue { unsorted -= t.amount }
        }
        return spending == 0 ? 1 : (spending - unsorted) / spending
    }
}
