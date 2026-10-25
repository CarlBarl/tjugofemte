import Foundation
import CryptoKit

/// Stable identity for a booked transaction. Bank id first, entry reference second,
/// and a fingerprint when the bank gives neither (or gives unstable ones).
public enum DedupKey {
    /// Internal so a fetch can only be keyed with `makeAll`: one key at a time would merge repeat payments.
    static func make(transactionID: String?, entryReference: String?, bookingDate: Date,
                     amount: Decimal, currency: String, counterparty: String) -> String {
        bankKey(transactionID: transactionID, entryReference: entryReference)
            ?? fingerprint(material(bookingDate: bookingDate, amount: amount, currency: currency, counterparty: counterparty))
    }

    /// The fields one transaction's key is made from.
    public struct Item: Sendable {
        public let transactionID: String?
        public let entryReference: String?
        public let bookingDate: Date
        public let amount: Decimal
        public let currency: String
        public let counterparty: String

        public init(transactionID: String?, entryReference: String?, bookingDate: Date, amount: Decimal, currency: String, counterparty: String) {
            self.transactionID = transactionID
            self.entryReference = entryReference
            self.bookingDate = bookingDate
            self.amount = amount
            self.currency = currency
            self.counterparty = counterparty
        }
    }

    /// Keys for one fetch, in order. Separate payments without a bank identifier can match on everything the
    /// fingerprint uses (two coffees at the same café on the same day), so the second and later get an occurrence
    /// number in theirs. The first keeps the key `make` gives, so rows already stored keep their keys.
    public static func makeAll(_ items: [Item]) -> [String] {
        var seen: [String: Int] = [:]
        return items.map { i in
            if let key = bankKey(transactionID: i.transactionID, entryReference: i.entryReference) { return key }
            let m = material(bookingDate: i.bookingDate, amount: i.amount, currency: i.currency, counterparty: i.counterparty)
            let n = (seen[m] ?? 0) + 1
            seen[m] = n
            return fingerprint(n == 1 ? m : "\(m)|#\(n)")
        }
    }

    private static func bankKey(transactionID: String?, entryReference: String?) -> String? {
        if let id = present(transactionID) { return "id:\(id)" }
        if let ref = present(entryReference) { return "ref:\(ref)" }
        return nil
    }

    private static func material(bookingDate: Date, amount: Decimal, currency: String, counterparty: String) -> String {
        let day = Calendar.stockholm.dateComponents([.year, .month, .day], from: bookingDate)
        let text = Categorizer.normalize(counterparty)
        return "\(day.year!)-\(day.month!)-\(day.day!)|\(amount)|\(currency.uppercased())|\(text)"
    }

    private static func fingerprint(_ material: String) -> String {
        let digest = SHA256.hash(data: Data(material.utf8))
        return "fp:" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func present(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
