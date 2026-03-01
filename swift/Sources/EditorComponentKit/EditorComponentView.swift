#if canImport(AppKit)
import AppKit

public protocol EditorComponentDelegate: AnyObject {
    func editorComponent(_ component: EditorComponentView, didFail error: EditorCommandError)
    func editorComponent(_ component: EditorComponentView, didExecute commandResult: EditorCommandResult)
}

public final class EditorComponentView: NSView {
    public weak var delegate: EditorComponentDelegate?
    public weak var hoverProvider: EditorHoverProvider? {
        didSet { updateInteractionProviders() }
    }
    public weak var contextMenuProvider: EditorContextMenuProvider? {
        didSet { updateInteractionProviders() }
    }

    public var configuration: EditorComponentConfiguration {
        didSet {
            applyConfiguration()
            refreshChrome()
        }
    }

    public var keybindingRegistry: EditorKeybindingRegistry {
        didSet {
            textView.keybindingRegistry = keybindingRegistry
        }
    }

    public weak var engine: EditorEngineProtocol? {
        didSet {
            commandDispatcher.engine = engine
            refreshChrome()
            reloadFromEngine()
        }
    }

    public var customCommandHandler: ((String, [String: String]) -> EditorCommandResult?)? {
        get { commandDispatcher.customCommandHandler }
        set { commandDispatcher.customCommandHandler = newValue }
    }

    public let scrollView: NSScrollView

    private let textView: EditorTextView
    private let gutterView: EditorGutterView
    private let minimapView: EditorMinimapView
    private let commandDispatcher: EditorCommandDispatcher
    private var foldRegions: [EditorFoldRegion] = []

    public override var isFlipped: Bool { true }

    public var currentDisplayedText: String {
        textView.string
    }

    var textViewForTesting: EditorTextView {
        textView
    }

    var minimapSnapshotForTesting: EditorMinimapSnapshot {
        minimapView.snapshot
    }

    var visibleMinimapRangeForTesting: Range<Int>? {
        minimapView.visibleVisualRange
    }

    var foldRegionsForTesting: [EditorFoldRegion] {
        foldRegions
    }

    public init(
        frame frameRect: NSRect = .zero,
        configuration: EditorComponentConfiguration = .init(),
        keybindingRegistry: EditorKeybindingRegistry = .init()
    ) {
        self.configuration = configuration
        self.keybindingRegistry = keybindingRegistry

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        self.textView = EditorTextView(frame: .zero, textContainer: textContainer)
        self.textView.isRichText = false
        self.textView.isAutomaticQuoteSubstitutionEnabled = false
        self.textView.isAutomaticDashSubstitutionEnabled = false
        self.textView.usesFindBar = true
        self.textView.allowsUndo = true
        self.textView.textContainerInset = NSSize(width: 8, height: 8)

        self.scrollView = NSScrollView(frame: .zero)
        self.scrollView.borderType = .noBorder
        self.scrollView.hasVerticalScroller = true
        self.scrollView.hasHorizontalScroller = true
        self.scrollView.autohidesScrollers = true
        self.scrollView.documentView = textView

        self.gutterView = EditorGutterView(frame: .zero)
        self.minimapView = EditorMinimapView(frame: .zero)

        self.commandDispatcher = EditorCommandDispatcher()

        super.init(frame: frameRect)

        textView.keybindingRegistry = keybindingRegistry
        textView.commandDispatcher = commandDispatcher
        commandDispatcher.observer = self
        commandDispatcher.engine = engine
        gutterView.textView = textView
        gutterView.onToggleFoldRegion = { [weak self] region in
            self?.toggleFoldRegion(region)
        }
        updateInteractionProviders()

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibleBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        addSubview(gutterView)
        addSubview(scrollView)
        addSubview(minimapView)

        applyConfiguration()
        refreshChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func layout() {
        super.layout()

        let minimapWidth: CGFloat = configuration.features.showsMinimap ? 120 : 0
        let gutterWidth: CGFloat
        if configuration.features.showsGutter {
            gutterWidth = configuration.features.showsLineNumbers ? 56 : 18
        } else {
            gutterWidth = 0
        }

        gutterView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        minimapView.frame = CGRect(
            x: bounds.width - minimapWidth,
            y: 0,
            width: minimapWidth,
            height: bounds.height
        )

        scrollView.frame = CGRect(
            x: gutterWidth,
            y: 0,
            width: max(bounds.width - gutterWidth - minimapWidth, 0),
            height: bounds.height
        )
    }

    public func dispatch(_ command: EditorCommand) {
        commandDispatcher.dispatch(command)
    }

    public func bindKey(_ chord: EditorKeyChord, to command: EditorCommand) {
        keybindingRegistry.bind(chord, command: command)
    }

    public func unbindKey(_ chord: EditorKeyChord) {
        keybindingRegistry.unbind(chord)
    }

    public func toggleFold(startLine: Int) {
        guard let region = foldRegions.first(where: { $0.startLine == startLine }) else {
            return
        }
        toggleFoldRegion(region)
    }

    public func reloadFromEngine() {
        guard let engine else {
            textView.string = ""
            gutterView.lineNumbers = []
            gutterView.foldRegions = []
            minimapView.snapshot = .init(startVisualRow: 0, requestedCount: 0, lines: [])
            minimapView.visibleVisualRange = nil
            return
        }

        do {
            let newText = engine.text
            if textView.string != newText {
                textView.string = newText
            }

            let offsetTranslator = EditorOffsetTranslator(text: newText)
            let styleSpans = try engine.styleSpans(in: 0..<offsetTranslator.scalarCount)
            let inlays = try engine.inlays(in: 0..<offsetTranslator.scalarCount)
            foldRegions = try engine.foldRegions()
            let diagnostics = try engine.diagnostics()

            textView.applyDecorations(
                styleSpans: styleSpans,
                inlays: inlays,
                foldRegions: foldRegions,
                diagnostics: diagnostics,
                visualStyle: configuration.visualStyle,
                featureFlags: configuration.features
            )

            let state = try engine.documentState()
            gutterView.lineNumbers = Array(1...max(state.lineCount, 1))
            gutterView.foldRegions = foldRegions

            if configuration.features.showsMinimap {
                minimapView.snapshot = try engine.minimapViewport(
                    .init(startVisualRow: 0, rowCount: max(state.lineCount, 1))
                )
            }

            updateViewportIndicators()
        } catch {
            delegate?.editorComponent(
                self,
                didFail: EditorCommandError("Failed to reload editor state: \(error)")
            )
        }
    }

    private func applyConfiguration() {
        let style = configuration.visualStyle
        let font = NSFont(name: style.fontName, size: style.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .regular)

        textView.font = font
        textView.defaultParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = style.lineHeightMultiplier
            p.lineBreakMode = .byCharWrapping
            return p
        }()
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.isContinuousSpellCheckingEnabled = false
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.typingAttributes[.ligature] = style.enablesLigatures ? 1 : 0
        textView.featureFlags = configuration.features

        minimapView.dominantStyleColorProvider = { [weak self] styleID in
            guard let self else {
                return nil
            }
            return self.configuration.visualStyle.stylePalette.styles[styleID]?.foreground?.nsColor
        }
    }

    private func refreshChrome() {
        gutterView.isHidden = !configuration.features.showsGutter
        gutterView.showsLineNumbers = configuration.features.showsLineNumbers
        minimapView.isHidden = !configuration.features.showsMinimap
        textView.featureFlags = configuration.features
        needsLayout = true
        gutterView.needsDisplay = true
        minimapView.needsDisplay = true
        textView.needsDisplay = true
        updateViewportIndicators()
    }

    private func updateInteractionProviders() {
        textView.hoverTooltipProvider = { [weak self] position in
            guard let self, let provider = self.hoverProvider else {
                return nil
            }
            return provider.editorComponent(self, hoverAt: position)
        }

        textView.contextMenuProvider = { [weak self] position in
            guard let self, let provider = self.contextMenuProvider else {
                return []
            }
            return provider.editorComponent(self, contextMenuItemsAt: position)
        }
    }

    private func toggleFoldRegion(_ region: EditorFoldRegion) {
        guard region.endLine > region.startLine else {
            return
        }

        if region.isCollapsed {
            commandDispatcher.dispatch(.unfold(startLine: region.startLine))
        } else {
            commandDispatcher.dispatch(.fold(startLine: region.startLine, endLine: region.endLine))
        }
    }

    private func updateViewportIndicators() {
        guard configuration.features.showsMinimap else {
            minimapView.visibleVisualRange = nil
            return
        }

        let metrics = textView.logicalLineMetrics()
        guard !metrics.isEmpty else {
            minimapView.visibleVisualRange = nil
            return
        }

        let visibleRect = scrollView.contentView.bounds
        let lower = metrics.firstIndex { $0.rect.maxY >= visibleRect.minY } ?? 0
        let upperExclusive = metrics.lastIndex { $0.rect.minY <= visibleRect.maxY }.map { $0 + 1 } ?? lower + 1
        minimapView.visibleVisualRange = lower..<max(lower + 1, upperExclusive)
    }

    @objc
    private func handleVisibleBoundsChanged(_ notification: Notification) {
        _ = notification
        updateViewportIndicators()
    }
}

extension EditorComponentView: EditorCommandDispatchObserver {
    public func commandDispatcher(_ dispatcher: EditorCommandDispatcher, didFail error: EditorCommandError) {
        delegate?.editorComponent(self, didFail: error)
    }

    public func commandDispatcher(_ dispatcher: EditorCommandDispatcher, didSucceed result: EditorCommandResult) {
        reloadFromEngine()
        delegate?.editorComponent(self, didExecute: result)
    }
}
#endif
