import Testing
import Foundation
@testable import BudgetCore

@Suite struct MerchantKeyTests {
    @Test func keywordDropsTrailingWordsWithDigits() {
        #expect(MerchantKey.keyword(for: "PRESSBYRAN 5521") == "pressbyran")
        #expect(MerchantKey.keyword(for: "KLARNA*ZALANDO") == "klarna*zalando")
        #expect(MerchantKey.keyword(for: "  ICA  Nära 12 ") == "ica nära")
    }

    @Test func aKeywordThatWouldBeEmptyKeepsTheText() {
        #expect(MerchantKey.keyword(for: "+46766274950") == "+46766274950")
    }

    @Test func everyKeywordMatchesTheTextItCameFrom() {
        for text in ["PRESSBYRAN 5521", "KLARNA*ZALANDO", "+46766274950", "8242039580402", "K*hotels com", "REVOLUT**3590*",
                     "STIFT  STOCKHOLM BG 0000059540146 Bg-bet. via internet", "CENTRALA STUDIESTODSNAMNDEN"] {
            #expect(Categorizer.matches(MerchantKey.keyword(for: text), in: Categorizer.normalize(text)), "\(text)")
        }
    }
}
