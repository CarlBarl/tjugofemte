import Foundation
import CryptoKit

/// Stable identity for a booked transaction. Bank id first, entry reference second,
/// and a fingerprint when the bank gives neither (or gives unstable ones).
public enum DedupKey {
    public static func make(transactionID: String?, entryReference: String?, bookingDate: Date,
                            amount: Decimal, currency: String, counterparty: String) -> String {
        if let id = present(transactionID) { return "id:\(id)" }
        if let ref = present(entryReference) { return "ref:\(ref)" }
        let day = Calendar.stockholm.dateComponents([.year, .month, .day], from: bookingDate)
        let text = Categorizer.normalize(counterparty)
        let material = "\(day.year!)-\(day.month!)-\(day.day!)|\(amount)|\(currency.uppercased())|\(text)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return "fp:" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func present(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
