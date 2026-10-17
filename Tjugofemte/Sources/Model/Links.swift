import Foundation

/// The only outside links the app shows. The lint script allows exactly these hosts.
enum Links {
    static let controlPanel = URL(string: "https://enablebanking.com/cp/applications")!
    static let repository = URL(string: "https://github.com/CarlBarl/tjugofemte")!
    static let privacy = URL(string: "https://carlbarl.github.io/tjugofemte/privacy")!
    static let terms = URL(string: "https://carlbarl.github.io/tjugofemte/terms")!
}

import BudgetCore

/// SwiftUI also has a `Transaction`; the app means the bank kind.
typealias Transaction = BudgetCore.Transaction

extension Budget: @retroactive Identifiable {
    public var id: String { categoryID }
}
