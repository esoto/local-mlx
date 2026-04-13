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

    // MARK: - Vision mode

    func test_serverModule_textMode_usesMlxLm() {
        let config = ServerLauncher.Config(
            modelPath: "m", pythonVenvPath: "", port: 8080, vision: false)
        XCTAssertEqual(ServerLauncher.serverModule(for: config), "mlx_lm.server")
    }

    func test_serverModule_visionMode_usesMlxVlm() {
        let config = ServerLauncher.Config(
            modelPath: "m", pythonVenvPath: "", port: 8080, vision: true)
        XCTAssertEqual(ServerLauncher.serverModule(for: config), "mlx_vlm.server")
    }

    func test_renderScript_visionMode_invokesMlxVlm() {
        let config = ServerLauncher.Config(
            modelPath: "mlx-community/Qwen2-VL-7B-Instruct-4bit",
            pythonVenvPath: "",
            port: 8080,
            vision: true)
        let script = ServerLauncher.renderScript(config)
        XCTAssertTrue(script.contains("exec mlx_vlm.server --model 'mlx-community/Qwen2-VL-7B-Instruct-4bit' --port 8080"))
        XCTAssertFalse(script.contains("mlx_lm.server"),
                       "vision mode must not fall back to mlx_lm.server")
    }

    func test_renderScript_visionBackgroundMode_nohupsMlxVlm() {
        let config = ServerLauncher.Config(
            modelPath: "m",
            pythonVenvPath: "",
            port: 8080,
            background: true,
            vision: true,
            pidFilePath: "/tmp/pid",
            logFilePath: "/tmp/log")
        let script = ServerLauncher.renderScript(config)
        XCTAssertTrue(script.contains("nohup mlx_vlm.server"))
        XCTAssertFalse(script.contains("nohup mlx_lm.server"))
    }

    // MARK: - Download script

    func test_renderDownloadScript_usesHuggingfaceCLI() {
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            pythonVenvPath: "")
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("huggingface-cli download 'mlx-community/Llama-3.2-3B-Instruct-4bit'"),
                      "must invoke huggingface-cli with the shell-escaped model path")
    }

    func test_renderDownloadScript_waitsForKeypress() {
        // Foreground-style: wait for the user before closing Terminal so
        // the final "done" message is actually visible.
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "m", pythonVenvPath: "")
        XCTAssertTrue(script.contains("read -n 1 -s"))
    }

    func test_renderDownloadScript_sourcesVenvWhenProvided() {
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "m", pythonVenvPath: "~/mlx-env")
        let sourceRange = script.range(of: "source '~/mlx-env'/bin/activate")
        let hfRange = script.range(of: "huggingface-cli download")
        XCTAssertNotNil(sourceRange, "venv activation line must be present")
        XCTAssertNotNil(hfRange)
        if let s = sourceRange, let h = hfRange {
            XCTAssertLessThan(s.lowerBound, h.lowerBound,
                              "venv activation must precede huggingface-cli call")
        }
    }

    func test_renderDownloadScript_noVenv_omitsSourceLine() {
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "m", pythonVenvPath: "   ")
        XCTAssertFalse(script.contains("source "),
                       "blank venv path should not emit an activate line")
    }

    func test_renderDownloadScript_modelPathWithSpaces_isShellEscaped() {
        // Model paths come from user input — make sure the escape still
        // wraps quoted paths safely.
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "mlx-community/Weird Model Name",
            pythonVenvPath: "")
        XCTAssertTrue(script.contains("'mlx-community/Weird Model Name'"))
    }

    func test_renderDownloadScript_default_doesNotForceRedownload() {
        // The non-forced path must not pass --force-download — otherwise
        // every Download Model click would re-fetch weights unnecessarily.
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "m", pythonVenvPath: "")
        XCTAssertFalse(script.contains("--force-download"))
    }

    func test_renderDownloadScript_forceRedownload_passesHuggingfaceFlag() {
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "mlx-community/gemma-3-4b-it-4bit",
            pythonVenvPath: "",
            forceRedownload: true)
        XCTAssertTrue(script.contains("huggingface-cli download 'mlx-community/gemma-3-4b-it-4bit' --force-download"),
                      "force mode must pass --force-download to huggingface-cli")
    }

    func test_renderDownloadScript_forceRedownload_updatesHeaderMessage() {
        // The Terminal banner distinguishes a fresh download from a
        // force update so users see what's happening.
        let script = ServerLauncher.renderDownloadScript(
            modelPath: "m", pythonVenvPath: "", forceRedownload: true)
        XCTAssertTrue(script.contains("UPDATING"),
                      "force mode should show an UPDATING header instead of 'downloading'")
        XCTAssertTrue(script.contains("force re-download"))
    }

    // MARK: - Install script

    func test_renderInstallScript_containsPipInstallMlxLmAndMlxVlm() {
        let script = ServerLauncher.renderInstallScript()
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("python -m pip install mlx-lm mlx-vlm"),
                      "install script must install both text and vision packages")
        XCTAssertTrue(script.contains("python3 -m venv"),
                      "install script must provision a virtualenv")
        XCTAssertTrue(script.contains("$HOME/mlx-env"),
                      "default venv target should be ~/mlx-env")
    }

    func test_renderInstallScript_checksForPython3Before() {
        let script = ServerLauncher.renderInstallScript()
        let pythonCheck = script.range(of: "command -v python3")!
        let pipInstall = script.range(of: "pip install mlx-lm")!
        XCTAssertLessThan(pythonCheck.lowerBound, pipInstall.lowerBound,
                          "must verify Python is present before trying to install")
    }

    func test_renderInstallScript_customVenvPath_isSubstituted() {
        let script = ServerLauncher.renderInstallScript(venvPath: "/opt/localmlx-env")
        XCTAssertTrue(script.contains("'/opt/localmlx-env'"),
                      "custom venv path should be shell-escaped into the script")
        XCTAssertFalse(script.contains("$HOME/mlx-env"),
                       "default path should not leak in when a custom one is given")
    }

    // MARK: - Stop script

    func test_renderStopScript_embedsPIDFileAndPort() {
        let script = ServerLauncher.renderStopScript(
            pidFilePath: "/tmp/LocalMLX/server.pid", port: 8080)
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("PIDFILE='/tmp/LocalMLX/server.pid'"))
        XCTAssertTrue(script.contains("PORT=8080"))
    }

    func test_renderStopScript_escalatesFromSigtermToSigkill() {
        // The terminate_pid helper must attempt graceful SIGTERM first,
        // then poll, then escalate to SIGKILL. If either step is
        // missing, the stop script reproduces the zombie-server bug.
        let script = ServerLauncher.renderStopScript(
            pidFilePath: "/tmp/pid", port: 8080)
        XCTAssertTrue(script.contains("kill \"$pid\" 2>/dev/null || true"),
                      "must send SIGTERM first")
        XCTAssertTrue(script.contains("kill -9 \"$pid\" 2>/dev/null || true"),
                      "must escalate to SIGKILL if graceful shutdown fails")
        let sigtermRange = script.range(of: "kill \"$pid\" 2>/dev/null")!
        let sigkillRange = script.range(of: "kill -9 \"$pid\"")!
        XCTAssertLessThan(sigtermRange.lowerBound, sigkillRange.lowerBound)
    }

    func test_renderStopScript_fallsBackToPortScan() {
        // If the PID file is missing or stale, lsof the port to find
        // whatever zombie is still bound to it.
        let script = ServerLauncher.renderStopScript(
            pidFilePath: "/tmp/pid", port: 9090)
        XCTAssertTrue(script.contains("lsof -ti tcp:$PORT"),
                      "must check port for zombie processes")
        XCTAssertTrue(script.contains("PORT=9090"),
                      "port must be hardcoded into the generated script")
    }

    func test_renderStopScript_cleansUpPIDFile() {
        let script = ServerLauncher.renderStopScript(
            pidFilePath: "/tmp/pid", port: 8080)
        XCTAssertTrue(script.contains("rm -f \"$PIDFILE\""))
    }

    // MARK: - Log rotation

    func test_renderScript_backgroundMode_rotatesExistingLargeLog() {
        // The background start script should rotate the log if it's
        // grown past the threshold — otherwise 15s polling creates
        // unbounded growth.
        let config = ServerLauncher.Config(
            modelPath: "m",
            pythonVenvPath: "",
            port: 8080,
            background: true,
            pidFilePath: "/tmp/pid",
            logFilePath: "/tmp/server.log")
        let script = ServerLauncher.renderScript(config)
        XCTAssertTrue(script.contains("mv \"$LOG\" \"$LOG.old\""),
                      "should rotate old log to .old suffix")
        XCTAssertTrue(script.contains("\(ServerLauncher.logRotationThresholdBytes)"),
                      "should embed the configured threshold")
    }

    func test_renderScript_foregroundMode_doesNotRotateLog() {
        // Foreground mode doesn't use a log file — it writes to
        // Terminal directly — so the rotation clause must not appear.
        let config = ServerLauncher.Config(
            modelPath: "m", pythonVenvPath: "", port: 8080, background: false)
        let script = ServerLauncher.renderScript(config)
        XCTAssertFalse(script.contains("mv \"$LOG\" \"$LOG.old\""))
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
