import Foundation
import Security

/// Secrets live here and nowhere else: the RSA key, the Enable Banking application id, the session id.
/// Everything is "when unlocked, this device only": never backed up, never synced, gone with the phone.
enum Keychain {
    enum Item: String { case applicationID, sessionID, authState, accountUID }

    private static let service = "com.carlelelid.tjugofemte"
    private static let keyTag = Data("com.carlelelid.tjugofemte.rsa".utf8)

    enum Failure: Error { case status(OSStatus), keyGeneration(String) }

    // MARK: Strings

    static func string(_ item: Item) -> String? {
        var query = baseQuery(item)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String?, for item: Item) throws {
        SecItemDelete(baseQuery(item) as CFDictionary)
        guard let value else { return }
        var attrs = baseQuery(item)
        attrs[kSecValueData] = Data(value.utf8)
        attrs[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    private static func baseQuery(_ item: Item) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: item.rawValue]
    }

    // MARK: RSA key

    static func privateKey() -> SecKey? {
        let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag, kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecReturnRef: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return (result as! SecKey)
    }

    /// RSA-4096 to match Enable Banking's own example. Generated once, stored permanently, never exported.
    static func generatePrivateKey() throws -> SecKey {
        deletePrivateKey()
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 4096,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: keyTag,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as [CFString: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw Failure.keyGeneration(error!.takeRetainedValue().localizedDescription)
        }
        return key
    }

    static func deletePrivateKey() {
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag] as CFDictionary)
    }

    static func wipe() {
        deletePrivateKey()
        for item in [Item.applicationID, .sessionID, .authState, .accountUID] {
            SecItemDelete(baseQuery(item) as CFDictionary)
        }
    }
}
