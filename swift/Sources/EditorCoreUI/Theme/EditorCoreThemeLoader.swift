import EditorCoreUIFFI
import Foundation

public enum EditorCoreThemeLoader {
    public static func loadTheme(from url: URL) throws -> EditorCoreThemeDefinition {
        let data = try Data(contentsOf: url)
        return try parseThemeJSON(data, sourceURL: url)
    }

    public static func parseThemeJSON(_ data: Data, sourceURL: URL? = nil) throws -> EditorCoreThemeDefinition {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw EditorCoreThemeError.invalidJSONRoot
        }

        let schemaVersion: Int = {
            if let n = dict["schema_version"] as? Int { return n }
            if let n = dict["schema_version"] as? NSNumber { return n.intValue }
            return 1
        }()
        guard schemaVersion == 1 else {
            throw EditorCoreThemeError.unsupportedSchemaVersion(schemaVersion)
        }

        let rawName = try requireString(dict, "name")
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            throw EditorCoreThemeError.missingRequiredField("name")
        }

        let appearance: EditorCoreThemeAppearance = {
            guard let raw = dict["appearance"] as? String else { return .unspecified }
            return EditorCoreThemeAppearance(rawValue: raw.lowercased()) ?? .unspecified
        }()

        let editorDict = try requireObject(dict, "editor")
        let chromeDict = try requireObject(dict, "chrome")

        let editorBackground = try requireColor(editorDict, "background")
        let editorForeground = try requireColor(editorDict, "foreground")
        let selectionBackground = try requireColor(editorDict, "selection_background")
        let caret = try requireColor(editorDict, "caret")

        let gutterBackground = try requireColor(chromeDict, "gutter_background")
        let gutterForeground = try requireColor(chromeDict, "gutter_foreground")
        let gutterSeparator = try requireColor(chromeDict, "gutter_separator")
        let foldMarkerCollapsed = try requireColor(chromeDict, "fold_marker_collapsed")
        let foldMarkerExpanded = try requireColor(chromeDict, "fold_marker_expanded")

        let minimapBackground = try optionalColor(chromeDict, "minimap_background")
        let scrollbarBackground = try optionalColor(chromeDict, "scrollbar_background")
        let scrollbarForeground = try optionalColor(chromeDict, "scrollbar_foreground")

        var theme = EditorCoreSkiaTheme(
            editorBackground: editorBackground,
            editorForeground: editorForeground,
            selectionBackground: selectionBackground,
            caret: caret,
            gutterBackground: gutterBackground,
            gutterForeground: gutterForeground,
            gutterSeparator: gutterSeparator,
            foldMarkerCollapsed: foldMarkerCollapsed,
            foldMarkerExpanded: foldMarkerExpanded,
            minimapBackground: minimapBackground,
            scrollbarBackground: scrollbarBackground,
            scrollbarForeground: scrollbarForeground,
            styleOverrides: [],
            treeSitterCaptureOverrides: []
        )

        if let rawOverrides = dict["style_overrides"] {
            if let arr = rawOverrides as? [Any] {
                theme.styleOverrides = parseStyleOverrides(arr, sourceURL: sourceURL)
            } else if rawOverrides is NSNull {
                theme.styleOverrides = []
            } else {
                throw EditorCoreThemeError.invalidFieldType(field: "style_overrides", expected: "array")
            }
        }

        if let rawCaptureOverrides = dict["tree_sitter_capture_overrides"] {
            if let arr = rawCaptureOverrides as? [Any] {
                theme.treeSitterCaptureOverrides = parseTreeSitterCaptureOverrides(arr, sourceURL: sourceURL)
            } else if rawCaptureOverrides is NSNull {
                theme.treeSitterCaptureOverrides = []
            } else {
                throw EditorCoreThemeError.invalidFieldType(field: "tree_sitter_capture_overrides", expected: "array")
            }
        }

        return EditorCoreThemeDefinition(
            schemaVersion: schemaVersion,
            name: name,
            appearance: appearance,
            skiaTheme: theme
        )
    }

    // MARK: - Overrides

    private static func parseStyleOverrides(_ arr: [Any], sourceURL: URL?) -> [EditorCoreSkiaStyleOverride] {
        var out: [EditorCoreSkiaStyleOverride] = []
        out.reserveCapacity(arr.count)

        for (idx, raw) in arr.enumerated() {
            guard let dict = raw as? [String: Any] else {
                logSkip(sourceURL, "style_overrides[\(idx)]: expected object")
                continue
            }

            guard let styleObj = dict["style"] else {
                logSkip(sourceURL, "style_overrides[\(idx)]: missing style selector")
                continue
            }

            guard let styleId = parseStyleSelector(styleObj, sourceURL: sourceURL, context: "style_overrides[\(idx)]") else {
                continue
            }

            let spec = parseStyleSpec(dict, sourceURL: sourceURL, context: "style_overrides[\(idx)]")
            guard spec.isEmpty == false else {
                // Allow empty entries in JSON, but they are no-ops.
                continue
            }

            out.append(.init(styleId: styleId, spec: spec))
        }

        return out
    }

    private static func parseTreeSitterCaptureOverrides(_ arr: [Any], sourceURL: URL?) -> [EditorCoreSkiaTreeSitterCaptureOverride] {
        var out: [EditorCoreSkiaTreeSitterCaptureOverride] = []
        out.reserveCapacity(arr.count)

        for (idx, raw) in arr.enumerated() {
            guard let dict = raw as? [String: Any] else {
                logSkip(sourceURL, "tree_sitter_capture_overrides[\(idx)]: expected object")
                continue
            }

            guard let captureRaw = dict["capture"] as? String else {
                logSkip(sourceURL, "tree_sitter_capture_overrides[\(idx)]: missing capture")
                continue
            }
            let capture = captureRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard capture.isEmpty == false else { continue }

            let spec = parseStyleSpec(dict, sourceURL: sourceURL, context: "tree_sitter_capture_overrides[\(idx)]")
            guard spec.isEmpty == false else { continue }

            out.append(.init(capture: capture, spec: spec))
        }

        return out
    }

    // MARK: - Style selector

    private static let builtinStyleNameToId: [String: UInt32] = [
        normalizeKey("foldPlaceholder"): EditorCoreSkiaBuiltinStyleId.foldPlaceholder,
        normalizeKey("imeMarkedText"): EditorCoreSkiaBuiltinStyleId.imeMarkedText,
        normalizeKey("inlayHint"): EditorCoreSkiaBuiltinStyleId.inlayHint,
        normalizeKey("codeLens"): EditorCoreSkiaBuiltinStyleId.codeLens,
        normalizeKey("documentLink"): EditorCoreSkiaBuiltinStyleId.documentLink,
        normalizeKey("matchHighlight"): EditorCoreSkiaBuiltinStyleId.matchHighlight,
        normalizeKey("commandHoverLink"): EditorCoreSkiaBuiltinStyleId.commandHoverLink,
    ]

    private static let reservedStyleNameToId: [String: UInt32] = [
        normalizeKey("gutterBackground"): EditorCoreSkiaReservedStyleId.gutterBackground,
        normalizeKey("gutterForeground"): EditorCoreSkiaReservedStyleId.gutterForeground,
        normalizeKey("gutterSeparator"): EditorCoreSkiaReservedStyleId.gutterSeparator,
        normalizeKey("foldMarkerCollapsed"): EditorCoreSkiaReservedStyleId.foldMarkerCollapsed,
        normalizeKey("foldMarkerExpanded"): EditorCoreSkiaReservedStyleId.foldMarkerExpanded,
        normalizeKey("indentGuide"): EditorCoreSkiaReservedStyleId.indentGuide,
        normalizeKey("whitespace"): EditorCoreSkiaReservedStyleId.whitespace,
    ]

    private static func parseStyleSelector(_ value: Any, sourceURL: URL?, context: String) -> UInt32? {
        guard let dict = value as? [String: Any] else {
            logSkip(sourceURL, "\(context).style: expected object")
            return nil
        }

        var candidates: [(String, Any)] = []
        if let v = dict["style_id"], (v is NSNull) == false { candidates.append(("style_id", v)) }
        if let v = dict["builtin"], (v is NSNull) == false { candidates.append(("builtin", v)) }
        if let v = dict["reserved"], (v is NSNull) == false { candidates.append(("reserved", v)) }
        if let v = dict["lsp_semantic"], (v is NSNull) == false { candidates.append(("lsp_semantic", v)) }

        if candidates.isEmpty {
            logSkip(sourceURL, "\(context).style: missing selector")
            return nil
        }
        if candidates.count > 1 {
            logSkip(
                sourceURL,
                "\(context).style: selector must be one-of (got \(candidates.map(\.0).joined(separator: ", ")))"
            )
            return nil
        }

        let (kind, raw) = candidates[0]

        switch kind {
        case "style_id":
            guard let styleId = parseUInt32(raw) else {
                logSkip(sourceURL, "\(context).style.style_id: invalid value")
                return nil
            }
            return styleId
        case "builtin":
            guard let s = raw as? String else {
                logSkip(sourceURL, "\(context).style.builtin: expected string")
                return nil
            }
            let key = normalizeKey(s)
            guard let id = builtinStyleNameToId[key] else {
                logSkip(sourceURL, "\(context).style.builtin: unknown builtin '\(s)'")
                return nil
            }
            return id
        case "reserved":
            guard let s = raw as? String else {
                logSkip(sourceURL, "\(context).style.reserved: expected string")
                return nil
            }
            let key = normalizeKey(s)
            guard let id = reservedStyleNameToId[key] else {
                logSkip(sourceURL, "\(context).style.reserved: unknown reserved '\(s)'")
                return nil
            }
            return id
        case "lsp_semantic":
            guard let obj = raw as? [String: Any] else {
                logSkip(sourceURL, "\(context).style.lsp_semantic: expected object")
                return nil
            }

            guard let tokenType = obj["token_type"] as? String else {
                logSkip(sourceURL, "\(context).style.lsp_semantic.token_type: expected string")
                return nil
            }

            let modifierBits: UInt32 = {
                guard let rawMods = obj["modifiers"] else { return 0 }
                guard let mods = rawMods as? [Any] else { return 0 }
                var bits: UInt32 = 0
                for rawMod in mods {
                    guard let mod = rawMod as? String else { continue }
                    bits |= EditorCoreSkiaLspSemanticStyleId.modifierBit(named: mod)
                }
                return bits
            }()

            guard let id = EditorCoreSkiaLspSemanticStyleId.styleId(tokenType: tokenType, modifierBits: modifierBits) else {
                logSkip(sourceURL, "\(context).style.lsp_semantic: unknown token_type '\(tokenType)'")
                return nil
            }
            return id
        default:
            logSkip(sourceURL, "\(context).style: unknown selector kind \(kind)")
            return nil
        }
    }

    // MARK: - Style spec

    private static func parseStyleSpec(
        _ dict: [String: Any],
        sourceURL: URL?,
        context: String
    ) -> EditorCoreSkiaStyleSpec {
        var spec = EditorCoreSkiaStyleSpec()

        spec.foreground = parseOptionalColorValue(dict["foreground"], sourceURL: sourceURL, context: "\(context).foreground")
        spec.background = parseOptionalColorValue(dict["background"], sourceURL: sourceURL, context: "\(context).background")

        if let v = dict["bold"] as? Bool { spec.bold = v }
        if let v = dict["italic"] as? Bool { spec.italic = v }
        if let v = dict["strikethrough"] as? Bool { spec.strikethrough = v }

        if let raw = dict["underline"] {
            if raw is NSNull {
                spec.underline = nil
            } else if let s = raw as? String {
                spec.underline = parseUnderlineStyle(s, sourceURL: sourceURL, context: "\(context).underline")
            } else {
                logSkip(sourceURL, "\(context).underline: expected string")
            }
        }

        spec.underlineColor = parseOptionalColorValue(dict["underline_color"], sourceURL: sourceURL, context: "\(context).underline_color")
        spec.strikethroughColor = parseOptionalColorValue(dict["strikethrough_color"], sourceURL: sourceURL, context: "\(context).strikethrough_color")

        return spec
    }

    private static func parseUnderlineStyle(_ raw: String, sourceURL: URL?, context: String) -> EcuUnderlineStyle? {
        switch normalizeKey(raw) {
        case normalizeKey("single"):
            return .single
        case normalizeKey("double"):
            return .double
        case normalizeKey("squiggly"):
            return .squiggly
        default:
            logSkip(sourceURL, "\(context): invalid underline style '\(raw)'")
            return nil
        }
    }

    // MARK: - Color parsing

    private static func requireColor(_ dict: [String: Any], _ key: String) throws -> EcuRgba8 {
        guard let raw = dict[key] else {
            throw EditorCoreThemeError.missingRequiredField(key)
        }
        guard let c = parseColorValue(raw) else {
            throw EditorCoreThemeError.invalidColor("\(key)=\(String(describing: raw))")
        }
        return c
    }

    private static func optionalColor(_ dict: [String: Any], _ key: String) throws -> EcuRgba8? {
        guard let raw = dict[key] else { return nil }
        return parseColorValue(raw)
    }

    private static func parseOptionalColorValue(_ raw: Any?, sourceURL: URL?, context: String) -> EcuRgba8? {
        guard let raw else { return nil }
        guard raw is NSNull == false else { return nil }
        if let c = parseColorValue(raw) { return c }
        logSkip(sourceURL, "\(context): invalid color value")
        return nil
    }

    /// Supports:
    /// - "#RRGGBB" / "#RRGGBBAA"
    /// - { "r": 255, "g": 255, "b": 255, "a": 255 }
    private static func parseColorValue(_ raw: Any) -> EcuRgba8? {
        if let s = raw as? String {
            return parseHexColorString(s)
        }

        guard let obj = raw as? [String: Any] else { return nil }
        guard
            let r = parseUInt8(obj["r"]),
            let g = parseUInt8(obj["g"]),
            let b = parseUInt8(obj["b"])
        else {
            return nil
        }
        let a = parseUInt8(obj["a"]) ?? 0xFF
        return EcuRgba8(r: r, g: g, b: b, a: a)
    }

    private static func parseHexColorString(_ raw: String) -> EcuRgba8? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.isEmpty == false else { return nil }

        var hex = s
        if hex.hasPrefix("#") { hex.removeFirst() }

        if hex.count == 6 {
            hex.append("FF")
        }
        guard hex.count == 8 else { return nil }

        guard let rgba = UInt32(hex, radix: 16) else { return nil }

        let r = UInt8((rgba >> 24) & 0xFF)
        let g = UInt8((rgba >> 16) & 0xFF)
        let b = UInt8((rgba >> 8) & 0xFF)
        let a = UInt8(rgba & 0xFF)
        return EcuRgba8(r: r, g: g, b: b, a: a)
    }

    // MARK: - Primitives

    private static func requireString(_ dict: [String: Any], _ key: String) throws -> String {
        guard let raw = dict[key] else {
            throw EditorCoreThemeError.missingRequiredField(key)
        }
        guard let s = raw as? String else {
            throw EditorCoreThemeError.invalidFieldType(field: key, expected: "string")
        }
        return s
    }

    private static func requireObject(_ dict: [String: Any], _ key: String) throws -> [String: Any] {
        guard let raw = dict[key] else {
            throw EditorCoreThemeError.missingRequiredField(key)
        }
        guard let obj = raw as? [String: Any] else {
            throw EditorCoreThemeError.invalidFieldType(field: key, expected: "object")
        }
        return obj
    }

    private static func parseUInt8(_ raw: Any?) -> UInt8? {
        guard let raw else { return nil }
        if let n = raw as? UInt8 { return n }
        if let n = raw as? Int { return (0...255).contains(n) ? UInt8(n) : nil }
        if let n = raw as? NSNumber { return (0...255).contains(n.intValue) ? UInt8(n.intValue) : nil }
        return nil
    }

    private static func parseUInt32(_ raw: Any) -> UInt32? {
        if let n = raw as? UInt32 { return n }
        if let n = raw as? Int {
            guard n >= 0 && n <= Int(UInt32.max) else { return nil }
            return UInt32(n)
        }
        if let n = raw as? UInt64 {
            guard n <= UInt64(UInt32.max) else { return nil }
            return UInt32(n)
        }
        if let n = raw as? NSNumber {
            let v = n.int64Value
            guard v >= 0 && v <= Int64(UInt32.max) else { return nil }
            return UInt32(v)
        }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.isEmpty == false else { return nil }

            if t.hasPrefix("0x") || t.hasPrefix("0X") {
                let hex = String(t.dropFirst(2))
                return UInt32(hex, radix: 16)
            }
            return UInt32(t, radix: 10)
        }
        return nil
    }

    private static func normalizeKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func logSkip(_ sourceURL: URL?, _ message: String) {
        if let sourceURL {
            NSLog("EditorCoreThemeLoader: skip theme entry (%@): %@", sourceURL.path, message)
        } else {
            NSLog("EditorCoreThemeLoader: skip theme entry: %@", message)
        }
    }
}

private extension EditorCoreSkiaStyleSpec {
    var isEmpty: Bool {
        foreground == nil
            && background == nil
            && bold == nil
            && italic == nil
            && underline == nil
            && underlineColor == nil
            && strikethrough == nil
            && strikethroughColor == nil
    }
}
