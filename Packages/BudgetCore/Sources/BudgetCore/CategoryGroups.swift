import Foundation

/// Needs, wants and savings, the three parts of the 50/30/20 split.
public enum CategoryGroup: String, Sendable, Codable {
    case need, want, saving
}

/// Which group each category counts as. The user's flips are stored as overrides; Unsorted cannot be flipped
/// and is always a want. Income and transfers are in no group.
public struct CategoryGroups: Equatable, Sendable, Codable {
    public var overrides: [String: CategoryGroup]

    public init(overrides: [String: CategoryGroup] = [:]) {
        self.overrides = overrides
    }

    public func group(of categoryID: String) -> CategoryGroup? {
        if categoryID == DefaultCategory.unsorted.rawValue { return .want }
        return overrides[categoryID] ?? Self.defaults[categoryID]
    }

    static let defaults: [String: CategoryGroup] = ([
        (.rent, .need), (.studentLoan, .need), (.insurance, .need), (.groceries, .need), (.transport, .need), (.health, .need),
        (.takeaway, .want), (.streaming, .want), (.subscriptions, .want), (.gym, .want), (.entertainment, .want), (.shopping, .want),
        (.unsorted, .want),
        (.savings, .saving),
    ] as [(DefaultCategory, CategoryGroup)]).reduce(into: [:]) { $0[$1.0.rawValue] = $1.1 }
}
