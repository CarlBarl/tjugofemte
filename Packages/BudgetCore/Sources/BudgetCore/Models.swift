import Foundation

/// The six fields kept from a bank transaction, plus the category. Everything else is dropped at decode time.
public struct Transaction: Equatable, Sendable, Identifiable {
    public var id: String { dedupKey }
    public let dedupKey: String
    public let bookingDate: Date
    /// Negative for money out, positive for money in.
    public let amount: Decimal
    public let currency: String
    public let counterparty: String
    public var categoryID: String

    public init(dedupKey: String, bookingDate: Date, amount: Decimal, currency: String, counterparty: String, categoryID: String) {
        self.dedupKey = dedupKey
        self.bookingDate = bookingDate
        self.amount = amount
        self.currency = currency
        self.counterparty = counterparty
        self.categoryID = categoryID
    }
}

public struct IncomeSource: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public var name: String
    public var plannedAmount: Decimal
    /// Incoming transactions matching this keyword count as this source's actual. nil means plan-only.
    public var keyword: String?

    public init(id: String, name: String, plannedAmount: Decimal, keyword: String?) {
        self.id = id
        self.name = name
        self.plannedAmount = plannedAmount
        self.keyword = keyword
    }
}

public enum BudgetCadence: Equatable, Sendable, Codable {
    case monthly
    /// `amount` is the quarterly total; it falls due every third month starting at `firstDueMonth` (1-12).
    case quarterly(firstDueMonth: Int)
}

public struct Budget: Equatable, Sendable, Codable {
    public let categoryID: String
    public var amount: Decimal
    public var cadence: BudgetCadence

    public init(categoryID: String, amount: Decimal, cadence: BudgetCadence) {
        self.categoryID = categoryID
        self.amount = amount
        self.cadence = cadence
    }
}

public func categoryKind(_ id: String) -> CategoryKind {
    DefaultCategory(rawValue: id)?.kind ?? .spending
}
