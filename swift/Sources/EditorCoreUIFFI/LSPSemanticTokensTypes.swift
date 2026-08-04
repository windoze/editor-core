public enum EcuLspSemanticTokensResultShape: String, Equatable, Sendable {
    case none
    case tokens
    case delta
}

public enum EcuLspSemanticTokensDeltaError: Error, Equatable, CustomStringConvertible {
    case indexOverflow(UInt32)
    case editOutOfBounds(start: UInt32, deleteCount: UInt32, count: Int)

    public var description: String {
        switch self {
        case let .indexOverflow(value):
            return "semantic token delta index overflows Int: \(value)"
        case let .editOutOfBounds(start, deleteCount, count):
            return "semantic token delta edit is out of bounds: start=\(start), deleteCount=\(deleteCount), count=\(count)"
        }
    }
}

public struct EcuLspSemanticTokensResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspSemanticTokensResultShape
    public var resultId: String?
    public var data: [UInt32]
    public var edits: [EcuLspSemanticTokensEdit]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        switch shape {
        case .none:
            return true
        case .tokens:
            return data.isEmpty
        case .delta:
            return edits.isEmpty
        }
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            resultId = nil
            data = []
            edits = []
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
        if container.contains(.edits) {
            shape = .delta
            data = []
            edits = try container.decodeIfPresent([EcuLspSemanticTokensEdit].self, forKey: .edits) ?? []
        } else {
            shape = .tokens
            data = try container.decodeIfPresent([UInt32].self, forKey: .data) ?? []
            edits = []
        }
    }

    public func dataForApplying(baseline: [UInt32] = []) throws -> [UInt32] {
        switch shape {
        case .none:
            return []
        case .tokens:
            return data
        case .delta:
            var next = baseline
            for edit in edits {
                let start = try edit.checkedStartIndex()
                let deleteCount = try edit.checkedDeleteCount()
                guard start <= next.count, deleteCount <= next.count - start else {
                    throw EcuLspSemanticTokensDeltaError.editOutOfBounds(
                        start: edit.start,
                        deleteCount: edit.deleteCount,
                        count: next.count
                    )
                }
                next.replaceSubrange(start..<(start + deleteCount), with: edit.data)
            }
            return next
        }
    }

    private enum CodingKeys: String, CodingKey {
        case resultId
        case data
        case edits
    }
}

public struct EcuLspSemanticTokensEdit: Equatable, Sendable, Decodable {
    public var start: UInt32
    public var deleteCount: UInt32
    public var data: [UInt32]
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(UInt32.self, forKey: .start)
        deleteCount = try container.decode(UInt32.self, forKey: .deleteCount)
        data = try container.decodeIfPresent([UInt32].self, forKey: .data) ?? []
    }

    fileprivate func checkedStartIndex() throws -> Int {
        guard let value = Int(exactly: start) else {
            throw EcuLspSemanticTokensDeltaError.indexOverflow(start)
        }
        return value
    }

    fileprivate func checkedDeleteCount() throws -> Int {
        guard let value = Int(exactly: deleteCount) else {
            throw EcuLspSemanticTokensDeltaError.indexOverflow(deleteCount)
        }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case deleteCount
        case data
    }
}
