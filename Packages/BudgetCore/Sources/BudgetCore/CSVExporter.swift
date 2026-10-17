import Foundation

public enum CSVExporter {
    public static let header = "date,amount,currency,counterparty,category"

    /// RFC 4180 style, UTF-8, newest first. Dates are civil dates in Stockholm.
    public static func export(_ transactions: [Transaction]) -> String {
        let rows = transactions.sorted { $0.bookingDate > $1.bookingDate }.map { t in
            [isoDay(t.bookingDate), "\(t.amount)", t.currency, text(t.counterparty), text(t.categoryID)].map(quote).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Spreadsheets execute cells starting with = + - @ or a tab. Bank text is attacker-reachable, so neutralize it.
    static func text(_ field: String) -> String {
        guard let first = field.first, "=+-@\t\r".contains(first) else { return field }
        return "'" + field
    }

    static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "'" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func isoDay(_ date: Date) -> String {
        let c = Calendar.stockholm.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
