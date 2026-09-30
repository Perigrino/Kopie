import XCTest
@testable import KopieCore

final class JSONUtilitiesTests: XCTestCase {

    func test_prettyPrint_twoSpace() throws {
        let out = try JSONUtilities.format(#"{"a":1,"b":[2,3]}"#, as: .twoSpace)
        XCTAssertTrue(out.contains("\n"))
        XCTAssertTrue(out.contains(#""a" : 1"#))
        XCTAssertTrue(out.contains("  \"b\""))
    }

    func test_prettyPrint_fourSpace_and_tab() throws {
        let four = try JSONUtilities.format(#"{"a":{"b":1}}"#, as: .fourSpace)
        XCTAssertTrue(four.contains("    \"a\""))
        XCTAssertTrue(four.contains("        \"b\""))
        let tab = try JSONUtilities.format(#"{"a":{"b":1}}"#, as: .tab)
        XCTAssertTrue(tab.contains("\t\"a\""))
    }

    func test_minify_removesWhitespace() throws {
        let out = try JSONUtilities.format(#"{ "a" : 1, "b" : [ 2 , 3 ] }"#, as: .minified)
        XCTAssertEqual(out, #"{"a":1,"b":[2,3]}"#)
    }

    func test_invalidJSON_throwsReadableError() {
        XCTAssertThrowsError(try JSONUtilities.format("{not json", as: .twoSpace)) { error in
            guard case JSONUtilities.JSONError.invalidJSON(let msg) = error else {
                return XCTFail("wrong error \(error)")
            }
            XCTAssertFalse(msg.isEmpty)
        }
    }

    func test_emptyInput_throwsEmpty() {
        XCTAssertThrowsError(try JSONUtilities.format("   ", as: .twoSpace)) { error in
            XCTAssertEqual(error as? JSONUtilities.JSONError, .empty)
        }
    }

    func test_validate_reportsNilForValid() {
        XCTAssertNil(JSONUtilities.validate(#"{"ok":true}"#))
        XCTAssertNotNil(JSONUtilities.validate(#"{"ok":}"#))
    }

    func test_fragmentsAllowed() throws {
        // A bare number/string is valid JSON per RFC 8259 fragments.
        XCTAssertNil(JSONUtilities.validate("42"))
        let out = try JSONUtilities.format("  [1,2]  ", as: .minified)
        XCTAssertEqual(out, "[1,2]")
    }

    func test_unicodeSurvives() throws {
        let out = try JSONUtilities.format(#"{"city":"Zürich"}"#, as: .minified)
        XCTAssertTrue(out.contains("Zürich"))
    }
}
