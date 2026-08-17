import XCTest
import KopieCore

final class HistoryCryptoTests: XCTestCase {
    func test_roundtrip() throws {
        let c = InMemoryHistoryCrypto()
        let d = Data("secret clipboard text".utf8)
        let enc = try c.encrypt(d)
        XCTAssertNotEqual(enc, d)
        XCTAssertEqual(c.decrypt(enc), d)
    }

    func test_tamperedCiphertextFails() throws {
        let c = InMemoryHistoryCrypto()
        var enc = try c.encrypt(Data("payload".utf8))
        enc[enc.count - 1] ^= 0xFF
        XCTAssertNil(c.decrypt(enc))
    }

    func test_truncatedCiphertextFails() throws {
        let c = InMemoryHistoryCrypto()
        let enc = try c.encrypt(Data("payload".utf8))
        XCTAssertNil(c.decrypt(enc.prefix(enc.count - 5)))
    }

    func test_atRestTextMarker() throws {
        let c = InMemoryHistoryCrypto()
        let stored = try AtRestText.encode("hello", crypto: c)
        XCTAssertTrue(AtRestText.isEncrypted(stored))
        XCTAssertFalse(stored.contains("hello"))
        XCTAssertEqual(AtRestText.decode(stored, crypto: c), "hello")

        // Legacy plaintext passes through untouched.
        XCTAssertEqual(AtRestText.decode("plain legacy", crypto: c), "plain legacy")
        // Malformed encrypted values fall back to the stored string, never crash.
        XCTAssertEqual(AtRestText.decode("enc:v1:!!!not-base64!!!", crypto: c), "enc:v1:!!!not-base64!!!")
    }
}
