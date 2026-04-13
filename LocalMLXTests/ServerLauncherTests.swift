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

    // MARK: - Background mode

    func test_renderScript_background_usesNohupAndRecordsPID() {
        let config = ServerLauncher.Config(
            modelPath: "mlx-community/Phi-3",
            pythonVenvPath: "",
            port: 8080,
            background: true,
            pidFilePath: "/tmp/LocalMLX/server.pid",
            logFilePath: "/tmp/LocalMLX/logs/server.log")
        let script = ServerLauncher.renderScript(config)

        XCTAssertTrue(script.contains("nohup mlx_lm.server --model 'mlx-community/Phi-3' --port 8080 >> '/tmp/LocalMLX/logs/server.log' 2>&1 &"),
                      "background mode must nohup and redirect to the log file")
        XCTAssertTrue(script.contains("echo \"$SERVER_PID\" > '/tmp/LocalMLX/server.pid'"),
                      "background mode must record the server PID")
        XCTAssertFalse(script.contains("exec mlx_lm.server"),
                       "background mode should not use exec — the script has to exit to release Terminal")
    }

    func test_renderScript_background_withVenv_sourcesBeforeNohup() {
        let config = ServerLauncher.Config(
            modelPath: "m",
            pythonVenvPath: "~/mlx-env",
            port: 8080,
            background: true,
            pidFilePath: "/tmp/server.pid",
            logFilePath: "/tmp/server.log")
        let script = ServerLauncher.renderScript(config)
        let sourceRange = script.range(of: "source ")!
        let nohupRange = script.range(of: "nohup mlx_lm.server")!
        XCTAssertLessThan(sourceRange.lowerBound, nohupRange.lowerBound)
    }

    func test_renderScript_foreground_doesNotMentionNohup() {
        let config = ServerLauncher.Config(
            modelPath: "m",
            pythonVenvPath: "",
            port: 8080,
            background: false)
        let script = ServerLauncher.renderScript(config)
        XCTAssertFalse(script.contains("nohup"),
                       "foreground mode must never detach")
        XCTAssertTrue(script.contains("exec mlx_lm.server"))
    }

    // MARK: - Stop script

    func test_renderStopScript_killsRecordedPIDAndRemovesFile() {
        let script = ServerLauncher.renderStopScript(
            pidFilePath: "/tmp/LocalMLX/server.pid")

        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("PIDFILE='/tmp/LocalMLX/server.pid'"))
        XCTAssertTrue(script.contains("kill \"$PID\""))
        XCTAssertTrue(script.contains("rm -f \"$PIDFILE\""))
        XCTAssertTrue(script.contains("No LocalMLX server PID file found"),
                      "should handle the 'nothing to stop' case gracefully")
    }

    // MARK: - write round-trip

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
        let script = ServerLauncher.renderScript(config)

        _ = try ServerLauncher.write(script, to: url)

        // Content matches renderScript exactly.
        let fileContents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(fileContents, script)

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
        let script = ServerLauncher.renderScript(config)
        _ = try ServerLauncher.write(script, to: url)

        let fileContents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(fileContents.contains("new-model"))
        XCTAssertFalse(fileContents.contains("old"))
    }
}
