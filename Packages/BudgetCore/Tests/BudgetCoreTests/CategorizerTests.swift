import Testing
import Foundation
@testable import BudgetCore

@Suite struct CategorizerTests {
    let categorizer = Categorizer(userRules: [], ownAccountIDs: ["own-savings-hash"])

    @Test func keywordMatchesCaseInsensitivelyOnWordBoundary() {
        #expect(categorizer.categorize(text: "ICA SUPERMARKET STHLM", amount: -120) == DefaultCategory.groceries.rawValue)
        #expect(categorizer.categorize(text: "Musica AB", amount: -120) != DefaultCategory.groceries.rawValue)
    }

    @Test func anEmptyKeywordMatchesNothing() {
        #expect(!Categorizer.matches("", in: Categorizer.normalize("SWISH - ANNA")))
        #expect(!Categorizer.matches("  ", in: Categorizer.normalize("AB, STHLM")))
        #expect(Categorizer(userRules: [KeywordRule(keyword: "", categoryID: "rent")], ownAccountIDs: []).categorize(text: "ICA NÄRA", amount: -50) == "groceries")
    }

    @Test func swedishLettersMatch() {
        #expect(categorizer.categorize(text: "LÄNSFÖRSÄKRINGAR SAK", amount: -300) == DefaultCategory.insurance.rawValue)
    }

    @Test func specExamplesHold() {
        #expect(categorizer.categorize(text: "COOP KONSUM", amount: -80) == DefaultCategory.groceries.rawValue)
        #expect(categorizer.categorize(text: "foodora AB", amount: -150) == DefaultCategory.takeaway.rawValue)
        #expect(categorizer.categorize(text: "UBR* TRIP HELP.UBER.COM", amount: -95) == DefaultCategory.transport.rawValue)
        #expect(categorizer.categorize(text: "SL Access", amount: -1020) == DefaultCategory.transport.rawValue)
        #expect(categorizer.categorize(text: "Systembolaget", amount: -249) == DefaultCategory.entertainment.rawValue)
        #expect(categorizer.categorize(text: "Avanza Bank", amount: -2000) == DefaultCategory.savings.rawValue)
        #expect(categorizer.categorize(text: "Swish mottagen Anna", amount: 500) == DefaultCategory.income.rawValue)
    }

    @Test func userRulesWinOverDefaultsNewestFirst() {
        let rules = [
            KeywordRule(keyword: "ica", categoryID: DefaultCategory.shopping.rawValue),   // newest
            KeywordRule(keyword: "ica", categoryID: DefaultCategory.takeaway.rawValue),
        ]
        let c = Categorizer(userRules: rules, ownAccountIDs: [])
        #expect(c.categorize(text: "ICA NÄRA", amount: -50) == DefaultCategory.shopping.rawValue)
    }

    @Test func ownAccountTransferBeatsEveryRule() {
        let id = categorizer.categorize(text: "Avanza Bank", amount: -2000, counterpartyAccountID: "own-savings-hash")
        #expect(id == DefaultCategory.transfer.rawValue)
        let back = categorizer.categorize(text: "Överföring", amount: 2000, counterpartyAccountID: "own-savings-hash")
        #expect(back == DefaultCategory.transfer.rawValue)
    }

    @Test func refundFromMerchantStaysInSpendingCategory() {
        #expect(categorizer.categorize(text: "ICA SUPERMARKET", amount: 450) == DefaultCategory.groceries.rawValue)
    }

    @Test func unmatchedFallsBackOnSign() {
        #expect(categorizer.categorize(text: "Okänd betalning", amount: 1234) == DefaultCategory.income.rawValue)
        #expect(categorizer.categorize(text: "Okänd betalning", amount: -1234) == DefaultCategory.shopping.rawValue)
    }

    @Test func transferAndIncomeAreNotSpending() {
        #expect(DefaultCategory.transfer.kind == .transfer)
        #expect(DefaultCategory.income.kind == .income)
        #expect(DefaultCategory.savings.kind == .spending)
    }
}
