import XCTest
import KopieCore

final class ContentDetectorTests: XCTestCase {

    func test_typescriptSnippetDetectedAsCode() {
        // A JS/TS snippet like the reference code card must route to .code.
        let snippet = """
        const post = await getPost(postId)

        if (post.deleted) return

        post.content = cleanContent(content)
        """
        guard case .code(let language) = ContentDetector.detectContentType(snippet) else {
            return XCTFail("expected .code, got \(ContentDetector.detectContentType(snippet))")
        }
        XCTAssertEqual(language, "typescript")
    }

    func test_arrowFunctionDetectedAsCode() {
        let snippet = """
        const sum = (a, b) => a + b
        const double = (n) => n * 2
        """
        guard case .code = ContentDetector.detectContentType(snippet) else {
            return XCTFail("expected .code for arrow functions")
        }
    }

    func test_plainProseIsNotCode() {
        // Normal multi-line prose (no code signatures) must stay plain text.
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

    func test_singleLineIfNotEnoughForCodeByItself() {
        // A single "if a sentence reads like..." line should not be code unless
        // additional code signals are present. One unflagged line is plain text.
        let sentence = "if you think about it the answer is simple"
        if case .plainText = ContentDetector.detectContentType(sentence) {
            // ok
        } else {
            XCTFail("expected plainText, got \(ContentDetector.detectContentType(sentence))")
        }
    }
}
