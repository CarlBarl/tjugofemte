import Foundation

public struct BankRef: Codable, Equatable, Sendable {
    public let name: String
    public let country: String
    public init(name: String, country: String) { self.name = name; self.country = country }
}

public struct AuthMethod: Decodable, Equatable, Sendable {
    public struct Credential: Decodable, Equatable, Sendable {
        public let name: String
        public let required: Bool?
    }
    public let approach: String
    public let name: String
    public let psuType: String?
    public let credentials: [Credential]?

    public var requiredCredentials: [String] { (credentials ?? []).filter { $0.required == true }.map(\.name) }

    enum CodingKeys: String, CodingKey { case approach, name, psuType = "psu_type", credentials }
}

public struct Bank: Decodable, Equatable, Sendable {
    public let name: String
    public let country: String
    public let beta: Bool?
    /// Seconds. The bank's ceiling for `valid_until`.
    public let maximumConsentValidity: Int
    public let requiredPSUHeaders: [String]?
    public let authMethods: [AuthMethod]

    enum CodingKeys: String, CodingKey {
        case name, country, beta
        case maximumConsentValidity = "maximum_consent_validity"
        case requiredPSUHeaders = "required_psu_headers"
        case authMethods = "auth_methods"
    }
}

public struct AuthStart: Decodable, Equatable, Sendable {
    public let url: URL
    public let authorizationID: String
    enum CodingKeys: String, CodingKey { case url, authorizationID = "authorization_id" }
}

public struct BankAccount: Equatable, Sendable {
    public let uid: String
    public let name: String?
    public let product: String?
    public let currency: String?
    /// Every identifier the bank gave for this account, normalized, so transfers to it can be recognized.
    public let ownAccountIDs: Set<String>
}

public struct BankSession: Equatable, Sendable {
    public let sessionID: String
    public let validUntil: Date
    public let accounts: [BankAccount]
}

/// The six fields kept from a bank transaction. Everything else in the payload is never decoded.
public struct TransactionRecord: Equatable, Sendable {
    public let transactionID: String?
    public let entryReference: String?
    /// Civil booking date at midnight in Europe/Stockholm.
    public let bookingDate: Date
    /// Negative for money out.
    public let amount: Decimal
    public let currency: String
    public let counterparty: String
    public let counterpartyAccountID: String?
}

/// Account identifiers as banks print them differ only in spaces and punctuation.
func normalizeAccountID(_ raw: String) -> String {
    String(raw.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

enum Wire {
    static let stockholm: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }()

    struct Amount: Decodable { let currency: String; let amount: String }
    struct Party: Decodable { let name: String? }
    struct AccountID: Decodable {
        struct Other: Decodable { let identification: String? }
        let iban: String?
        let other: Other?
        var normalized: String? { (iban ?? other?.identification).map(normalizeAccountID) }
    }

    struct Transaction: Decodable {
        let transactionID: String?
        let entryReference: String?
        let bookingDate: String
        let creditDebitIndicator: String?
        let transactionAmount: Amount
        let creditor: Party?
        let debtor: Party?
        let creditorAccount: AccountID?
        let debtorAccount: AccountID?
        let remittanceInformation: [String]?

        enum CodingKeys: String, CodingKey {
            case transactionID = "transaction_id", entryReference = "entry_reference", bookingDate = "booking_date"
            case creditDebitIndicator = "credit_debit_indicator", transactionAmount = "transaction_amount"
            case creditor, debtor, creditorAccount = "creditor_account", debtorAccount = "debtor_account"
            case remittanceInformation = "remittance_information"
        }

        func record() throws -> TransactionRecord {
            guard let value = Decimal(string: transactionAmount.amount, locale: Locale(identifier: "en_US_POSIX")) else {
                throw ClientError.decoding("amount \(transactionAmount.amount)")
            }
            let parts = bookingDate.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let date = stockholm.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
                throw ClientError.decoding("booking_date \(bookingDate)")
            }
            let isDebit = creditDebitIndicator == "DBIT"
            let magnitude = value < 0 ? -value : value
            let amount: Decimal = switch creditDebitIndicator {
            case "DBIT": -magnitude
            case "CRDT": magnitude
            default: value
            }
            let other = isDebit ? creditor : debtor
            let name = other?.name ?? (isDebit ? debtor : creditor)?.name
            let text = name ?? (remittanceInformation ?? []).joined(separator: " ")
            return TransactionRecord(transactionID: transactionID, entryReference: entryReference, bookingDate: date, amount: amount,
                                     currency: transactionAmount.currency, counterparty: text,
                                     counterpartyAccountID: (isDebit ? creditorAccount : debtorAccount)?.normalized)
        }
    }

    struct TransactionsPage: Decodable {
        let transactions: [Transaction]
        let continuationKey: String?
        enum CodingKeys: String, CodingKey { case transactions, continuationKey = "continuation_key" }
    }

    struct Session: Decodable {
        struct Access: Decodable { let validUntil: String; enum CodingKeys: String, CodingKey { case validUntil = "valid_until" } }
        struct Account: Decodable {
            struct Other: Decodable { let identification: String }
            let uid: String
            let name: String?
            let product: String?
            let currency: String?
            let accountID: AccountID?
            let allAccountIDs: [Other]?
            enum CodingKeys: String, CodingKey { case uid, name, product, currency, accountID = "account_id", allAccountIDs = "all_account_ids" }
        }
        let sessionID: String
        let access: Access
        let accounts: [Account]
        enum CodingKeys: String, CodingKey { case sessionID = "session_id", access, accounts }

        func session() throws -> BankSession {
            guard let until = ISO8601DateFormatter().date(from: access.validUntil) else { throw ClientError.decoding("valid_until \(access.validUntil)") }
            let accounts = accounts.map { a in
                var ids = Set((a.allAccountIDs ?? []).map { normalizeAccountID($0.identification) })
                if let primary = a.accountID?.normalized { ids.insert(primary) }
                return BankAccount(uid: a.uid, name: a.name, product: a.product, currency: a.currency, ownAccountIDs: ids)
            }
            return BankSession(sessionID: sessionID, validUntil: until, accounts: accounts)
        }
    }

    struct Banks: Decodable { let aspsps: [Bank] }
    struct ErrorBody: Decodable { let code: String?; let message: String? }
}
