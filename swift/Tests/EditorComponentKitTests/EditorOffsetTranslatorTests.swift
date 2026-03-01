import XCTest
@testable import EditorComponentKit

final class EditorOffsetTranslatorTests: XCTestCase {
    func testScalarToUTF16ConversionHandlesEmojiAndCombiningMarks() {
        let text = "a🙂e\u{301}\n"
        let translator = EditorOffsetTranslator(text: text)

        XCTAssertEqual(translator.scalarCount, 5)
        XCTAssertEqual(translator.utf16Count, 6)

        XCTAssertEqual(translator.utf16Offset(forScalarOffset: 0), 0)
        XCTAssertEqual(translator.utf16Offset(forScalarOffset: 1), 1) // a
        XCTAssertEqual(translator.utf16Offset(forScalarOffset: 2), 3) // 🙂 (surrogate pair)
        XCTAssertEqual(translator.utf16Offset(forScalarOffset: 3), 4) // e
        XCTAssertEqual(translator.utf16Offset(forScalarOffset: 4), 5) // combining mark
        XCTAssertEqual(translator.utf16Offset(forScalarOffset: 5), 6) // newline/end
    }

    func testUTF16ToScalarConversionClampsAndMapsBoundaries() {
        let text = "🙂x"
        let translator = EditorOffsetTranslator(text: text)

        XCTAssertEqual(translator.scalarOffset(forUTF16Offset: -1), 0)
        XCTAssertEqual(translator.scalarOffset(forUTF16Offset: 0), 0)
        XCTAssertEqual(translator.scalarOffset(forUTF16Offset: 1), 0) // mid-surrogate
        XCTAssertEqual(translator.scalarOffset(forUTF16Offset: 2), 1) // end of 🙂
        XCTAssertEqual(translator.scalarOffset(forUTF16Offset: 3), 2)
        XCTAssertEqual(translator.scalarOffset(forUTF16Offset: 999), 2)
    }
}
