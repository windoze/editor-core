import Foundation
@testable import AttoEditor
import XCTest

@MainActor
extension AttoConfigurationSettingsTests {
    func testScopedSettingsMatchGlobFileExtensionAndBareLanguageSelectors() {
        let swiftContext = AttoConfigurationDocumentContext(
            fileURL: URL(fileURLWithPath: "/tmp/project/Sources/View.SWIFT"),
            languageId: "swift"
        )
        let markdownContext = AttoConfigurationDocumentContext(
            fileURL: URL(fileURLWithPath: "/tmp/project/Docs/README.md"),
            languageId: "markdown"
        )

        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["path:**/sources/*.swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["ext:swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["filename:readme.md"]).matches(markdownContext))
        XCTAssertFalse(AttoScopedConfigurationSettings(selectors: ["source.swift"]).matches(markdownContext))
    }

    func testScopedSettingsSupportSublimeSelectorGrammar() {
        let swiftContext = AttoConfigurationDocumentContext(
            fileURL: URL(fileURLWithPath: "/tmp/project/Sources/View.swift"),
            languageId: "swift",
            scopeName: "source.swift meta.function entity.name.function"
        )
        let markdownContext = AttoConfigurationDocumentContext(
            fileURL: URL(fileURLWithPath: "/tmp/project/Docs/README.md"),
            languageId: "markdown",
            scopeName: "text.html.markdown markup.heading"
        )

        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["source.swift meta.function"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["source.rust, source.swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["source.rust | source.swift"]).matches(swiftContext))
        XCTAssertTrue(
            AttoScopedConfigurationSettings(
                selectors: ["(source.rust | source.swift) path:**/sources/*.swift"]
            ).matches(swiftContext)
        )
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["source.swift - comment"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["scope:entity.name.function"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["text.html"]).matches(markdownContext))
        XCTAssertFalse(AttoScopedConfigurationSettings(selectors: ["source.swift - meta.function"]).matches(swiftContext))
        XCTAssertFalse(
            AttoScopedConfigurationSettings(
                selectors: ["(source.rust | text.html) path:**/sources/*.swift"]
            ).matches(swiftContext)
        )
        XCTAssertFalse(AttoScopedConfigurationSettings(selectors: ["source.swift"]).matches(markdownContext))
    }
}
