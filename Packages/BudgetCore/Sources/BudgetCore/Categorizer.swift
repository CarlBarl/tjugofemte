import Foundation

public struct KeywordRule: Equatable, Sendable, Codable {
    public let keyword: String
    public let categoryID: String

    public init(keyword: String, categoryID: String) {
        self.keyword = keyword
        self.categoryID = categoryID
    }
}

/// Keyword categorization. Order: own-account transfer, user rules (newest first), default rules,
/// then sign of the amount. Rules apply regardless of sign, so a merchant refund lands in the
/// merchant's spending category instead of counting as income.
public struct Categorizer: Sendable {
    public let userRules: [KeywordRule]
    public let ownAccountIDs: Set<String>

    public init(userRules: [KeywordRule], ownAccountIDs: Set<String>) {
        self.userRules = userRules
        self.ownAccountIDs = ownAccountIDs
    }

    public func categorize(text: String, amount: Decimal, counterpartyAccountID: String? = nil) -> String {
        if let id = counterpartyAccountID, ownAccountIDs.contains(id) {
            return DefaultCategory.transfer.rawValue
        }
        let haystack = Self.normalize(text)
        for rule in userRules + Self.defaultRules where Self.matches(rule.keyword, in: haystack) {
            return rule.categoryID
        }
        return amount > 0 ? DefaultCategory.income.rawValue : DefaultCategory.unsorted.rawValue
    }

    /// Whole-word, case-insensitive match. "ica" matches "ICA NÄRA" and "UBR*", not "Musica".
    static func matches(_ keyword: String, in haystack: String) -> Bool {
        // An empty keyword would match every gap between two non-letters.
        let normalized = normalize(keyword)
        guard !normalized.isEmpty else { return false }
        let needle = NSRegularExpression.escapedPattern(for: normalized)
        return haystack.range(of: "(?<![\\p{L}\\p{N}])\(needle)(?![\\p{L}\\p{N}])", options: .regularExpression) != nil
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let defaultRules: [KeywordRule] = ([
        ("hyra", .rent), ("csn", .studentLoan),
        ("netflix", .streaming), ("spotify", .streaming), ("hbo", .streaming), ("disney", .streaming), ("viaplay", .streaming), ("youtube", .streaming),
        ("folksam", .insurance), ("länsförsäkringar", .insurance), ("trygg-hansa", .insurance), ("if skadeförsäkring", .insurance), ("hedvig", .insurance),
        ("sats", .gym), ("nordic wellness", .gym), ("fitness24seven", .gym), ("friskis", .gym),
        ("ica", .groceries), ("coop", .groceries), ("hemköp", .groceries), ("willys", .groceries), ("lidl", .groceries), ("city gross", .groceries), ("mathem", .groceries),
        ("foodora", .takeaway), ("wolt", .takeaway), ("uber eats", .takeaway), ("mcdonalds", .takeaway), ("max burgers", .takeaway), ("espresso house", .takeaway),
        ("ubr", .transport), ("uber", .transport), ("bolt", .transport), ("sl", .transport), ("sj", .transport), ("västtrafik", .transport), ("skånetrafiken", .transport), ("voi", .transport), ("circle k", .transport), ("okq8", .transport), ("preem", .transport), ("easypark", .transport),
        ("systembolaget", .entertainment), ("filmstaden", .entertainment), ("steam", .entertainment), ("ticketmaster", .entertainment),
        ("apotek", .health), ("apoteket", .health), ("kry", .health), ("vårdcentral", .health), ("folktandvården", .health),
        ("avanza", .savings), ("nordnet", .savings), ("lysa", .savings), ("opti", .savings),
        ("swish mottagen", .income), ("lön", .income), ("försäkringskassan", .income), ("skatteverket", .income),
    ] as [(String, DefaultCategory)]).map { KeywordRule(keyword: $0.0, categoryID: $0.1.rawValue) }
}
