import Foundation

@frozen
public struct ViewportBlobHeader: Equatable, Sendable {
    public var abiVersion: UInt32
    public var headerSize: UInt32
    public var lineCount: UInt32
    public var cellCount: UInt32
    public var styleIdCount: UInt32
    public var linesOffset: UInt32
    public var cellsOffset: UInt32
    public var styleIdsOffset: UInt32
    public var reserved: UInt32

    public init() {
        self.abiVersion = 0
        self.headerSize = 0
        self.lineCount = 0
        self.cellCount = 0
        self.styleIdCount = 0
        self.linesOffset = 0
        self.cellsOffset = 0
        self.styleIdsOffset = 0
        self.reserved = 0
    }
}

@frozen
public struct ViewportBlobLine: Equatable, Sendable {
    public var logicalLineIndex: UInt32
    public var visualInLogical: UInt32
    public var charOffsetStart: UInt32
    public var charOffsetEnd: UInt32
    public var cellStartIndex: UInt32
    public var cellCount: UInt32
    public var segmentXStartCells: UInt16
    public var isWrappedPart: UInt8
    public var isFoldPlaceholderAppended: UInt8

    public init() {
        self.logicalLineIndex = 0
        self.visualInLogical = 0
        self.charOffsetStart = 0
        self.charOffsetEnd = 0
        self.cellStartIndex = 0
        self.cellCount = 0
        self.segmentXStartCells = 0
        self.isWrappedPart = 0
        self.isFoldPlaceholderAppended = 0
    }
}

@frozen
public struct ViewportBlobCell: Equatable, Sendable {
    public var scalarValue: UInt32
    public var width: UInt16
    public var styleCount: UInt16
    public var styleStartIndex: UInt32

    public init() {
        self.scalarValue = 0
        self.width = 0
        self.styleCount = 0
        self.styleStartIndex = 0
    }
}

public struct ViewportBlob: Equatable, Sendable {
    public let header: ViewportBlobHeader
    public let lines: [ViewportBlobLine]
    public let cells: [ViewportBlobCell]
    public let styleIds: [UInt32]

    public init(data: Data) throws {
        let headerSize = MemoryLayout<ViewportBlobHeader>.size
        guard data.count >= headerSize else {
            throw EditorCoreFFIError.invalidViewportBlob(reason: "too small for header: \(data.count) < \(headerSize)")
        }

        var header = ViewportBlobHeader()
        _ = withUnsafeMutableBytes(of: &header) { dst in
            data.copyBytes(to: dst, from: 0..<dst.count)
        }

        let expectedHeaderSize = UInt32(headerSize)
        guard header.headerSize == expectedHeaderSize else {
            throw EditorCoreFFIError.invalidViewportBlob(
                reason: "unexpected header_size: \(header.headerSize) (expected \(expectedHeaderSize))"
            )
        }

        func checkedOffset(_ offset: UInt32, label: String) throws -> Int {
            let off = Int(offset)
            guard off >= 0 && off <= data.count else {
                throw EditorCoreFFIError.invalidViewportBlob(reason: "\(label) out of range: \(off) (data.count=\(data.count))")
            }
            return off
        }

        let linesOffset = try checkedOffset(header.linesOffset, label: "lines_offset")
        let cellsOffset = try checkedOffset(header.cellsOffset, label: "cells_offset")
        let styleIdsOffset = try checkedOffset(header.styleIdsOffset, label: "style_ids_offset")

        let lineRecordSize = MemoryLayout<ViewportBlobLine>.size
        let cellRecordSize = MemoryLayout<ViewportBlobCell>.size

        let lineCount = Int(header.lineCount)
        let cellCount = Int(header.cellCount)
        let styleIdCount = Int(header.styleIdCount)

        let linesEnd = linesOffset + (lineCount * lineRecordSize)
        let cellsEnd = cellsOffset + (cellCount * cellRecordSize)
        let styleIdsEnd = styleIdsOffset + (styleIdCount * MemoryLayout<UInt32>.size)

        guard linesEnd <= data.count else {
            throw EditorCoreFFIError.invalidViewportBlob(reason: "lines table out of range: end=\(linesEnd), data.count=\(data.count)")
        }
        guard cellsEnd <= data.count else {
            throw EditorCoreFFIError.invalidViewportBlob(reason: "cells table out of range: end=\(cellsEnd), data.count=\(data.count)")
        }
        guard styleIdsEnd <= data.count else {
            throw EditorCoreFFIError.invalidViewportBlob(reason: "style ids out of range: end=\(styleIdsEnd), data.count=\(data.count)")
        }

        var lines: [ViewportBlobLine] = []
        lines.reserveCapacity(lineCount)
        for i in 0..<lineCount {
            let offset = linesOffset + (i * lineRecordSize)
            var record = ViewportBlobLine()
            _ = withUnsafeMutableBytes(of: &record) { dst in
                data.copyBytes(to: dst, from: offset..<(offset + dst.count))
            }
            lines.append(record)
        }

        var cells: [ViewportBlobCell] = []
        cells.reserveCapacity(cellCount)
        for i in 0..<cellCount {
            let offset = cellsOffset + (i * cellRecordSize)
            var record = ViewportBlobCell()
            _ = withUnsafeMutableBytes(of: &record) { dst in
                data.copyBytes(to: dst, from: offset..<(offset + dst.count))
            }
            cells.append(record)
        }

        var styleIds: [UInt32] = []
        styleIds.reserveCapacity(styleIdCount)
        for i in 0..<styleIdCount {
            let offset = styleIdsOffset + (i * MemoryLayout<UInt32>.size)
            var id: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &id) { dst in
                data.copyBytes(to: dst, from: offset..<(offset + dst.count))
            }
            styleIds.append(id)
        }

        self.header = header
        self.lines = lines
        self.cells = cells
        self.styleIds = styleIds
    }
}
