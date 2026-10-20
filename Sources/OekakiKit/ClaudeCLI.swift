import Foundation

/// Runs the Claude Code command-line tool the user has installed and signed in to.
///
/// The app has no server and no keys of its own. A request is one run of
/// `claude -p` in a folder that holds the canvas picture.
public enum ClaudeCLI {
    public enum Failure: LocalizedError, Equatable {
        case notInstalled
        case notLoggedIn
        case cancelled
        case timedOut
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return L("Claude Code が見つかりません。", "Claude Code was not found.")
            case .notLoggedIn:
                return L("Claude にログインしていません。", "You are not signed in to Claude.")
            case .cancelled:
                return L("中止しました。", "Stopped.")
            case .timedOut:
                return L("時間がかかりすぎたので中止しました。もう一度お試しください。", "It took too long and was stopped. Please try again.")
            case .failed(let message):
                return L("AI から返事をもらえませんでした: \(message)", "The assistant could not answer: \(message)")
            }
        }
    }

    public struct Reply {
        public var text: String
        /// Pass this back as `resume` to continue the same conversation.
        public var sessionID: String?
        public var seconds: Double
    }

    /// A request in progress.
    public final class Run {
        fileprivate let process = Process()
        fileprivate var wasCancelled = false
        fileprivate var didTimeOut = false

        public func cancel() {
            wasCancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    /// Finds the `claude` command. An app started from the Finder does not
    /// get the shell's PATH, so the usual install places are checked first.
    public static func locate() -> URL? {
        let files = FileManager.default
        if let forced = ProcessInfo.processInfo.environment["OEKAKI_CLAUDE"], files.isExecutableFile(atPath: forced) {
            return URL(fileURLWithPath: forced)
        }
        let home = files.homeDirectoryForCurrentUser.path
        let places = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let found = places.first(where: { files.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        // Last resort: ask a login shell, which reads the user's own PATH setup.
        guard let output = try? capture(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v claude"]) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
        environment["PATH"] = [extra, environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        return environment
    }

    private static func capture(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the user is signed in. Calls back on the main queue.
    public static func checkLogin(executable: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            struct Status: Decodable {
                var loggedIn: Bool
            }
            let output = (try? capture(executable, ["auth", "status"])) ?? ""
            let loggedIn = (try? JSONDecoder().decode(Status.self, from: Data(output.utf8)))?.loggedIn ?? false
            DispatchQueue.main.async { completion(loggedIn) }
        }
    }

    /// Opens the sign-in page in the browser. The command waits there until
    /// the user finishes, so it is left running on its own.
    public static func startLogin(executable: URL) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "login"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// The model the assistant runs on, and how hard it thinks unless told otherwise.
    public static let model = "opus"
    public static let effort = "medium"

    /// Sends one prompt and calls back on the main queue with the reply.
    ///
    /// The assistant may only read files in `directory`; it gets no other tools.
    @discardableResult
    public static func run(
        executable: URL, prompt: String, directory: URL, model: String, effort: String? = nil, resume: String? = nil,
        timeout: TimeInterval = 600, completion: @escaping (Result<Reply, Failure>) -> Void
    ) -> Run {
        let run = Run()
        let process = run.process
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        var arguments = [
            "-p", "--model", model, "--output-format", "json",
            "--tools", "Read", "--allowedTools", "Read",
            "--strict-mcp-config", "--disable-slash-commands",
        ]
        if let effort {
            arguments += ["--effort", effort]
        }
        if let resume {
            arguments += ["--resume", resume]
        }
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let started = Date()
        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(.failure(.notInstalled)) }
            return run
        }
        input.fileHandleForWriting.write(Data(prompt.utf8))
        try? input.fileHandleForWriting.close()

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning else { return }
            run.didTimeOut = true
            process.terminate()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // Both pipes are drained at once so a chatty stderr cannot stall stdout.
            var errorData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                errorData = errors.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            let result = interpret(
                output: outputData, errors: errorData, status: process.terminationStatus,
                wasCancelled: run.wasCancelled, didTimeOut: run.didTimeOut, seconds: Date().timeIntervalSince(started)
            )
            DispatchQueue.main.async { completion(result) }
        }
        return run
    }

    static func interpret(
        output: Data, errors: Data, status: Int32, wasCancelled: Bool, didTimeOut: Bool, seconds: Double
    ) -> Result<Reply, Failure> {
        if wasCancelled { return .failure(.cancelled) }
        if didTimeOut { return .failure(.timedOut) }
        struct Output: Decodable {
            var is_error: Bool?
            var result: String?
            var session_id: String?
        }
        let decoded = try? JSONDecoder().decode(Output.self, from: output)
        if status == 0, let decoded, decoded.is_error != true, let text = decoded.result, !text.isEmpty {
            return .success(Reply(text: text, sessionID: decoded.session_id, seconds: seconds))
        }
        let message = [decoded?.result, String(data: errors, encoding: .utf8), String(data: output, encoding: .utf8)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "exit \(status)"
        let lowered = message.lowercased()
        if lowered.contains("/login") || lowered.contains("not logged in") || lowered.contains("authentication") {
            return .failure(.notLoggedIn)
        }
        return .failure(.failed(String(message.prefix(300))))
    }
}
