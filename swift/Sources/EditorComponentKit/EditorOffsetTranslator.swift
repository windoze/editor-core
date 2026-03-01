import Foundation

struct EditorOffsetTranslator {
    private let scalarToUTF16: [Int]
    private let utf16ToScalar: [Int]

    let scalarCount: Int
    let utf16Count: Int

    init(text: String) {
        var scalarToUTF16: [Int] = [0]
        scalarToUTF16.reserveCapacity(text.unicodeScalars.count + 1)

        var utf16ToScalar = Array(repeating: 0, count: text.utf16.count + 1)
        var scalarOffset = 0
        var utf16Offset = 0

        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            for step in 1...width {
                utf16ToScalar[utf16Offset + step] = scalarOffset + (step == width ? 1 : 0)
            }
            utf16Offset += width
            scalarOffset += 1
            scalarToUTF16.append(utf16Offset)
        }

        self.scalarToUTF16 = scalarToUTF16
        self.utf16ToScalar = utf16ToScalar
        self.scalarCount = scalarOffset
        self.utf16Count = utf16Offset
    }

    func utf16Offset(forScalarOffset offset: Int) -> Int {
        let clamped = max(0, min(offset, scalarCount))
        return scalarToUTF16[clamped]
    }

    func scalarOffset(forUTF16Offset offset: Int) -> Int {
        let clamped = max(0, min(offset, utf16Count))
        return utf16ToScalar[clamped]
    }

    func utf16Range(startScalar: Int, endScalar: Int) -> NSRange {
        let lower = utf16Offset(forScalarOffset: min(startScalar, endScalar))
        let upper = utf16Offset(forScalarOffset: max(startScalar, endScalar))
        return NSRange(location: lower, length: upper - lower)
    }
}
