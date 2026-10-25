import Foundation

public enum CategoryKind: Sendable {
    case spending, income, transfer, saving
}

/// Built-in categories. Display names live in the app's string catalog (sv/en); the raw value is the stored id.
public enum DefaultCategory: String, CaseIterable, Sendable {
    case rent, studentLoan, subscriptions, streaming, insurance, gym, groceries, takeaway,
         transport, entertainment, health, shopping, unsorted, savings, income, transfer

    public var kind: CategoryKind {
        switch self {
        case .income: .income
        case .transfer: .transfer
        case .savings: .saving
        default: .spending
        }
    }
}
