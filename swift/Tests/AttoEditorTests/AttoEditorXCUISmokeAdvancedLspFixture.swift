import AttoEditorSupport
@testable import AttoEditor
import Foundation
import XCTest

@MainActor
extension AttoEditorXCUIApplicationSmokeTests {
    func enqueueOpenRequest(
        directories: [URL] = [],
        files: [URL] = [],
        launched: LaunchedAttoApp
    ) throws {
        try FileManager.default.createDirectory(at: launched.spoolDir, withIntermediateDirectories: true)
        let requestID = UUID().uuidString
        let request = AttoIpcOpenRequest(
            requestID: requestID,
            newWindow: false,
            wait: false,
            directories: directories.map(\.standardizedFileURL.path),
            files: files.map { AttoIpcFileRequest(path: $0.standardizedFileURL.path, line1: nil, column1: nil) }
        )
        let requestURL = launched.spoolDir.appendingPathComponent("req-\(requestID).json", isDirectory: false)
        let data = try JSONEncoder().encode(request)
        try data.write(to: requestURL, options: [.atomic])
    }

    func openWorkspaceFileThroughQuickOpen(
        _ query: String,
        expectingTitle title: String,
        in app: XCUIApplication
    ) throws {
        let prefix = "AttoEditor.QuickOpen"
        app.typeKey("p", modifierFlags: [.command])
        let search = try requiredElement(
            identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix),
            in: app
        )
        search.click()
        app.typeText(query)
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.commandPaletteRowTitle(prefix: prefix),
                contains: title,
                in: app
            ),
            "expected Quick Open to list \(title)"
        )
        app.typeKey(.return, modifierFlags: [])
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: dynamicIdentifierPrefix(AttoAccessibilityID.tabTitle),
                contains: title,
                in: app
            ),
            "expected Quick Open to open \(title)"
        )
    }

    func requestDocumentSymbolsAndWaitForSymbol(_ symbolName: String, in app: XCUIApplication) throws {
        try runCommandPaletteCommand("lsp.document_symbols", in: app)
        let prefix = "AttoEditor.LSP.SymbolResults"
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.commandPaletteRowTitle(prefix: prefix),
                contains: symbolName,
                in: app
            ),
            "expected document symbols to include \(symbolName)"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    func runWorkspaceSymbolSearch(_ query: String, expecting title: String, in app: XCUIApplication) throws {
        try runCommandPaletteCommand("lsp.workspace_symbols", in: app)
        let prefix = "AttoEditor.LSP.WorkspaceSymbolSearch"
        let search = try requiredElement(
            identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix),
            in: app
        )
        search.click()
        app.typeText(query)
        XCTAssertNotNil(
            waitForAnyElementText(
                identifier: AttoAccessibilityID.commandPaletteRowTitle(prefix: prefix),
                contains: title,
                in: app
            ),
            "expected Workspace Symbol Search to include \(title)"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    func waitForCapturedLineCount(at url: URL, containing needle: String, atLeast expected: Int) -> Int {
        let deadline = Date().addingTimeInterval(Self.timeout)
        var lastCount = 0
        repeat {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                lastCount = text.components(separatedBy: .newlines).filter { $0.contains(needle) }.count
                if lastCount >= expected {
                    return lastCount
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
        } while Date() < deadline
        return lastCount
    }

    func makeAdvancedLspFixture() throws -> AdvancedLspFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atto-xcui-advanced-lsp-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = rootURL.appendingPathComponent("advanced-fixture-lsp.py", isDirectory: false)
        let captureURL = rootURL.appendingPathComponent("advanced-fixture-lsp.jsonl", isDirectory: false)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try writeAdvancedLspFixtureServerScript(scriptURL: scriptURL, captureURL: captureURL)
        return AdvancedLspFixture(rootURL: rootURL, scriptURL: scriptURL, captureURL: captureURL)
    }

    func writeAdvancedLspFixtureServerScript(scriptURL: URL, captureURL: URL) throws {
        let capturePath = captureURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        #!/usr/bin/env python3
        import json
        import os
        import sys
        import time
        import traceback
        from urllib.parse import unquote

        capture_path = '\(capturePath)'
        opened_by_name = {}

        def log_event(event, **payload):
            payload['event'] = event
            payload['pid'] = os.getpid()
            with open(capture_path, 'a', encoding='utf-8') as fh:
                fh.write(json.dumps(payload, separators=(',', ':')) + '\\n')

        log_event('process_start')

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
            return json.loads(body.decode('utf-8'))

        def send_payload(payload):
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            sys.stdout.buffer.write(b'Content-Length: ' + str(len(body)).encode('ascii') + b'\\r\\n\\r\\n')
            sys.stdout.buffer.write(body)
            sys.stdout.buffer.flush()

        def send_response(request_id, result):
            send_payload({'jsonrpc': '2.0', 'id': request_id, 'result': result})

        def send_error(request_id, code, message):
            log_event('response_error', message=message)
            send_payload({'jsonrpc': '2.0', 'id': request_id, 'error': {'code': code, 'message': message}})

        def basename_from_uri(uri):
            return unquote(uri.rsplit('/', 1)[-1])

        def uri_for_name(name):
            preferred = {
                'multi_main_symbol': 'multi_main.rs',
                'multi_lib_symbol': 'multi_lib.rs',
                'root_alpha_symbol': 'root_alpha.rs',
                'root_beta_symbol': 'root_beta.rs',
                'delayed_symbol': 'root_beta.rs',
            }.get(name)
            if preferred and preferred in opened_by_name:
                return opened_by_name[preferred]
            if opened_by_name:
                return next(iter(opened_by_name.values()))
            return 'file:///atto-xcui-fixture.rs'

        def location(uri, line, character, length=8):
            return {
                'uri': uri,
                'range': {
                    'start': {'line': line, 'character': character},
                    'end': {'line': line, 'character': character + length},
                },
            }

        def document_symbol(name, line, character=3):
            return {
                'name': name,
                'kind': 12,
                'range': {
                    'start': {'line': line, 'character': 0},
                    'end': {'line': line, 'character': 30},
                },
                'selectionRange': {
                    'start': {'line': line, 'character': character},
                    'end': {'line': line, 'character': character + len(name)},
                },
            }

        def document_symbols(uri):
            base = basename_from_uri(uri)
            if base == 'multi_main.rs':
                return [document_symbol('multi_main_symbol', 0)]
            if base == 'multi_lib.rs':
                return [document_symbol('multi_lib_symbol', 0)]
            if base == 'root_alpha.rs':
                return [document_symbol('root_alpha_symbol', 0)]
            if base == 'root_beta.rs':
                return [document_symbol('root_beta_symbol', 0)]
            return [document_symbol('fixture_symbol', 0)]

        def workspace_symbol(name, line=0):
            uri = uri_for_name(name)
            return {
                'name': name,
                'kind': 12,
                'location': location(uri, line, 3, len(name)),
            }

        try:
            while True:
                message = read_message()
                if message is None:
                    break
                method = message.get('method')
                params = message.get('params', {})
                if method:
                    record = {'method': method}
                    if 'rootUri' in params:
                        record['rootUri'] = params.get('rootUri')
                    if 'workspaceFolders' in params:
                        record['workspaceFolders'] = params.get('workspaceFolders')
                    if 'textDocument' in params:
                        record['uri'] = params.get('textDocument', {}).get('uri', '')
                    if 'query' in params:
                        record['query'] = params.get('query', '')
                    log_event('message', **record)
                if method == 'textDocument/didOpen':
                    uri = params.get('textDocument', {}).get('uri', '')
                    opened_by_name[basename_from_uri(uri)] = uri
                if 'id' not in message:
                    continue
                request_id = message['id']
                if method == 'initialize':
                    send_response(request_id, {
                        'capabilities': {
                            'definitionProvider': True,
                            'documentSymbolProvider': True,
                            'workspaceSymbolProvider': True,
                        },
                        'serverInfo': {'name': 'atto-xcui-advanced-fixture-lsp'},
                    })
                elif method == 'textDocument/definition':
                    uri = params.get('textDocument', {}).get('uri', '')
                    send_response(request_id, [location(uri, 0, 3)])
                elif method == 'textDocument/documentSymbol':
                    uri = params.get('textDocument', {}).get('uri', '')
                    if basename_from_uri(uri) == 'error_symbols.rs':
                        send_error(request_id, -32001, 'fixture documentSymbol failure')
                    else:
                        send_response(request_id, document_symbols(uri))
                elif method == 'workspace/symbol':
                    query = params.get('query', '')
                    if query == 'error_symbol':
                        send_error(request_id, -32002, 'fixture workspace symbol failure')
                    elif query == 'delayed_symbol':
                        time.sleep(0.25)
                        send_response(request_id, [workspace_symbol('delayed_symbol')])
                    elif 'multi' in query:
                        send_response(request_id, [
                            workspace_symbol('multi_main_symbol'),
                            workspace_symbol('multi_lib_symbol'),
                        ])
                    else:
                        send_response(request_id, [
                            workspace_symbol('root_alpha_symbol'),
                            workspace_symbol('root_beta_symbol'),
                        ])
                elif method == 'shutdown':
                    send_response(request_id, None)
                else:
                    send_response(request_id, None)
        except Exception:
            with open(capture_path, 'a', encoding='utf-8') as fh:
                fh.write(traceback.format_exc())
            raise
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    struct AdvancedLspFixture {
        let rootURL: URL
        let scriptURL: URL
        let captureURL: URL

        func cleanUp() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }
}
