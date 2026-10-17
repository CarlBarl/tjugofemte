import Foundation

/// How much history the phone keeps. Older transactions are purged on launch.
public struct RetentionPolicy: Equatable, Sendable, Codable {
    public let months: Int

    public init(months: Int) { self.months = months }

    public static let options = [RetentionPolicy(months: 3), RetentionPolicy(months: 12), RetentionPolicy(months: 24)]

    public func cutoff(today: Date) -> Date {
        let start = Calendar.stockholm.startOfDay(for: today)
        return Calendar.stockholm.date(byAdding: .month, value: -months, to: start)!
    }

    public func shouldPurge(bookingDate: Date, today: Date) -> Bool {
        bookingDate < cutoff(today: today)
    }
}
