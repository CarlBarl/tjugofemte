import Foundation

public enum JWT {
    /// RS256 token as Enable Banking specifies: kid = application id, iss/aud fixed, one hour validity.
    public static func make(signer: TokenSigner, now: Date = Date()) throws -> String {
        let iat = Int(now.timeIntervalSince1970)
        let header: [String: Any] = ["typ": "JWT", "alg": "RS256", "kid": signer.keyID]
        let claims: [String: Any] = ["iss": "enablebanking.com", "aud": "api.enablebanking.com", "iat": iat, "exp": iat + 3600]
        let signingInput = try json(header) + "." + json(claims)
        let signature = try signer.sign(Data(signingInput.utf8))
        return signingInput + "." + Base64URL.encode(signature)
    }

    private static func json(_ object: [String: Any]) throws -> String {
        Base64URL.encode(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
}

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}
