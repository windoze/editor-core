#if canImport(AppKit)
import AppKit

public protocol EditorComponentDelegate: AnyObject {
    func editorComponent(_ component: EditorComponentView, didFail error: EditorCommandError)
    func editorComponent(_ component: EditorComponentView, didExecute commandResult: EditorCommandResult)
}

public final class EditorComponentView: NSView {
    public weak var delegate: EditorComponentDelegate?

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

    public let scrollView: NSScrollView

    private let textView: EditorTextView
    private let gutterView: EditorGutterView
    private let minimapView: EditorMinimapView
    private let commandDispatcher: EditorCommandDispatcher

    public override var isFlipped: Bool { true }

    public var currentDisplayedText: String {
        textView.string
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

    public override func layout() {
        super.layout()

        let minimapWidth: CGFloat = configuration.features.showsMinimap ? 120 : 0
        let gutterWidth: CGFloat = configuration.features.showsGutter ? 56 : 0

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

    public func reloadFromEngine() {
        guard let engine else {
            textView.string = ""
            gutterView.lineNumbers = []
            minimapView.snapshot = .init(startVisualRow: 0, requestedCount: 0, lines: [])
            return
        }

        textView.string = engine.text

        do {
            let state = try engine.documentState()
            gutterView.lineNumbers = Array(1...max(state.lineCount, 1))

            if configuration.features.showsMinimap {
                minimapView.snapshot = try engine.minimapViewport(
                    .init(startVisualRow: 0, rowCount: max(state.lineCount, 1))
                )
            }
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
            return p
        }()

        textView.isContinuousSpellCheckingEnabled = false
        textView.layoutManager?.allowsNonContiguousLayout = true

        if style.enablesLigatures {
            textView.typingAttributes[.ligature] = 1
        } else {
            textView.typingAttributes[.ligature] = 0
        }
    }

    private func refreshChrome() {
        gutterView.isHidden = !configuration.features.showsGutter
        minimapView.isHidden = !configuration.features.showsMinimap
        needsLayout = true
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
