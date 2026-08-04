import Foundation

struct AttoLspResultOwner: Equatable {
    enum Scope: String, Equatable {
        case document
        case workspace
        case global
    }

    let scope: Scope
    let tabID: UUID?
    let coreTabID: UInt64?
    let documentURI: String?
    let workspaceRootURI: String?

    static func document(
        tabID: UUID,
        coreTabID: UInt64?,
        documentURI: String,
        workspaceRootURI: String?
    ) -> AttoLspResultOwner {
        AttoLspResultOwner(
            scope: .document,
            tabID: tabID,
            coreTabID: coreTabID,
            documentURI: documentURI,
            workspaceRootURI: workspaceRootURI
        )
    }

    static func workspace(workspaceRootURI: String?) -> AttoLspResultOwner {
        AttoLspResultOwner(
            scope: .workspace,
            tabID: nil,
            coreTabID: nil,
            documentURI: nil,
            workspaceRootURI: workspaceRootURI
        )
    }
}
