import XCTest
@testable import KopieCore

final class ColorParserTests: XCTestCase {

    func test_hex_forms() {
        XCTAssertEqual(ColorParser.parse("#4F46E5")?.hexString, "4F46E5")
        XCTAssertEqual(ColorParser.parse("4f46e5")?.hexString, "4F46E5")
        let alpha = ColorParser.parse("#4F46E5CC")
        XCTAssertEqual(alpha?.hexString, "4F46E5")
        XCTAssertEqual(alpha?.alpha ?? 0, 204.0 / 255.0, accuracy: 0.001)
    }

    func test_hex_rejectsWrongLengths() {
        XCTAssertNil(ColorParser.parse("#4F46E"))
        XCTAssertNil(ColorParser.parse("#4F46E5555"))
        XCTAssertNil(ColorParser.parse("#GGGGGG"))
    }

    func test_rgb_forms_commas_and_spaces() {
        let comma = ColorParser.parse("rgb(79, 70, 229)")
        XCTAssertEqual(comma?.hexString, "4F46E5")
        let spaced = ColorParser.parse("rgb(79 70 229)")
        XCTAssertEqual(spaced?.hexString, "4F46E5")
        let rgba = ColorParser.parse("rgba(79, 70, 229, 0.5)")
        XCTAssertEqual(rgba?.hexString, "4F46E5")
        XCTAssertEqual(rgba?.alpha ?? 0, 0.5, accuracy: 0.001)
    }

    func test_rgb_rejectsOutOfRange() {
        XCTAssertNil(ColorParser.parse("rgb(300, 70, 229)"))
        XCTAssertNil(ColorParser.parse("rgba(79, 70, 229, 2)"))
    }

    func test_hsl_roundTrips() {
        let v = ColorParser.parse("hsl(243, 75%, 59%)")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.hslString, "hsl(243, 75%, 59%)")
        // Round-trip through the conversion lands back near the same hex.
        let rgb = ColorParser.hslToRgb(h: 243, s: 0.75, l: 0.59)
        XCTAssertEqual(Int(round(rgb.r * 255)), 79, accuracy: 2)
        XCTAssertEqual(Int(round(rgb.b * 255)), 229, accuracy: 2)
    }

    func test_nonColorText_rejected() {
        XCTAssertNil(ColorParser.parse("my favorite number is #4F46E5 today"))
        XCTAssertNil(ColorParser.parse("4F46E5 is indigo"))
        XCTAssertNil(ColorParser.parse("hello"))
        XCTAssertNil(ColorParser.parse("12345678"))
    }

    func test_bareSixHex_onlyWhenAlone() {
        XCTAssertNotNil(ColorParser.parse("4F46E5"))
        XCTAssertNil(ColorParser.parse("commit 4F46E5 fixed"))
    }

    func test_outputStrings() {
        let v = ColorParser.parse("#4F46E5")!
        XCTAssertEqual(v.rgbString, "rgb(79, 70, 229)")
        XCTAssertTrue(v.hslString.hasPrefix("hsl("))
        let translucent = ColorParser.parse("rgba(79, 70, 229, 0.5)")!
        XCTAssertTrue(translucent.rgbString.contains("0.50"))
    }

    func test_blackWhite_and_knownHues() {
        XCTAssertEqual(ColorParser.parse("#000000")?.hexString, "000000")
        XCTAssertEqual(ColorParser.parse("#FFFFFF")?.hexString, "FFFFFF")
        // Pure red in HSL is hsl(0, 100%, 50%).
        let red = ColorParser.parse("hsl(0, 100%, 50%)")
        XCTAssertEqual(red?.hexString, "FF0000")
    }
}
