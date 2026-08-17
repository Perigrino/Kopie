import Foundation
import CryptoKit
import KopieCore

/// AES-256-GCM with a fixed key — deterministic and Keychain-free, for tests.
struct InMemoryHistoryCrypto: HistoryCrypto {
    private let key = SymmetricKey(data: Data(repeating: 0x2A, count: 32))

    func encrypt(_ data: Data) throws -> Data {
        try AES.GCM.seal(data, using: key).combined!
    }

    func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}
