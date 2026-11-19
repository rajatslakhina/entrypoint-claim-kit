/// One thing an answer says, or shows, about what a container runs.
public struct EntrypointClaim: Sendable, Hashable {
    public enum Subject: Sendable, Hashable {
        /// "`docker run app --debug` runs `python app.py --debug`": the run, and the words the answer says it executes.
        case runs(DockerRun, claimed: [String])
        /// A general statement about how `CMD`, `ENTRYPOINT` and `docker run` combine.
        case statement(Statement)
        /// A `CMD`, `ENTRYPOINT` or `SHELL` line of the answer's Dockerfile that does not do what it looks like.
        case line(Line, lineNumber: Int)
    }

    public enum Statement: String, Sendable, Hashable, CaseIterable {
        /// Arguments after the image replace `CMD`. Holds.
        case argumentsReplaceCmd
        /// Arguments after the image are added after `CMD`. Wrong: they replace it.
        case argumentsAppendToCmd
        /// Arguments after the image follow the `ENTRYPOINT`. Holds for an exec-form `ENTRYPOINT` only.
        case argumentsAppendToEntrypoint
        /// Arguments after the image replace the `ENTRYPOINT`. Wrong: only `--entrypoint` does.
        case argumentsReplaceEntrypoint
        /// `--entrypoint` drops the image's `CMD`. Holds.
        case overrideClearsCmd
        /// `--entrypoint` keeps the image's `CMD` as its arguments. Wrong.
        case overrideKeepsCmd
        /// A shell-form `ENTRYPOINT` ignores `CMD` and run arguments. Holds.
        case shellEntrypointIgnoresArguments
        /// A shell-form `ENTRYPOINT` receives `CMD` or run arguments. Wrong.
        case shellEntrypointTakesArguments
        /// Only the last `CMD` takes effect. Holds.
        case lastCmdCounts
        /// Every `CMD` line runs. Wrong.
        case everyCmdRuns
        /// Setting `ENTRYPOINT` empties a `CMD` inherited from the base. Holds.
        case entrypointResetsBaseCmd
        /// Setting `ENTRYPOINT` keeps a `CMD` inherited from the base. Wrong.
        case entrypointKeepsBaseCmd
        /// The exec form needs double quotes. Holds.
        case execFormNeedsDoubleQuotes
        /// Single quotes work in the exec form. Wrong.
        case singleQuotesWork
    }

    public enum Line: String, Sendable, Hashable, CaseIterable {
        /// A shell-form `CMD` under an exec-form `ENTRYPOINT`: the `ENTRYPOINT` receives `/bin/sh`, `-c` and the text.
        case shellCmdUnderExecEntrypoint
        /// Text that starts like an exec form but is not JSON: it runs through the shell as a command named `[...`.
        case brokenExecForm
        /// A JSON array holding something but strings: the build stops.
        case notStringArray
        /// Shell-form text starting with `--`: read as a flag of the instruction, so the build stops.
        case leadingFlag
        /// A shell-form `ENTRYPOINT` with a `CMD`: the `CMD` never reaches the program.
        case shellEntrypointDropsCmd
        /// More than one `CMD` in the final stage: only the last counts.
        case severalCmd
        /// More than one `ENTRYPOINT` in the final stage: only the last counts.
        case severalEntrypoint
        /// The final stage's `ENTRYPOINT` empties the `CMD` it inherited from an earlier stage.
        case inheritedCmdCleared

        /// The mistake a stated claim makes when it reads this line the way it looks.
        var slip: EntrypointFinding.Slip? {
            switch self {
            case .shellCmdUnderExecEntrypoint: .shellCmdIsWords
            case .brokenExecForm: .brokenExecForm
            case .shellEntrypointDropsCmd: .shellFormTakesArguments
            case .severalCmd: .earlierCmdCounts
            case .inheritedCmdCleared: .entrypointKeepsBaseCmd
            case .notStringArray, .leadingFlag, .severalEntrypoint: nil
            }
        }
    }

    public let subject: Subject
    /// The sentence the claim was read from, or the Dockerfile line.
    public let sentence: String
    /// What the claim is judged against: the image config of the Dockerfile in the conversation, when there is one.
    public let image: ImageCommands?

    public init(subject: Subject, sentence: String, image: ImageCommands?) {
        self.subject = subject
        self.sentence = sentence
        self.image = image
    }

    /// Stated in words (a run or a statement), as opposed to a line the answer only shows.
    public var isExplicit: Bool {
        if case .line = subject { return false }
        return true
    }

    /// Identifies the claim across answers, so one stated again is recognised.
    var key: String {
        switch subject {
        case let .runs(run, claimed):
            "runs|\(run.entrypoint ?? "-")|\(run.arguments.joined(separator: " "))|\(claimed.joined(separator: " "))"
        case let .statement(statement): "statement|\(statement.rawValue)"
        case let .line(line, _): "line|\(line.rawValue)|\(sentence)"
        }
    }
}
