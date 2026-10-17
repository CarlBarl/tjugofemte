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

@Suite struct CSVFormulaInjectionTests {
    @Test func textStartingWithFormulaTriggerIsNeutralized() {
        let txs = [Transaction(dedupKey: "a", bookingDate: d(2026, 10, 1), amount: -1, currency: "SEK", counterparty: "=HYPERLINK(\"http://x\")", categoryID: "+cmd")]
        let csv = CSVExporter.export(txs)
        #expect(csv.contains("\"'=HYPERLINK(\"\"http://x\"\")\",\"'+cmd\""))
    }

    @Test func negativeAmountsAreNotTouched() {
        let txs = [Transaction(dedupKey: "a", bookingDate: d(2026, 10, 1), amount: -120.5, currency: "SEK", counterparty: "ICA", categoryID: "groceries")]
        #expect(CSVExporter.export(txs).contains(",-120.5,"))
    }
}

@Suite struct CSVFormulaInjectionEdgeTests {
    func row(_ counterparty: String, currency: String = "SEK") -> String {
        CSVExporter.export([Transaction(dedupKey: "a", bookingDate: d(2026, 10, 1), amount: -1, currency: currency, counterparty: counterparty, categoryID: "x")])
            .split(separator: "\n").last.map(String.init) ?? ""
    }

    @Test func combiningMarkAfterTriggerIsStillNeutralized() {
        #expect(row("=\u{301}SUM(1)").contains("\"'=\u{301}SUM(1)\""))
    }

    @Test func leadingWhitespaceBeforeTriggerIsNeutralized() {
        #expect(row(" \t=1+1").contains("\"' \t=1+1\""))
    }

    @Test func fullwidthTriggersAreNeutralized() {
        #expect(row("＝1").contains("\"'＝1\""))
    }

    @Test func currencyColumnIsNeutralizedToo() {
        #expect(row("ICA", currency: "=X").contains(",\"'=X\","))
    }
}
