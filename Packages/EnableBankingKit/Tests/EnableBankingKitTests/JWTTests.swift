import Testing
import Foundation
import Security
@testable import EnableBankingKit

@Suite struct JWTTests {
    let key = try! RSAKey.ephemeral(bits: 2048, keyID: "app-123")
    let now = Date(timeIntervalSince1970: 1_760_700_000)

    func part(_ token: String, _ index: Int) -> [String: Any] {
        let segment = token.split(separator: ".")[index]
        return try! JSONSerialization.jsonObject(with: Base64URL.decode(String(segment))!) as! [String: Any]
    }

    @Test func headerNamesTheApplicationAsKeyID() throws {
        let token = try JWT.make(signer: key, now: now)
        let header = part(token, 0)
        #expect(header["typ"] as? String == "JWT")
        #expect(header["alg"] as? String == "RS256")
        #expect(header["kid"] as? String == "app-123")
    }

    @Test func claimsMatchEnableBankingAndExpireInOneHour() throws {
        let claims = part(try JWT.make(signer: key, now: now), 1)
        #expect(claims["iss"] as? String == "enablebanking.com")
        #expect(claims["aud"] as? String == "api.enablebanking.com")
        #expect(claims["iat"] as? Int == 1_760_700_000)
        #expect(claims["exp"] as? Int == 1_760_703_600)
    }

    @Test func signatureVerifiesWithThePublicKey() throws {
        let token = try JWT.make(signer: key, now: now)
        let parts = token.split(separator: ".").map(String.init)
        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        let signature = Base64URL.decode(parts[2])!
        let publicKey = SecKeyCopyPublicKey(key.privateKey)!
        #expect(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil))
    }

    @Test func base64URLHasNoPaddingOrUnsafeCharacters() {
        let encoded = Base64URL.encode(Data([0xfb, 0xff, 0xfe, 0x01]))
        #expect(!encoded.contains("=") && !encoded.contains("+") && !encoded.contains("/"))
        #expect(Base64URL.decode(encoded) == Data([0xfb, 0xff, 0xfe, 0x01]))
    }
}
