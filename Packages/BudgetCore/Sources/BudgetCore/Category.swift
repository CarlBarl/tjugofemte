import Foundation

public enum CategoryKind: Sendable {
    case spending, income, transfer
}

/// Built-in categories. Display names live in the app's string catalog (sv/en); the raw value is the stored id.
public enum DefaultCategory: String, CaseIterable, Sendable {
    case rent, studentLoan, subscriptions, streaming, insurance, gym, groceries, takeaway,
         transport, entertainment, health, shopping, savings, income, transfer

    public var kind: CategoryKind {
        switch self {
        case .income: .income
        case .transfer: .transfer
        default: .spending
        }
    }
}
