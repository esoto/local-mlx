import XCTest
@testable import LocalMLX

final class ServerLauncherTests: XCTestCase {

    // MARK: - renderScript

    func test_renderScript_withoutVenv_hasShebangAndExec() {
        let config = ServerLauncher.Config(
            modelPath: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            pythonVenvPath: "",
            port: 8080)
        let script = ServerLauncher.renderScript(config)

        XCTAssertTrue(script.hasPrefix("#!/bin/bash"),
                      "script should start with bash shebang")
        XCTAssertTrue(script.contains("set -eu"))
        XCTAssertTrue(script.contains("exec mlx_lm.server --model 'mlx-community/Llama-3.2-3B-Instruct-4bit' --port 8080"),
                      "exec line should pass model + port")
        XCTAssertFalse(script.contains("source "),
                       "no venv means no source line")
        XCTAssertTrue(script.hasSuffix("\n"), "script should end with a newline")
    }

    func test_renderScript_withVenv_includesSourceLine() {
        let config = ServerLauncher.Config(
            modelPath: "mistralai/Mistral-7B",
            pythonVenvPath: "/Users/me/mlx-env",
            port: 9090)
        let script = ServerLauncher.renderScript(config)

        XCTAssertTrue(script.contains("source '/Users/me/mlx-env'/bin/activate"),
                      "venv path should be sourced before exec")
        XCTAssertTrue(script.contains("exec mlx_lm.server --model 'mistralai/Mistral-7B' --port 9090"))

        // Order matters: source must come before exec.
        let sourceRange = script.range(of: "source ")!
        let execRange = script.range(of: "exec mlx_lm.server")!
        XCTAssertLessThan(sourceRange.lowerBound, execRange.lowerBound,
                          "venv activation must precede exec")
    }

    func test_renderScript_venvPath_trimsWhitespace() {
        let config = ServerLauncher.Config(
            modelPath: "m",
            pythonVenvPath: "   \n",
            port: 8080)
        let script = ServerLauncher.renderScript(config)
        XCTAssertFalse(script.contains("source "),
                       "all-whitespace venv path should be treated as empty")
    }

    // MARK: - shellEscape

    func test_shellEscape_wrapsInSingleQuotes() {
        XCTAssertEqual(ServerLauncher.shellEscape("hello"), "'hello'")
    }

    func test_shellEscape_escapesEmbeddedSingleQuote() {
        // Classic bash-safe embedding: end quoted section, escape, re-open.
        XCTAssertEqual(ServerLauncher.shellEscape("it's"), "'it'\\''s'")
    }

    func test_shellEscape_preservesSpacesUnchanged() {
        XCTAssertEqual(ServerLauncher.shellEscape("a b c"), "'a b c'")
    }

    // MARK: - write(_:to:) round-trip

    func test_write_producesExecutableFileWithRenderedContents() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServerLauncherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("start.command")
        let config = ServerLauncher.Config(
            modelPath: "unit-test-model",
            pythonVenvPath: "",
            port: 12345)

        _ = try ServerLauncher.write(config, to: url)

        // Content matches renderScript exactly.
        let fileContents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(fileContents, ServerLauncher.renderScript(config))

        // File is executable.
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.uint16Value, 0o755,
                       "written script should be marked executable")
    }

    func test_write_overwritesExistingFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServerLauncherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("start.command")
        try "old".write(to: url, atomically: true, encoding: .utf8)

        let config = ServerLauncher.Config(
            modelPath: "new-model", pythonVenvPath: "", port: 8080)
        _ = try ServerLauncher.write(config, to: url)

        let fileContents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(fileContents.contains("new-model"))
        XCTAssertFalse(fileContents.contains("old"))
    }
}
