import Foundation
@testable import EnableBankingKit

/// Records requests and serves canned responses in order. One instance per test.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Call { let request: URLRequest; let body: Data? }
    private(set) var calls: [Call] = []
    private var responses: [(Int, Data)]

    init(_ responses: [(status: Int, json: String)]) {
        self.responses = responses.map { ($0.status, Data($0.json.utf8)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls.append(Call(request: request, body: request.httpBody))
        guard !responses.isEmpty else { fatalError("unexpected request \(request.url!)") }
        let (status, data) = responses.removeFirst()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

let aspspsJSON = """
{"aspsps":[{"name":"Swedbank","country":"SE","beta":false,"maximum_consent_validity":15552000,
"required_psu_headers":["Psu-Ip-Address"],"psu_types":["personal","business"],
"auth_methods":[{"approach":"DECOUPLED","name":"BankID","psu_type":"personal","hidden_method":false,
"credentials":[{"name":"ssn","title":"Personnummer","required":true}]},
{"approach":"REDIRECT","name":"BankID web","psu_type":"personal","hidden_method":false,"credentials":[]}]},
{"name":"Roslagens Sparbank","country":"SE","beta":false,"maximum_consent_validity":15552000,
"auth_methods":[{"approach":"DECOUPLED","psu_type":"personal"}]}]}
"""

let sessionJSON = """
{"session_id":"sess-1","psu_type":"personal","aspsp":{"name":"Swedbank","country":"SE"},
"access":{"valid_until":"2027-04-15T12:00:00Z"},
"accounts":[{"uid":"acc-uid-1","name":"Privatkonto","product":"Privatkonto","currency":"SEK",
"account_id":{"iban":"SE45 5000 0000 0583 9825 7466"},
"all_account_ids":[{"identification":"8327-9,123 456 789-0","scheme_name":"BBAN"},{"identification":"SE4550000000058398257466","scheme_name":"IBAN"}],
"identification_hash":"abc"}]}
"""

func transactionsJSON(_ items: [String], next: String?) -> String {
    let key = next.map { "\"\($0)\"" } ?? "null"
    return "{\"transactions\":[\(items.joined(separator: ","))],\"continuation_key\":\(key)}"
}

let icaJSON = """
{"transaction_id":"tx-1","entry_reference":"ref-1","booking_date":"2026-10-01","status":"BOOK",
"credit_debit_indicator":"DBIT","transaction_amount":{"currency":"SEK","amount":"120.50"},
"creditor":{"name":"ICA SUPERMARKET STHLM"},"creditor_account":{"iban":"SE11 1111 1111 1111 1111 1111"},
"remittance_information":["Kortköp 123"],"merchant_category_code":"5411","note":"dropped"}
"""

let salaryJSON = """
{"transaction_id":null,"entry_reference":"ref-2","booking_date":"2026-09-25","status":"BOOK",
"credit_debit_indicator":"CRDT","transaction_amount":{"currency":"SEK","amount":"35000"},
"debtor":{"name":"NEWARE AB"},"debtor_account":{"other":{"identification":"8327-9,999 999 999-9","scheme_name":"BBAN"}},
"remittance_information":["Lön september"]}
"""

let noNamesJSON = """
{"entry_reference":"ref-3","booking_date":"2026-10-02","status":"BOOK",
"credit_debit_indicator":"DBIT","transaction_amount":{"currency":"SEK","amount":"-49"},
"remittance_information":["Swish skickad","Anna"]}
"""

/// Roslagens Sparbank card purchase as measured on 2026-10-23: no creditor, the holder as debtor, merchant only in remittance.
let cardJSON = """
{"entry_reference":"ref-card","booking_date":"2026-10-20","credit_debit_indicator":"DBIT",
"transaction_amount":{"amount":"245.00","currency":"SEK"},
"debtor":{"name":"CARL ELELID"},"debtor_account":{"iban":"SE4580000000000000000001"},"remittance_information":["SPAR AURLAND"]}
"""

let unsignedIndicatorJSON = """
{"entry_reference":"ref-nil","booking_date":"2026-10-21","transaction_amount":{"amount":"-89.00","currency":"SEK"},
"creditor":{"name":"PRESSBYRAN 5521"},"creditor_account":{"iban":"SE1100000000000000000002"},
"debtor":{"name":"CARL ELELID"},"debtor_account":{"iban":"SE4580000000000000000001"}}
"""

let holderOnlyJSON = """
{"entry_reference":"ref-holder","booking_date":"2026-10-22","credit_debit_indicator":"DBIT",
"transaction_amount":{"amount":"30.00","currency":"SEK"},"debtor":{"name":"CARL ELELID"}}
"""
