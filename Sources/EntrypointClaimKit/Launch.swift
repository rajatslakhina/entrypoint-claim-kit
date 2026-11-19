/// The process a `docker run` starts, as far as the Dockerfile settles it.
public struct Launch: Sendable, Hashable {
    /// The words the daemon executes: the program, then its arguments.
    public let words: [String]
    /// The base image's `ENTRYPOINT`, which the Dockerfile does not show, comes before `words`.
    public let prefixFromBase: Bool
    /// `false` when the base image decides everything (the Dockerfile sets neither `CMD` nor `ENTRYPOINT`).
    public let isKnown: Bool

    public init(words: [String], prefixFromBase: Bool, isKnown: Bool = true) {
        self.words = words
        self.prefixFromBase = prefixFromBase
        self.isKnown = isKnown
    }

    /// Docker refuses to start the container: nothing to execute.
    public var refused: Bool {
        isKnown && !prefixFromBase && words.isEmpty
    }

    /// For a process started through a shell (`/bin/sh -c "script"`), the script: what actually runs. Words after
    /// it only fill the script's `$0`, `$1`, ...
    public var script: String? {
        shellCall?.last
    }

    /// The words through the script (`/bin/sh -c "script"`), without the `$0`, `$1`, ... that follow it.
    var shellCall: [String]? {
        guard let first = words.first, Self.shells.contains(Self.basename(first)),
              let flag = words.firstIndex(of: "-c"), flag <= 3, flag + 1 < words.count else { return nil }
        return Array(words[...(flag + 1)])
    }

    /// The command line as a person would type it.
    public var display: String {
        words.map(Self.quoted).joined(separator: " ")
    }

    static let shells: Set<String> = ["sh", "bash", "dash", "ash", "zsh"]

    static func basename(_ word: String) -> String {
        String(word.split(separator: "/").last ?? Substring(word))
    }

    static func quoted(_ word: String) -> String {
        guard word.isEmpty || word.contains(where: { $0.isWhitespace || "\"'$\\`".contains($0) }) else { return word }
        let escaped = word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
