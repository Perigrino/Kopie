import Foundation
import CryptoKit
import Security

/// Errors raised when the Keychain cannot provide the encryption key.
public enum HistoryCryptoError: Error {
    case keychainUnavailable
    case encryptFailed
}

/// Encrypts/decrypts clipboard history at rest: the `text_content` column of
/// the SQLite store and the image/thumbnail files on disk.
public protocol HistoryCrypto {
    /// Encrypts `data`. The exact output layout is implementation-defined but
    /// must be self-describing enough for `decrypt` to recover the input.
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) -> Data?

    /// Deterministic keyed hashes of the text's trigram shingles, used to build
    /// a searchable index without storing plaintext — search never decrypts
    /// non-matching rows. Must be stable across launches for the same text.
    func searchTokens(for text: String) -> [Data]
}

/// AES-256-GCM with a random 256-bit key stored in the Keychain.
///
/// Output layout: 12-byte nonce || ciphertext || 16-byte tag. GCM provides
/// authenticated encryption, so a tampered or truncated blob fails to decrypt
/// instead of yielding garbage.
public final class KeychainHistoryCrypto: HistoryCrypto {
    public static let keychainService = "com.kopie.app"
    public static let keychainAccount = "history-encryption-key"

    private let key: SymmetricKey
    /// Separate key for the search index (derived, never stored separately).
    private let searchKey: SymmetricKey

    /// Loads the existing key, or creates and stores a new one on first use.
    /// Throws only if the Keychain is unavailable and no key can be created.
    public init() throws {
        guard let k = Self.loadOrCreateKey() else { throw HistoryCryptoError.keychainUnavailable }
        self.key = k
        self.searchKey = Self.deriveSearchKey(from: k)
    }

    private static func deriveSearchKey(from key: SymmetricKey) -> SymmetricKey {
        let material = key.withUnsafeBytes { Data($0) } + Data("kopie-search-index".utf8)
        return SymmetricKey(data: SHA256.hash(data: material))
    }

    private static func loadOrCreateKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }

        var keyData = Data(count: 32)
        let rc = keyData.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard rc == errSecSuccess else { return nil }

        // AfterFirstUnlock so the key is readable when Kopie launches at login.
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return SymmetricKey(data: keyData)
    }

    public func encrypt(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw HistoryCryptoError.encryptFailed
        }
        return combined
    }

    public func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    public func searchTokens(for text: String) -> [Data] {
        SearchTokens.shingles(SearchTokens.normalize(text)).map { SearchTokens.hmac($0, key: searchKey) }
    }
}

/// Trigram shingles + keyed hashing for the encrypted search index.
public enum SearchTokens {
    /// Case- and diacritic-insensitive normalization, matching the behavior of
    /// the in-memory substring filter used to verify candidates.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    /// All 3-character shingles of the normalized text (spaces count, so word
    /// boundaries are preserved). Strings shorter than 3 characters produce no
    /// shingles; searches for such short queries fall back to plain filtering.
    public static func shingles(_ normalized: String) -> [String] {
        let chars = Array(normalized)
        guard chars.count >= 3 else { return [] }
        return (0...(chars.count - 3)).map { String(chars[$0..<$0 + 3]) }
    }

    public static func hmac(_ shingle: String, key: SymmetricKey) -> Data {
        HMAC<SHA256>.authenticationCode(for: Data(shingle.utf8), using: key)
            .withUnsafeBytes { Data($0) }
    }
}

/// Encoding of a text value in the `text_content` column. Schema-compatible:
/// the column stays TEXT; encrypted values carry a marker prefix so legacy
/// plaintext rows (and plaintext mode without a key) are still readable.
public enum AtRestText {
    public static let marker = "enc:v1:"

    public static func isEncrypted(_ stored: String) -> Bool { stored.hasPrefix(marker) }

    public static func encode(_ plain: String, crypto: HistoryCrypto) throws -> String {
        marker + (try crypto.encrypt(Data(plain.utf8))).base64EncodedString()
    }

    /// Returns the plaintext for a stored value. Legacy plaintext rows pass
    /// through untouched; malformed encrypted values fall back to the stored
    /// string so history never bricks over a bad row.
    public static func decode(_ stored: String, crypto: HistoryCrypto) -> String {
        guard isEncrypted(stored),
              let payload = Data(base64Encoded: String(stored.dropFirst(marker.count))),
              let data = crypto.decrypt(payload),
              let plain = String(data: data, encoding: .utf8) else {
            return stored
        }
        return plain
    }
}
