import DockerfileClaimKit

/// One `CMD`, `ENTRYPOINT` or `SHELL` line as Docker's parser reads it (the classic builder and BuildKit share the
/// parser): text that starts with `[` and parses as a JSON array of strings is the exec form; any other text is the
/// shell form, run through the stage's `SHELL`; a JSON array holding anything but strings stops the build.
public struct CommandInstruction: Sendable, Hashable {
    public enum Form: Sendable, Hashable {
        /// The exec (JSON) form: these words, no shell.
        case exec([String])
        /// The shell form: this text, handed to the shell as one argument.
        case shell(String)
        /// The build stops on this line.
        case stopsBuild(BuildStop)
    }

    /// Why the build stops on a line.
    public enum BuildStop: String, Sendable, Hashable {
        /// A JSON array with something other than a string in it.
        case notStringArray
        /// Shell-form text that starts with `--`: the parser reads it as a flag of the instruction, and `CMD`,
        /// `ENTRYPOINT` and `SHELL` take none.
        case leadingFlag
    }

    public let keyword: String
    public let form: Form
    public let lineNumber: Int
    /// The text as written after the keyword.
    public let text: String

    public init(_ instruction: DockerfileInstruction) {
        self.init(keyword: instruction.keyword, text: instruction.arguments, lineNumber: instruction.lineNumber)
    }

    init(keyword: String, text: String, lineNumber: Int) {
        self.keyword = keyword
        self.text = text
        self.lineNumber = lineNumber
        form = Self.form(of: text)
    }

    static func parsing(_ text: String, keyword: String) -> CommandInstruction {
        CommandInstruction(keyword: keyword, text: text, lineNumber: 0)
    }

    static func form(of text: String) -> Form {
        if text.hasPrefix("--") { return .stopsBuild(.leadingFlag) }
        guard text.hasPrefix("[") else { return .shell(text) }
        return switch JSONArray.parse(text) {
        case let .strings(words): .exec(words)
        case .notStrings: .stopsBuild(.notStringArray)
        case .invalid: .shell(text)
        }
    }

    /// Text that starts like an exec form but is not JSON (single quotes, a trailing comma): Docker runs it through
    /// the shell, which then fails to find a command named like the array.
    public var looksLikeBrokenExecForm: Bool {
        if case .shell = form { return text.hasPrefix("[") }
        return false
    }

    /// The words Docker stores in the image config for this line, with `shell` in front of a shell-form line.
    func words(shell: [String]) -> [String] {
        switch form {
        case let .exec(words): words
        case let .shell(script): shell + [script]
        case .stopsBuild: []
        }
    }

    /// What the line was meant to say, for a broken exec form: the array read with single quotes as double quotes
    /// and a trailing comma dropped.
    var intendedWords: [String]? {
        guard looksLikeBrokenExecForm else { return nil }
        var repaired = text.replacingOccurrences(of: "'", with: "\"")
        if let close = repaired.lastIndex(of: "]") {
            let body = repaired[..<close].trimmed
            repaired = (body.hasSuffix(",") ? String(body.dropLast()) : body) + "]"
        }
        if case let .exec(words) = Self.form(of: repaired) { return words }
        return nil
    }
}
