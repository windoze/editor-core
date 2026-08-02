public enum EcuLspLocationResultShape: String, Equatable, Sendable {
    case none
    case location
    case locationLink = "location_link"
    case locationArray = "location_array"
    case locationLinkArray = "location_link_array"
    case mixedArray = "mixed_array"
}

public struct EcuLspLocationResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspLocationResultShape
    public var locations: [EcuLspLocation]
    public var locationLinks: [EcuLspLocationLink]
    public var raw: EcuJSONValue?
    private var orderedTargets: [EcuLspLocationTarget]

    public var targets: [EcuLspLocationTarget] {
        orderedTargets
    }

    public var isEmpty: Bool {
        locations.isEmpty && locationLinks.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            locations = []
            locationLinks = []
            orderedTargets = []
            return
        }

        if let location = try? single.decode(EcuLspLocation.self) {
            shape = .location
            locations = [location]
            locationLinks = []
            orderedTargets = [location.target]
            return
        }

        if let link = try? single.decode(EcuLspLocationLink.self) {
            shape = .locationLink
            locations = []
            locationLinks = [link]
            orderedTargets = [link.target]
            return
        }

        let elements = try single.decode([EcuLspLocationElement].self)
        locations = elements.compactMap(\.location)
        locationLinks = elements.compactMap(\.locationLink)
        orderedTargets = elements.map(\.target)
        if locationLinks.isEmpty {
            shape = .locationArray
        } else if locations.isEmpty {
            shape = .locationLinkArray
        } else {
            shape = .mixedArray
        }
    }
}

public struct EcuLspLocation: Equatable, Sendable, Decodable {
    public var uri: String
    public var range: EcuLspRange
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        range = try container.decode(EcuLspRange.self, forKey: .range)
    }

    private enum CodingKeys: String, CodingKey {
        case uri
        case range
    }
}

public struct EcuLspLocationLink: Equatable, Sendable, Decodable {
    public var originSelectionRange: EcuLspRange?
    public var targetUri: String
    public var targetRange: EcuLspRange
    public var targetSelectionRange: EcuLspRange
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originSelectionRange = try container.decodeIfPresent(EcuLspRange.self, forKey: .originSelectionRange)
        targetUri = try container.decode(String.self, forKey: .targetUri)
        targetRange = try container.decode(EcuLspRange.self, forKey: .targetRange)
        targetSelectionRange = try container.decode(EcuLspRange.self, forKey: .targetSelectionRange)
    }

    private enum CodingKeys: String, CodingKey {
        case originSelectionRange
        case targetUri
        case targetRange
        case targetSelectionRange
    }
}

public enum EcuLspLocationTargetSourceKind: String, Equatable, Sendable {
    case location
    case locationLink = "location_link"
}

public struct EcuLspLocationTarget: Equatable, Sendable {
    public var uri: String
    public var range: EcuLspRange
    public var selectionRange: EcuLspRange
    public var sourceKind: EcuLspLocationTargetSourceKind
}

private struct EcuLspLocationElement: Decodable {
    var location: EcuLspLocation?
    var locationLink: EcuLspLocationLink?
    var target: EcuLspLocationTarget

    init(from decoder: Decoder) throws {
        if let location = try? EcuLspLocation(from: decoder) {
            self.location = location
            locationLink = nil
            target = location.target
            return
        }
        location = nil
        let link = try EcuLspLocationLink(from: decoder)
        locationLink = link
        target = link.target
    }
}

private extension EcuLspLocation {
    var target: EcuLspLocationTarget {
        EcuLspLocationTarget(
            uri: uri,
            range: range,
            selectionRange: range,
            sourceKind: .location
        )
    }
}

private extension EcuLspLocationLink {
    var target: EcuLspLocationTarget {
        EcuLspLocationTarget(
            uri: targetUri,
            range: targetRange,
            selectionRange: targetSelectionRange,
            sourceKind: .locationLink
        )
    }
}
