import Foundation
import Security

/// Signs Enable Banking JWTs. Today: an RSA key on this phone. A commercial setup would add a remote signer.
public protocol TokenSigner: Sendable {
    /// Enable Banking application id, sent as the JWT `kid`.
    var keyID: String { get }
    func sign(_ message: Data) throws -> Data
}

public enum SigningError: Error {
    case keyGeneration(String)
    case signing(String)
    case export(String)
}

/// RSA private key wrapped as a signer. The key lives wherever the SecKey came from
/// (ephemeral in tests, Keychain in the app).
public final class RSAKey: TokenSigner, @unchecked Sendable {
    public let keyID: String
    public let privateKey: SecKey

    public init(privateKey: SecKey, keyID: String) {
        self.privateKey = privateKey
        self.keyID = keyID
    }

    /// In-memory key, never persisted. For tests and previews.
    public static func ephemeral(bits: Int, keyID: String) throws -> RSAKey {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SigningError.keyGeneration(error!.takeRetainedValue().localizedDescription)
        }
        return RSAKey(privateKey: key, keyID: keyID)
    }

    public func sign(_ message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) else {
            throw SigningError.signing(error!.takeRetainedValue().localizedDescription)
        }
        return signature as Data
    }

    /// SubjectPublicKeyInfo PEM, the format the Enable Banking control panel expects.
    /// SecKey exports PKCS#1, so the RSA algorithm identifier is wrapped around it here.
    public func publicKeyPEM() throws -> String {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw SigningError.export(error?.takeRetainedValue().localizedDescription ?? "no public key")
        }
        let rsaAlgorithm: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
        let bitString = DER.tag(0x03, Data([0x00]) + pkcs1)
        let spki = DER.tag(0x30, Data(rsaAlgorithm) + bitString)
        let body = spki.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(body)\n-----END PUBLIC KEY-----\n"
    }
}

enum DER {
    static func tag(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            let bytes = withUnsafeBytes(of: UInt(n).bigEndian, Array.init).drop { $0 == 0 }
            out.append(0x80 | UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        return out + content
    }
}
