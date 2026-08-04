enum AttoSublimeFeatureBoundary: CaseIterable {
    case runBuildSystem
    case cancelBuildSystem
    case openPackageResource
    case showQuickPanel
    case showInputPanel
    case showOutputPanel

    static var commandIDs: Set<String> {
        Set(allCases.map(\.commandID))
    }

    var commandID: String {
        switch self {
        case .runBuildSystem:
            "build.run"
        case .cancelBuildSystem:
            "build.cancel"
        case .openPackageResource:
            "package.open_resource"
        case .showQuickPanel:
            "panel.show_quick_panel"
        case .showInputPanel:
            "panel.show_input_panel"
        case .showOutputPanel:
            "panel.show_output_panel"
        }
    }

    var commandTitle: String {
        switch self {
        case .runBuildSystem:
            "Build: Run Build System"
        case .cancelBuildSystem:
            "Build: Cancel Build"
        case .openPackageResource:
            "Package: Open Resource..."
        case .showQuickPanel:
            "Panel: Show Quick Panel"
        case .showInputPanel:
            "Panel: Show Input Panel"
        case .showOutputPanel:
            "Panel: Show Output Panel"
        }
    }

    var menuTitle: String {
        switch self {
        case .runBuildSystem:
            "Run Build System"
        case .cancelBuildSystem:
            "Cancel Build"
        case .openPackageResource:
            "Open Package Resource..."
        case .showQuickPanel:
            "Show Quick Panel"
        case .showInputPanel:
            "Show Input Panel"
        case .showOutputPanel:
            "Show Output Panel"
        }
    }

    var statusText: String {
        switch self {
        case .runBuildSystem:
            "Build systems: not configured"
        case .cancelBuildSystem:
            "Build systems: no active build"
        case .openPackageResource:
            "Package resources: not loaded"
        case .showQuickPanel:
            "Quick panels: package/plugin API unavailable"
        case .showInputPanel:
            "Input panels: package/plugin API unavailable"
        case .showOutputPanel:
            "Output panels: package/plugin API unavailable"
        }
    }
}
