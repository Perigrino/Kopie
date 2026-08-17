import XCTest
import KopieCore

final class HashingTests: XCTestCase {
    func test_sha256_knownVector() {
        XCTAssertEqual(Hashing.sha256(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func test_sha256_empty() {
        XCTAssertEqual(Hashing.sha256(Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
    func test_canonicalTextAndImageDiffer() {
        let t = CapturedContent(kind: .text("hi"), sourceAppID: nil).canonicalData
        let i = CapturedContent(kind: .image(Data([1, 2, 3])), sourceAppID: nil).canonicalData
        XCTAssertNotEqual(Hashing.sha256(t), Hashing.sha256(i))
    }
    func test_identicalTextSameHash() {
        let a = CapturedContent(kind: .text("same"), sourceAppID: nil).canonicalData
        let b = CapturedContent(kind: .text("same"), sourceAppID: nil).canonicalData
        XCTAssertEqual(Hashing.sha256(a), Hashing.sha256(b))
    }
}
