import EditorCoreUIFFI

enum AttoLspFoldingRangesSupport {
    enum Availability: Equatable {
        case available
        case unsupported
        case unknown
    }

    static let unsupportedMessage =
        "Folding ranges are unavailable.\nThe active LSP server does not advertise textDocument/foldingRange."

    static func availability(status: EcuLspStatusSnapshot) -> Availability {
        guard let capabilities = status.capabilities else { return .unknown }
        return capabilities.foldingRanges ? .available : .unsupported
    }
}
