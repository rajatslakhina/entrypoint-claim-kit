/// What a claim about a container's command turned out to be once Docker's rules were applied.
public struct EntrypointFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    public enum Caveat: String, Sendable, Hashable, CaseIterable {
        /// Several `CMD` or `ENTRYPOINT` lines: only the last one counts.
        case onlyLastCounts
        /// The `ENTRYPOINT` empties the `CMD` inherited from an earlier stage.
        case inheritedCmdCleared
    }

    /// A recognisable mistake behind a wrong claim.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// Arguments after the image read as added to `CMD`: they replace it.
        case argumentsAppendToCmd
        /// Arguments after the image read as replacing the `ENTRYPOINT`: they follow it; only `--entrypoint` replaces
        /// it.
        case argumentsReplaceEntrypoint
        /// A shell-form `ENTRYPOINT` read as receiving `CMD` or arguments: `sh -c` takes them as `$0`, `$1`, ... and
        /// the text never uses them.
        case shellFormTakesArguments
        /// `--entrypoint` read as keeping the image's `CMD`: it drops it.
        case overrideKeepsCmd
        /// `--entrypoint "a b"` read as a command line: Docker looks for one executable named `a b`.
        case overrideIsSplit
        /// `ENTRYPOINT` read as keeping the `CMD` from the stage it builds on: it empties it.
        case entrypointKeepsBaseCmd
        /// An earlier `CMD` line read as taking effect: only the last one does.
        case earlierCmdCounts
        /// Single quotes or a trailing comma read as the exec form: it is not JSON, so it is the shell form.
        case brokenExecForm
        /// A shell-form `CMD` under an exec-form `ENTRYPOINT` read as plain words: Docker stores `/bin/sh -c "..."`.
        case shellCmdIsWords
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: EntrypointClaim
    public let outcome: Outcome
    /// What the daemon executes (for a run claim, or a line that changes it).
    public let actual: [String]
    /// A line that does what the claim expected, where there is an obvious one.
    public let fix: String?
    /// Flagged in an earlier review of the same conversation (set by `EntrypointLedger`).
    public internal(set) var isRepeated = false

    init(claim: EntrypointClaim, outcome: Outcome, actual: [String] = [], fix: String? = nil) {
        self.claim = claim
        self.outcome = outcome
        self.actual = actual
        self.fix = fix
    }

    public var severity: Severity {
        switch outcome {
        case .exact: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    var key: String {
        claim.key
    }

    /// The mistake behind a wrong finding, if it is a recognisable one.
    public var slip: Slip? {
        if case let .wrong(slip) = outcome { return slip }
        return nil
    }
}

/// How strictly claims are judged.
public struct EntrypointPolicy: Sendable, Hashable {
    /// Also report `CMD`/`ENTRYPOINT` lines of the answer's Dockerfile that do not do what they look like.
    public var checksLines: Bool
    /// Report claims that hold with a caveat as cautions; when `false` they count as holding.
    public var reportsCaveats: Bool

    public init(checksLines: Bool = true, reportsCaveats: Bool = true) {
        self.checksLines = checksLines
        self.reportsCaveats = reportsCaveats
    }

    public static let standard = EntrypointPolicy()
    public static let lenient = EntrypointPolicy(checksLines: false, reportsCaveats: false)
}
