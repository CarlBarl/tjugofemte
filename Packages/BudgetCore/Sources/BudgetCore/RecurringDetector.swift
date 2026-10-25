import Foundation

/// A charge that comes back at about the same amount: "Netflix, 149 kr a month".
public struct RecurringCharge: Equatable, Sendable, Identifiable {
    public enum Cadence: Sendable { case monthly, quarterly }
    public let keyword: String
    /// The most recent counterparty text.
    public let name: String
    /// The most recent charge's category.
    public let categoryID: String
    /// Median of the charges, as a positive amount.
    public let amount: Decimal
    public let cadence: Cadence
    public let lastSeen: Date
    public var id: String { keyword }
    /// A quarterly charge counts a third.
    public var perPeriod: Decimal { cadence == .quarterly ? amount / 3 : amount }
}

/// Recurring charges and the want categories they make fixed, recomputed from the transactions on the phone.
public enum RecurringDetector {
    static let tolerancePercent: Decimal = 10
    static let monthlyGap = 25...35
    static let quarterlyGap = 80...100

    /// Money out of spending categories, grouped by merchant keyword. Monthly is three or more charges 25 to 35 days apart,
    /// quarterly two or more 80 to 100 days apart, and every charge within 10 % of the median.
    public static func detect(transactions: [Transaction], excluding: Set<String> = ["rent", "studentLoan"]) -> [RecurringCharge] {
        let moneyOut = transactions.filter { $0.amount < 0 && categoryKind($0.categoryID) == .spending && !excluding.contains($0.categoryID) }
        let groups = Dictionary(grouping: moneyOut) { MerchantKey.keyword(for: $0.counterparty) }
        return groups.compactMap { keyword, items -> RecurringCharge? in
            // An empty counterparty has no keyword to sort by.
            guard !keyword.isEmpty else { return nil }
            let sorted = items.sorted { $0.bookingDate < $1.bookingDate }
            let amounts = sorted.map { -$0.amount }
            let median = PlanSuggestions.median(amounts)
            guard amounts.allSatisfy({ abs($0 - median) <= median * tolerancePercent / 100 }) else { return nil }
            let gaps = zip(sorted, sorted.dropFirst()).map { Calendar.stockholm.dateComponents([.day], from: $0.bookingDate, to: $1.bookingDate).day ?? 0 }
            let cadence: RecurringCharge.Cadence
            if sorted.count >= 3, gaps.allSatisfy(monthlyGap.contains) {
                cadence = .monthly
            } else if sorted.count >= 2, gaps.allSatisfy(quarterlyGap.contains) {
                cadence = .quarterly
            } else {
                return nil
            }
            let last = sorted[sorted.count - 1]
            return RecurringCharge(keyword: keyword, name: last.counterparty, categoryID: last.categoryID, amount: median,
                                   cadence: cadence, lastSeen: last.bookingDate)
        }
        .sorted { ($0.perPeriod, $1.keyword) > ($1.perPeriod, $0.keyword) }
    }

    /// Want categories, other than Unsorted, whose money out is at least `threshold` recurring charges. The goal never trims them.
    public static func fixedCategories(transactions: [Transaction], charges: [RecurringCharge], groups: CategoryGroups,
                                       threshold: Decimal = 0.8) -> Set<String> {
        let recurring = Set(charges.map(\.keyword))
        var total: [String: Decimal] = [:]
        var fromCharges: [String: Decimal] = [:]
        for t in transactions where t.amount < 0 && categoryKind(t.categoryID) == .spending && groups.group(of: t.categoryID) == .want
            && t.categoryID != DefaultCategory.unsorted.rawValue {
            total[t.categoryID, default: 0] -= t.amount
            if recurring.contains(MerchantKey.keyword(for: t.counterparty)) { fromCharges[t.categoryID, default: 0] -= t.amount }
        }
        return Set(total.compactMap { id, sum in fromCharges[id, default: 0] >= sum * threshold ? id : nil })
    }
}
