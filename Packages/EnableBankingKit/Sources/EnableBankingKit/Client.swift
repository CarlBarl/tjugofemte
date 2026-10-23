import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Plain URLSession that refuses every redirect, so a response can never steer the app to another host.
public final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    public override init() { super.init() }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.decoding("non-HTTP response") }
        return (data, http)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ClientError: Error, Equatable {
    case disallowedHost(String)
    case sessionExpired
    case rateLimited
    case http(status: Int, code: String?, message: String?)
    case decoding(String)
    /// The start date was before the bank's history window; `earliest` is the first day it allows.
    case wrongPeriod(earliest: Date)
}

/// Headers that tell the bank the user is present. Sent all together or not at all (Enable Banking FAQ).
public struct PSUHeaders: Sendable {
    public let ipAddress: String?
    public let userAgent: String

    public init(ipAddress: String?, userAgent: String) {
        self.ipAddress = ipAddress
        self.userAgent = userAgent
    }

    /// The device's own IPv4 address on Wi-Fi or cellular. Learning the public address would need a call to another host.
    public static func deviceIPv4Address() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let name = String(cString: ifa.ifa_name)
            if name == "en0" || name.hasPrefix("pdp_ip") { return ip }
            fallback = fallback ?? ip
        }
        return fallback
    }
}

/// The only type in the app that talks to the network. Every URL is checked against one host.
public actor EnableBankingClient {
    public static let host = "api.enablebanking.com"

    private let signer: TokenSigner
    private let transport: HTTPTransport
    private let psu: PSUHeaders

    public init(signer: TokenSigner, transport: HTTPTransport = URLSessionTransport(), psu: PSUHeaders) {
        self.signer = signer
        self.transport = transport
        self.psu = psu
    }

    public static func checkHost(_ url: URL) throws {
        guard url.scheme == "https", url.host == host else { throw ClientError.disallowedHost(url.absoluteString) }
    }

    public func aspsps(country: String) async throws -> [Bank] {
        let banks: Wire.Banks = try await get("/aspsps", query: [("country", country)])
        return banks.aspsps
    }

    public func startAuth(bank: BankRef, redirectURL: URL, state: String, validUntil: Date,
                          authMethod: String? = nil, psuID: String? = nil) async throws -> AuthStart {
        var body: [String: Any] = [
            "access": ["valid_until": validUntil.formatted(.iso8601)],
            "aspsp": ["name": bank.name, "country": bank.country],
            "state": state,
            "redirect_url": redirectURL.absoluteString,
            "psu_type": "personal",
        ]
        body["auth_method"] = authMethod
        body["psu_id"] = psuID
        return try await send(method: "POST", path: "/auth", query: [], body: body)
    }

    public func createSession(code: String) async throws -> BankSession {
        let wire: Wire.Session = try await send(method: "POST", path: "/sessions", query: [], body: ["code": code])
        return try wire.session()
    }

    /// Booked transactions from `from` onwards, following continuation keys. Empty pages with a key are
    /// normal for Swedbank history older than 90 days, so paging stops only when the key is gone.
    /// A start before the bank's window is retried once from the earliest day the bank names.
    public func transactions(accountUID: String, from: Date) async throws -> FetchedTransactions {
        do {
            return FetchedTransactions(records: try await pages(accountUID: accountUID, from: from), from: from)
        } catch ClientError.wrongPeriod(let earliest) where earliest > from {
            return FetchedTransactions(records: try await pages(accountUID: accountUID, from: earliest), from: earliest)
        }
    }

    private func pages(accountUID: String, from: Date) async throws -> [TransactionRecord] {
        var records: [TransactionRecord] = []
        var continuation: String?
        for _ in 0..<1000 {  // ponytail: hard stop instead of trusting the bank to end the chain
            var query = [("date_from", Self.civilDay(from)), ("transaction_status", "BOOK")]
            if let continuation { query.append(("continuation_key", continuation)) }
            let page: Wire.TransactionsPage = try await get("/accounts/\(accountUID)/transactions", query: query)
            records += try page.transactions.map { try $0.record() }
            guard let next = page.continuationKey, !next.isEmpty else { return records }
            continuation = next
        }
        return records
    }

    /// Account uids of an existing session, for when the app restarts with a session but no account list.
    public func sessionAccountUIDs(_ sessionID: String) async throws -> [String] {
        struct Response: Decodable { let accounts: [String] }
        let response: Response = try await get("/sessions/\(sessionID)", query: [])
        return response.accounts
    }

    public func accountDetails(uid: String) async throws -> BankAccount {
        let account: Wire.Session.Account = try await get("/accounts/\(uid)/details", query: [])
        return account.bankAccount(uid: uid)
    }

    public func deleteSession(_ sessionID: String) async throws {
        struct OK: Decodable { let message: String? }
        let _: OK = try await send(method: "DELETE", path: "/sessions/\(sessionID)", query: [], body: nil)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, query: [(String, String)]) async throws -> T {
        try await send(method: "GET", path: path, query: query, body: nil)
    }

    private func send<T: Decodable>(method: String, path: String, query: [(String, String)], body: [String: Any]?) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.0, value: $0.1) }
        let url = components.url!
        try Self.checkHost(url)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try JWT.make(signer: signer))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ip = psu.ipAddress {
            request.setValue(ip, forHTTPHeaderField: "Psu-Ip-Address")
            request.setValue(psu.userAgent, forHTTPHeaderField: "Psu-User-Agent")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(Wire.ErrorBody.self, from: data)
            switch error?.reason {
            case "EXPIRED_SESSION", "CLOSED_SESSION": throw ClientError.sessionExpired
            case "ASPSP_RATE_LIMIT_EXCEEDED": throw ClientError.rateLimited
            case "WRONG_TRANSACTIONS_PERIOD":
                // Without the bank's own date, fall back to the 90 days PSD2 lets a bank share without a new login.
                let fallback = Wire.stockholm.date(byAdding: .day, value: -89, to: Wire.stockholm.startOfDay(for: Date()))!
                throw ClientError.wrongPeriod(earliest: error?.earliestDay ?? fallback)
            default: throw ClientError.http(status: response.statusCode, code: error?.reason, message: error?.message)
            }
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ClientError.decoding("\(T.self): \(error)") }
    }


    static func civilDay(_ date: Date) -> String {
        let c = Wire.stockholm.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
