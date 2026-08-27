import XCTest
import KopieCore

final class ContentDetectorTests: XCTestCase {

    func test_plainProseIsNotCode() {
        // Normal multi-line prose must stay plain text.
        let prose = """
        The little fox ran across the stream.
        It was a bright and sunny afternoon.
        Everyone waved as the boat went by.
        """
        if case .plainText = ContentDetector.detectContentType(prose) {
            // ok
        } else {
            XCTFail("expected plainText, got \(ContentDetector.detectContentType(prose))")
        }
    }

    func test_urlDetected() {
        if case .url = ContentDetector.detectContentType("https://example.com/page") {
            // ok
        } else {
            XCTFail("expected .url")
        }
    }

    func test_emailDetected() {
        if case .email = ContentDetector.detectContentType("hello@example.com") {
            // ok
        } else {
            XCTFail("expected .email")
        }
    }

    func test_phoneNumberDetected() {
        if case .phoneNumber = ContentDetector.detectContentType("(555) 123-4567") {
            // ok
        } else {
            XCTFail("expected .phoneNumber")
        }
    }

    func test_plainTextFallback() {
        if case .plainText = ContentDetector.detectContentType("just some ordinary prose here") {
            // ok
        } else {
            XCTFail("expected plainText")
        }
    }
}
