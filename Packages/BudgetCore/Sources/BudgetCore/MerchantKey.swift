import Foundation

/// The keyword a sort rule is saved under for a merchant.
public enum MerchantKey {
    /// The counterparty text lowercased, with trailing words that contain a digit removed: "PRESSBYRAN 5521" gives "pressbyran".
    /// Text that would lose every word, like a phone number, is kept whole.
    public static func keyword(for counterparty: String) -> String {
        let text = Categorizer.normalize(counterparty)
        var words = text.split(separator: " ")
        while let last = words.last, last.contains(where: \.isNumber) { words.removeLast() }
        return words.isEmpty ? text : words.joined(separator: " ")
    }
}
