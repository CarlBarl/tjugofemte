import Testing
import Foundation
@testable import BudgetCore

@Suite struct CategoryGroupsTests {
    @Test func defaultGroupsFollowTheSpec() {
        let g = CategoryGroups()
        for id in ["rent", "studentLoan", "insurance", "groceries", "transport", "health"] { #expect(g.group(of: id) == .need) }
        for id in ["takeaway", "streaming", "subscriptions", "gym", "entertainment", "shopping", "unsorted"] { #expect(g.group(of: id) == .want) }
        #expect(g.group(of: "savings") == .saving)
        #expect(g.group(of: "income") == nil)
        #expect(g.group(of: "transfer") == nil)
    }

    @Test func anOverrideFlipsACategoryButNeverUnsorted() {
        let g = CategoryGroups(overrides: ["groceries": .want, "gym": .need, "unsorted": .need])
        #expect(g.group(of: "groceries") == .want)
        #expect(g.group(of: "gym") == .need)
        #expect(g.group(of: "unsorted") == .want)
    }
}
