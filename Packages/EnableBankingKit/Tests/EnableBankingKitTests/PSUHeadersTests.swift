import Testing
import Foundation
@testable import EnableBankingKit

@Suite struct PSUHeadersTests {
    @Test func deviceAddressIsDottedQuadOrNil() {
        if let ip = PSUHeaders.deviceIPv4Address() {
            let parts = ip.split(separator: ".")
            #expect(parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } == true })
            #expect(!ip.hasPrefix("127."))
        }
    }
}
