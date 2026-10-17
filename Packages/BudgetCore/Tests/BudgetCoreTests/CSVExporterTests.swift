import Testing
import Foundation
@testable import BudgetCore

@Suite struct CSVExporterTests {
    @Test func writesHeaderAndOneRowPerTransactionNewestFirst() {
        let txs = [
            Transaction(dedupKey: "a", bookingDate: d(2026, 10, 1), amount: -120.5, currency: "SEK", counterparty: "ICA", categoryID: "groceries"),
            Transaction(dedupKey: "b", bookingDate: d(2026, 10, 3), amount: 35_000, currency: "SEK", counterparty: "Lön", categoryID: "income"),
        ]
        let csv = CSVExporter.export(txs)
        #expect(csv == """
        date,amount,currency,counterparty,category
        2026-10-03,35000,SEK,Lön,income
        2026-10-01,-120.5,SEK,ICA,groceries

        """)
    }

    @Test func quotesFieldsWithCommasQuotesOrNewlines() {
        let txs = [Transaction(dedupKey: "a", bookingDate: d(2026, 10, 1), amount: -1, currency: "SEK", counterparty: "Café \"Söder\", Stockholm", categoryID: "takeaway")]
        let csv = CSVExporter.export(txs)
        #expect(csv.contains("\"Café \"\"Söder\"\", Stockholm\""))
    }
}
