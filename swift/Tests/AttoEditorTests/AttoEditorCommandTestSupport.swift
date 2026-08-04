import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorCommandTests: XCTestCase {
    func allowWorkspaceEditPreviewConfirmation(_ vc: AttoEditorAreaViewController) {
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { _ in .apply }
    }

    func makeEditorArea(
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared,
        projectLspProcessHealthLogStore: AttoProjectLspProcessHealthLogStore = AttoProjectLspProcessHealthLogStore()
    ) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL,
            preferences: preferences,
            projectLspProcessHealthLogStore: projectLspProcessHealthLogStore
        )
    }

    @discardableResult
    func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    func waitForCapturedLspInput(at url: URL, containing needle: String) -> String {
        for _ in 0..<100 {
            let captured = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if captured.contains(needle) {
                return captured
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func waitForCapturedLspInput(
        at url: URL,
        containing needle: String,
        minimumOccurrences: Int
    ) -> String {
        for _ in 0..<100 {
            let captured = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if occurrenceCount(of: needle, in: captured) >= minimumOccurrences {
                return captured
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @discardableResult
    func waitUntil(_ condition: () -> Bool) -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    func waitForCoreWorkspaceEditTransactionSequence(
        _ vc: AttoEditorAreaViewController,
        expected: UInt64
    ) -> UInt64? {
        for _ in 0..<100 {
            let sequence = try? vc._coreWorkspaceEditTransactionLatestSequenceForTesting()
            if sequence == expected {
                return sequence
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return try? vc._coreWorkspaceEditTransactionLatestSequenceForTesting()
    }

    func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard needle.isEmpty == false else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    func writeFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let initBody = #"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#
        let capturePath = captureURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        body='\(initBody)'
        printf 'Content-Length: %s\\r\\n\\r\\n%s' "${#body}" "$body"
        cat > '\(capturePath)'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeExecuteCommandWorkspaceEditFakeLspServerScript(
        captureURL: URL,
        scriptURL: URL,
        resultJSON: String
    ) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let resultPayload = resultJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'
        result_payload = json.loads('\(resultPayload)')

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'executeCommandProvider': {
                                'commands': ['atto.applyEdit']
                            }
                        }
                    }
                })
            elif method == 'workspace/executeCommand':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': result_payload
                })
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeInlayHintResolveFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'inlayHintProvider': {
                                'resolveProvider': True
                            }
                        }
                    }
                })
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeColorPresentationFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'colorProvider': True
                        }
                    }
                })
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeCodeActionFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'codeActionProvider': True
                        }
                    }
                })
            elif method == 'textDocument/codeAction':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': []})
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeCompletionFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'completionProvider': {
                                'resolveProvider': False,
                                'triggerCharacters': ['.']
                            }
                        }
                    }
                })
            elif method == 'textDocument/completion':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'isIncomplete': False,
                        'items': []
                    }
                })
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeFormattingFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'documentFormattingProvider': True
                        }
                    }
                })
            elif method == 'textDocument/formatting':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': [{
                        'range': {
                            'start': {'line': 0, 'character': 0},
                            'end': {'line': 1, 'character': 0}
                        },
                        'newText': 'formatted\\n'
                    }]
                })
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeOnTypeFormattingFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        capture_path = '\(capturePath)'

        def read_message():
            headers = {}
            while True:
                line = sys.stdin.buffer.readline()
                if not line:
                    return None
                if line in (b'\\r\\n', b'\\n'):
                    break
                key, _, value = line.decode('ascii', 'ignore').partition(':')
                headers[key.lower()] = value.strip()

            length = int(headers.get('content-length', '0'))
            if length <= 0:
                return None

            body = sys.stdin.buffer.read(length)
            with open(capture_path, 'ab') as fh:
                fh.write(b'\\n--message--\\n')
                fh.write(body)
            return json.loads(body.decode('utf-8'))

        def send_message(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(
                b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n' + body
            )
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break

            method = message.get('method')
            if method == 'initialize':
                send_message({
                    'jsonrpc': '2.0',
                    'id': message.get('id'),
                    'result': {
                        'capabilities': {
                            'textDocumentSync': 1,
                            'documentOnTypeFormattingProvider': {
                                'firstTriggerCharacter': ';',
                                'moreTriggerCharacter': ['}']
                            }
                        }
                    }
                })
            elif method == 'textDocument/onTypeFormatting':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': []})
            elif method == 'shutdown':
                send_message({'jsonrpc': '2.0', 'id': message.get('id'), 'result': None})
            elif method == 'exit':
                break
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func writeAppendingFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let initBody = #"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#
        let capturePath = captureURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        body='\(initBody)'
        printf 'Content-Length: %s\\r\\n\\r\\n%s' "${#body}" "$body"
        printf '\\n--session--\\n' >> '\(capturePath)'
        cat >> '\(capturePath)'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T { return v }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }

    func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var out: [T] = []
        if let v = root as? T {
            out.append(v)
        }
        for child in root.subviews {
            out.append(contentsOf: findSubviews(of: type, in: child))
        }
        return out
    }

    func findTabChipView(title: String, in root: NSView) -> NSView? {
        findSubviews(of: NSView.self, in: root).first { view in
            view.subviews.contains { subview in
                (subview as? NSTextField)?.stringValue == title
            }
        }
    }

    func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for child in root.subviews {
            if let found = findView(identifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    @discardableResult
    func invokeButtonAction(
        _ button: NSButton,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard let action = button.action else {
            XCTFail("Button has no action", file: file, line: line)
            return false
        }
        let sent = NSApp.sendAction(action, to: button.target, from: button)
        if sent == false {
            XCTFail("Button action was not handled", file: file, line: line)
        }
        return sent
    }

    func findMenuItem(commandID: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? String == commandID {
                return item
            }
            if let submenu = item.submenu, let found = findMenuItem(commandID: commandID, in: submenu) {
                return found
            }
        }
        return nil
    }

    func topLevelMenu(title: String, in menu: NSMenu) -> NSMenu? {
        for item in menu.items {
            if item.submenu?.title == title {
                return item.submenu
            }
        }
        return nil
    }
}
