import XCTest
import KopieCore

final class CodeLanguageDetectorTests: XCTestCase {

    func testJSON() {
        let s = """
        { "message": "Success", "code": 200 }
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .json)
    }

    func testHTML() {
        let s = """
        <div class="container">
            <h1>Hello World</h1>
        </div>
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .html)
    }

    func testSwift() {
        let s = """
        struct User {
            let id: Int
            let name: String
        }
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .swift)
    }

    func testPython() {
        let s = """
        def hello(name):
            print(f"Hello {name}")
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .python)
    }

    func testSQL() {
        let s = """
        SELECT * FROM users WHERE active = true;
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .sql)
    }

    func testTypeScriptSnippet() {
        let s = """
        const post = await getPost(postId)
        if (post.deleted) return
        post.content = cleanContent(content)
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .typescript)
    }

    func testCSharpController() {
        let s = """
        [ApiController]
        public class CustomerController:Controller {
            // ...
        }
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .csharp)
    }

    func testPlainProseFallback() {
        let s = """
        The little fox ran across the stream.
        It was a bright and sunny afternoon.
        """
        XCTAssertEqual(CodeLanguageDetector.detect(content: s), .plainText)
    }

    func testFilenameHintOverridesLowConfidence() {
        XCTAssertEqual(CodeLanguageDetector.detect(content: "name: value\nage: 2", filename: "config.yaml"), .yaml)
    }

    func testFormatterPrettyPrintsJSON() {
        let raw = #"{"a":1,"b":[1,2],"c":{"d":true}}"#
        let out = CodeFormatter.format(raw, language: .json)
        XCTAssertNotEqual(out, raw)
        // Should still be valid JSON after formatting.
        let data = out.data(using: .utf8)!
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
        XCTAssertTrue(out.contains("\n"))
    }

    func testFormatterLeavesUnsafeLanguagesUntouched() {
        let raw = "func foo() {}"
        XCTAssertEqual(CodeFormatter.format(raw, language: .swift), raw)
    }
}
