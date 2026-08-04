import Foundation

public enum EcuLspDocumentColorResultShape: String, Equatable, Sendable {
    case none
    case colorInformationArray = "color_information_array"
}

public struct EcuLspDocumentColorResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspDocumentColorResultShape
    public var items: [EcuLspColorInformation]
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        items.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            items = []
            return
        }

        shape = .colorInformationArray
        items = try single.decode([EcuLspColorInformation].self)
    }
}

public struct EcuLspColorInformation: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var color: EcuLspColor
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        color = try container.decode(EcuLspColor.self, forKey: .color)
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case color
    }
}

public struct EcuLspColor: Equatable, Sendable, Decodable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
}

public enum EcuLspColorPresentationResultShape: String, Equatable, Sendable {
    case none
    case colorPresentationArray = "color_presentation_array"
}

public struct EcuLspColorPresentationResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspColorPresentationResultShape
    public var presentations: [EcuLspColorPresentation]
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        presentations.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            presentations = []
            return
        }

        shape = .colorPresentationArray
        presentations = try single.decode([EcuLspColorPresentation].self)
    }
}

public struct EcuLspColorPresentation: Equatable, Sendable, Decodable {
    public var label: String
    public var textEdit: EcuLspTextEdit?
    public var additionalTextEdits: [EcuLspTextEdit]
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        textEdit = try container.decodeIfPresent(EcuLspTextEdit.self, forKey: .textEdit)
        additionalTextEdits = try container.decodeIfPresent(
            [EcuLspTextEdit].self,
            forKey: .additionalTextEdits
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case textEdit
        case additionalTextEdits
    }
}
