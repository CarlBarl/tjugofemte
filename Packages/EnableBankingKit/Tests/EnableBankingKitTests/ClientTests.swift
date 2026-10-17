import Testing
import Foundation
@testable import EnableBankingKit

@Suite struct ClientTests {
    let key = try! RSAKey.ephemeral(bits: 2048, keyID: "app-123")

    func client(_ transport: StubTransport) -> EnableBankingClient {
        EnableBankingClient(signer: key, transport: transport, psu: PSUHeaders(ipAddress: "10.0.0.5", userAgent: "Tjugofemte/1.0"))
    }

    @Test func refusesAnyHostOtherThanTheAPI() throws {
        #expect(throws: ClientError.self) { try EnableBankingClient.checkHost(URL(string: "https://evil.example/aspsps")!) }
        #expect(throws: ClientError.self) { try EnableBankingClient.checkHost(URL(string: "http://api.enablebanking.com/aspsps")!) }
        #expect(throws: Never.self) { try EnableBankingClient.checkHost(URL(string: "https://api.enablebanking.com/aspsps?country=SE")!) }
    }

    @Test func everyRequestCarriesBearerAndPSUHeaders() async throws {
        let transport = StubTransport([(200, aspspsJSON)])
        _ = try await client(transport).aspsps(country: "SE")
        let request = transport.calls[0].request
        #expect(request.url?.absoluteString == "https://api.enablebanking.com/aspsps?country=SE")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer eyJ") == true)
        #expect(request.value(forHTTPHeaderField: "Psu-Ip-Address") == "10.0.0.5")
        #expect(request.value(forHTTPHeaderField: "Psu-User-Agent") == "Tjugofemte/1.0")
    }

    @Test func decodesBanksWithConsentLimitAndAuthApproaches() async throws {
        let banks = try await client(StubTransport([(200, aspspsJSON)])).aspsps(country: "SE")
        #expect(banks.count == 1)
        #expect(banks[0].name == "Swedbank")
        #expect(banks[0].maximumConsentValidity == 15_552_000)
        #expect(banks[0].requiredPSUHeaders == ["Psu-Ip-Address"])
        #expect(banks[0].authMethods.map(\.approach) == ["DECOUPLED", "REDIRECT"])
        #expect(banks[0].authMethods[0].requiredCredentials == ["ssn"])
    }

    @Test func startAuthPostsTheDocumentedBody() async throws {
        let transport = StubTransport([(200, #"{"url":"https://auth.enablebanking.com/ais/start?sessionid=1","authorization_id":"auth-1"}"#)])
        let validUntil = Date(timeIntervalSince1970: 1_776_254_400)  // 2026-04-15T12:00:00Z
        let start = try await client(transport).startAuth(bank: .init(name: "Swedbank", country: "SE"), redirectURL: URL(string: "tjugofemte://callback")!,
                                                          state: "nonce-1", validUntil: validUntil, authMethod: "BankID web")
        #expect(start.url.host == "auth.enablebanking.com")
        let request = transport.calls[0].request
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/auth")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["psu_type"] as? String == "personal")
        #expect(body["state"] as? String == "nonce-1")
        #expect(body["redirect_url"] as? String == "tjugofemte://callback")
        #expect(body["auth_method"] as? String == "BankID web")
        #expect((body["aspsp"] as? [String: String]) == ["name": "Swedbank", "country": "SE"])
        #expect((body["access"] as? [String: String])?["valid_until"] == "2026-04-15T12:00:00Z")
    }

    @Test func createSessionKeepsAccountsAndNormalizedOwnIDs() async throws {
        let transport = StubTransport([(200, sessionJSON)])
        let session = try await client(transport).createSession(code: "code-1")
        #expect(transport.calls[0].request.url?.path == "/sessions")
        #expect(session.sessionID == "sess-1")
        #expect(session.bankName == "Swedbank")
        #expect(session.validUntil == Date(timeIntervalSince1970: 1_807_790_400))  // 2027-04-15T12:00:00Z
        #expect(session.accounts.count == 1)
        #expect(session.accounts[0].uid == "acc-uid-1")
        #expect(session.accounts[0].name == "Privatkonto")
        #expect(session.accounts[0].ownAccountIDs == ["SE4550000000058398257466", "832791234567890"])
    }

    @Test func transactionsKeepSixFieldsAndSignByIndicator() async throws {
        let transport = StubTransport([(200, transactionsJSON([icaJSON, salaryJSON, noNamesJSON], next: nil))])
        let records = try await client(transport).transactions(accountUID: "acc-uid-1", from: Date(timeIntervalSince1970: 1_790_294_400))
        let request = transport.calls[0].request
        #expect(request.url?.path == "/accounts/acc-uid-1/transactions")
        #expect(request.url?.query?.contains("transaction_status=BOOK") == true)
        #expect(request.url?.query?.contains("date_from=2026-09-25") == true)

        #expect(records.count == 3)
        #expect(records[0].transactionID == "tx-1")
        #expect(records[0].amount == Decimal(string: "-120.50"))
        #expect(records[0].currency == "SEK")
        #expect(records[0].counterparty == "ICA SUPERMARKET STHLM")
        #expect(records[0].counterpartyAccountID == "SE" + String(repeating: "1", count: 22))
        #expect(records[1].transactionID == nil)
        #expect(records[1].entryReference == "ref-2")
        #expect(records[1].amount == 35_000)
        #expect(records[1].counterparty == "NEWARE AB")
        #expect(records[1].counterpartyAccountID == "832799999999999")
        #expect(records[2].amount == -49)   // already negative in the payload, stays negative
        #expect(records[2].counterparty == "Swish skickad Anna")
        #expect(records[2].counterpartyAccountID == nil)
    }

    @Test func pagingFollowsContinuationKeyAndToleratesEmptyPages() async throws {
        let transport = StubTransport([
            (200, transactionsJSON([], next: "k1")),           // Swedbank quirk for older history
            (200, transactionsJSON([icaJSON], next: "k2")),
            (200, transactionsJSON([salaryJSON], next: nil)),
        ])
        let records = try await client(transport).transactions(accountUID: "acc-uid-1", from: Date(timeIntervalSince1970: 1_790_294_400))
        #expect(records.count == 2)
        #expect(transport.calls.count == 3)
        #expect(transport.calls[0].request.url?.query?.contains("continuation_key") == false)
        #expect(transport.calls[1].request.url?.query?.contains("continuation_key=k1") == true)
        #expect(transport.calls[2].request.url?.query?.contains("continuation_key=k2") == true)
    }

    @Test func deleteSessionCallsTheDocumentedEndpoint() async throws {
        let transport = StubTransport([(200, #"{"message":"OK"}"#)])
        try await client(transport).deleteSession("sess-1")
        #expect(transport.calls[0].request.httpMethod == "DELETE")
        #expect(transport.calls[0].request.url?.path == "/sessions/sess-1")
    }

    @Test func expiredSessionBecomesNeedsReauth() async throws {
        let transport = StubTransport([(401, #"{"message":"Session is expired","code":"EXPIRED_SESSION"}"#)])
        await #expect(throws: ClientError.sessionExpired) {
            _ = try await client(transport).transactions(accountUID: "acc-uid-1", from: Date())
        }
    }

    @Test func rateLimitSurfacesAsItsOwnError() async throws {
        let transport = StubTransport([(429, #"{"message":"ASPSP Rate limit exceeded","code":"ASPSP_RATE_LIMIT_EXCEEDED"}"#)])
        await #expect(throws: ClientError.rateLimited) {
            _ = try await client(transport).transactions(accountUID: "acc-uid-1", from: Date())
        }
    }
}
