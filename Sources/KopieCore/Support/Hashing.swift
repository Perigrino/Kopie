import Foundation
import CommonCrypto

public enum Hashing {
    /// Hex-encoded SHA-256 of `data` (used for duplicate detection).
    public static func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        if data.isEmpty {
            _ = CC_SHA256(nil, 0, &digest)
        } else {
            data.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    _ = CC_SHA256(base, CC_LONG(data.count), &digest)
                }
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
