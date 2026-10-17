import Testing
import Foundation
@testable import EnableBankingKit

@Suite struct PublicKeyPEMTests {
    let key = try! RSAKey.ephemeral(bits: 2048, keyID: "app-123")

    @Test func exportsSubjectPublicKeyInfoPEM() throws {
        let pem = try key.publicKeyPEM()
        #expect(pem.hasPrefix("-----BEGIN PUBLIC KEY-----\n"))
        #expect(pem.hasSuffix("\n-----END PUBLIC KEY-----\n"))
        #expect(pem.split(separator: "\n").dropFirst().dropLast().allSatisfy { $0.count <= 64 })
    }

    #if os(macOS)
    @Test func opensslVerifiesASignatureUsingThePEM() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let message = Data("tjugofemte".utf8)
        try message.write(to: dir.appendingPathComponent("msg"))
        try key.sign(message).write(to: dir.appendingPathComponent("sig"))
        try key.publicKeyPEM().write(to: dir.appendingPathComponent("pub.pem"), atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = ["dgst", "-sha256", "-verify", dir.appendingPathComponent("pub.pem").path,
                       "-signature", dir.appendingPathComponent("sig").path, dir.appendingPathComponent("msg").path]
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(p.terminationStatus == 0 && text.contains("Verified OK"), "openssl said: \(text)")
    }
    #endif
}
