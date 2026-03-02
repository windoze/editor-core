import AppKit
import EditorCoreFFI
import Foundation

/// 一个最小可用的 AppKit 编辑组件：
/// - 使用 `NSTextView` 绘制与处理输入
/// - 拦截文本变更并转成 `editor-core` 的 offset-based replace 命令
/// - `editor-core` 作为真值，变更后回写 `NSTextView.string`
///
/// 目标是先把“基本编辑能跑通”打通：输入、删除、粘贴、选区替换、undo/redo。
@MainActor
public final class EditorCoreTextView: NSView {
    public let state: EditorState
    public let scrollView: NSScrollView
    public let textView: NSTextView

    private let coordinator: Coordinator

    public init(
        library: EditorCoreFFILibrary,
        initialText: String = "",
        viewportWidth: UInt = 120
    ) throws {
        self.state = try EditorState(library: library, initialText: initialText, viewportWidth: viewportWidth)

        // 使用系统提供的 scrollableTextView 工厂，避免手动拼装 TextStorage/LayoutManager/TextContainer
        // 时出现“documentView 尺寸为 0 导致整块空白”的常见坑。
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else {
            throw NSError(domain: "EditorCoreAppKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "NSTextView.scrollableTextView() 未返回 NSTextView"])
        }

        self.textView = tv
        self.scrollView = scroll
        self.coordinator = Coordinator(state: state)

        super.init(frame: .zero)

        coordinator.attach(textView: textView)
        configureSubviews()
        coordinator.syncFromCore(preserveSelection: false)
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidth:) 构造。")
    public override init(frame frameRect: NSRect) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidth:) 构造。")
    public required init?(coder: NSCoder) {
        fatalError("unavailable")
    }

    private func configureSubviews() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        // 注意：textView 作为 scrollView.documentView 时，通常不应该关闭 autoresizing（否则容易出现 frame=0 的空白）。
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.usesRuler = false
        textView.isIncrementalSearchingEnabled = true
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        textView.drawsBackground = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // 直接用 labelColor 更稳（textColor 在某些 appearance/组合下可能跟背景接近）
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor

        // 确保真正应用到 TextStorage（否则 NSTextView 有时会保留/继承到“看不见”的旧属性）
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any,
        ]
        textView.typingAttributes = baseAttributes
        textView.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: baseAttributes))

        // 最后兜底：如果前景/背景解析后几乎一样，强制切到高对比黑白，避免“看起来什么都没有”。
        applyContrastFallbackIfNeeded()

        // Wrap：让 NSTextView 自己负责行内换行；editor-core 的 viewportWidth 目前只用于内部布局/后续扩展。
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // scrollView.documentView 已由 scrollableTextView() 设好；这里不要重复赋值，避免触发布局异常。

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func applyContrastFallbackIfNeeded() {
        guard let fg = textView.textColor?.usingColorSpace(.deviceRGB) else { return }
        guard let bg = textView.backgroundColor.usingColorSpace(.deviceRGB) else { return }

        let delta =
            abs(fg.redComponent - bg.redComponent)
            + abs(fg.greenComponent - bg.greenComponent)
            + abs(fg.blueComponent - bg.blueComponent)

        // 阈值取一个保守值：如果太接近，就强制高对比。
        guard delta < 0.30 else {
            scrollView.backgroundColor = textView.backgroundColor
            return
        }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let forcedFG: NSColor = isDark ? .white : .black
        let forcedBG: NSColor = isDark ? .black : .white

        textView.textColor = forcedFG
        textView.insertionPointColor = forcedFG
        textView.backgroundColor = forcedBG
        scrollView.backgroundColor = forcedBG

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: textView.font as Any,
            .foregroundColor: forcedFG,
        ]
        textView.typingAttributes = baseAttributes
        if let storage = textView.textStorage {
            storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        }
    }
}

@MainActor
private final class Coordinator: NSObject, NSTextViewDelegate {
    private let state: EditorState
    private let ffi: EditorCoreFFILibrary
    private weak var textView: NSTextView?

    private var isApplyingFromCore = false

    init(state: EditorState) {
        self.state = state
        self.ffi = state.ffi
    }

    func attach(textView: NSTextView) {
        self.textView = textView
        textView.delegate = self
    }

    func syncFromCore(preserveSelection: Bool) {
        guard let textView else { return }
        guard !isApplyingFromCore else { return }

        do {
            let newText = try state.text()

            let oldSelection = textView.selectedRange()
            isApplyingFromCore = true
            setPlainTextWithBaseAttributes(textView: textView, text: newText)
            if preserveSelection {
                let clamped = NSRange(
                    location: min(oldSelection.location, (newText as NSString).length),
                    length: min(oldSelection.length, max(0, (newText as NSString).length - oldSelection.location))
                )
                textView.setSelectedRange(clamped)
            }
            isApplyingFromCore = false
        } catch {
            isApplyingFromCore = false
            NSLog("EditorCoreTextView syncFromCore failed: %@", String(describing: error))
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if isApplyingFromCore {
            return true
        }

        // NSTextView / NSString 使用 UTF-16 code units；editor-core 使用 Unicode scalar（Rust char）偏移。
        let currentText = textView.string
        let replacement = replacementString ?? ""

        let startUtf16 = max(0, affectedCharRange.location)
        let endUtf16 = max(startUtf16, affectedCharRange.location + affectedCharRange.length)

        let startScalar = Self.scalarOffset(fromUTF16Offset: startUtf16, in: currentText)
        let endScalar = Self.scalarOffset(fromUTF16Offset: endUtf16, in: currentText)
        let lengthScalar = max(0, endScalar - startScalar)

        let command = """
        {"kind":"edit","op":"replace","start":\(startScalar),"length":\(lengthScalar),"text":\(Self.jsonStringLiteral(replacement))}
        """

        do {
            _ = try state.executeJSON(command)
            let newText = try state.text()

            // caret 移到插入文本后（按 unicode scalar 计数）
            let insertedScalars = replacement.unicodeScalars.count
            let newCaretScalar = startScalar + insertedScalars
            let newCaretUtf16 = Self.utf16Offset(fromScalarOffset: newCaretScalar, in: newText)

            isApplyingFromCore = true
            setPlainTextWithBaseAttributes(textView: textView, text: newText)
            textView.setSelectedRange(NSRange(location: newCaretUtf16, length: 0))
            textView.scrollRangeToVisible(NSRange(location: newCaretUtf16, length: 0))
            isApplyingFromCore = false

            return false
        } catch {
            isApplyingFromCore = false
            NSSound.beep()
            NSLog("editor-core apply failed: %@ (last_error=%@)", String(describing: error), ffi.lastErrorMessageString())
            return false
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if isApplyingFromCore {
            return false
        }

        // 把常见编辑命令（undo/redo）交给 editor-core，避免 NSTextView 自己的 undo 栈与我们冲突。
        if commandSelector == Selector(("undo:")) {
            return runEditOpAndSync(textView: textView, op: "undo")
        }
        if commandSelector == Selector(("redo:")) {
            return runEditOpAndSync(textView: textView, op: "redo")
        }

        return false
    }

    private func runEditOpAndSync(textView: NSTextView, op: String) -> Bool {
        do {
            _ = try state.executeJSON(#"{"kind":"edit","op":"\#(op)"}"#)
            syncFromCore(preserveSelection: true)
            return true
        } catch {
            NSSound.beep()
            NSLog("editor-core %@ failed: %@ (last_error=%@)", op, String(describing: error), ffi.lastErrorMessageString())
            return true
        }
    }

    private func setPlainTextWithBaseAttributes(textView: NSTextView, text: String) {
        // 关键点：只设置 `textView.string` 在某些情况下不会把 `textColor/font` 应用到整段文本，
        // 结果就是看起来“全白/全黑”。这里强制给整个 textStorage 打基础属性。
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let color = textView.textColor ?? NSColor.labelColor
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]

        textView.typingAttributes = baseAttributes
        if let storage = textView.textStorage {
            storage.setAttributedString(NSAttributedString(string: text, attributes: baseAttributes))
        } else {
            textView.string = text
        }
    }

    // MARK: - UTF16 <-> UnicodeScalar offset mapping (simple, O(n))

    private static func scalarOffset(fromUTF16Offset targetUtf16Offset: Int, in text: String) -> Int {
        let target = max(0, min(targetUtf16Offset, text.utf16.count))

        var utf16Cursor = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            let unitCount = scalar.value <= 0xFFFF ? 1 : 2
            if utf16Cursor + unitCount > target {
                break
            }
            utf16Cursor += unitCount
            scalars += 1
        }
        return scalars
    }

    private static func utf16Offset(fromScalarOffset targetScalarOffset: Int, in text: String) -> Int {
        let target = max(0, min(targetScalarOffset, text.unicodeScalars.count))

        var utf16Cursor = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            if scalars >= target {
                break
            }
            utf16Cursor += scalar.value <= 0xFFFF ? 1 : 2
            scalars += 1
        }
        return utf16Cursor
    }

    // MARK: - JSON literal helper

    private static func jsonStringLiteral(_ value: String) -> String {
        // 只需要覆盖 demo 场景（文本插入），实现一个确定性的 JSON string 转义即可。
        var out = "\""
        out.reserveCapacity(value.utf8.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: // "
                out += "\\\""
            case 0x5C: // \
                out += "\\\\"
            case 0x08:
                out += "\\b"
            case 0x0C:
                out += "\\f"
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case 0x00...0x1F:
                out += String(format: "\\u%04X", scalar.value)
            default:
                out.append(Character(scalar))
            }
        }
        out += "\""
        return out
    }
}
