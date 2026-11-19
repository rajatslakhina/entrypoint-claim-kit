/// Judges claims against Docker's rules for composing a container's process.
struct EntrypointEvaluator {
    let policy: EntrypointPolicy

    func judge(_ claim: EntrypointClaim) -> EntrypointFinding {
        let finding = raw(claim)
        if !policy.reportsCaveats, case .caveat = finding.outcome {
            return EntrypointFinding(claim: claim, outcome: .exact, actual: finding.actual, fix: finding.fix)
        }
        return finding
    }

    func raw(_ claim: EntrypointClaim) -> EntrypointFinding {
        switch claim.subject {
        case let .runs(run, claimed): runs(claim, run, claimed)
        case let .statement(statement): Self.statement(claim, statement)
        case let .line(line, _): Self.line(claim, line)
        }
    }

    func runs(_ claim: EntrypointClaim, _ run: DockerRun, _ claimed: [String]) -> EntrypointFinding {
        guard let image = claim.image else {
            return EntrypointFinding(claim: claim, outcome: .unchecked("no Dockerfile in the conversation"))
        }
        let launch = image.launch(run)
        guard launch.isKnown else {
            return EntrypointFinding(claim: claim, outcome: .unchecked("the base image decides what runs"))
        }
        // The words themselves, then each misreading's words, then the Dockerfile's words behind a base ENTRYPOINT
        // the claim spells out: a claim is never called wrong over a prefix the Dockerfile does not show.
        if !launch.refused, Self.matches(claimed, launch) {
            return EntrypointFinding(claim: claim, outcome: .exact, actual: launch.words)
        }
        // A wrapper ENTRYPOINT (`tini --`, `/entrypoint.sh`) runs the command it is handed.
        if image.entrypointHandsOn, run.entrypoint == nil, case let .known(cmd) = image.cmd,
           Self.matches(claimed, Launch(words: run.arguments.isEmpty ? cmd : run.arguments, prefixFromBase: false)) {
            return EntrypointFinding(claim: claim, outcome: .exact, actual: launch.words)
        }
        for (slip, words) in Misreadings.all(image, run) where words != launch.words {
            if Self.matches(claimed, Launch(words: words, prefixFromBase: false)) {
                return EntrypointFinding(claim: claim, outcome: .wrong(slip), actual: launch.words)
            }
        }
        if launch.prefixFromBase, !launch.words.isEmpty, claimed.count > launch.words.count,
           Self.same(Array(claimed.suffix(launch.words.count)), launch.words) {
            return EntrypointFinding(claim: claim, outcome: .exact, actual: launch.words)
        }
        if launch.refused {
            return EntrypointFinding(claim: claim, outcome: .wrong(nil), actual: [])
        }
        return EntrypointFinding(claim: claim, outcome: .unchecked("no known mistake explains the difference"),
                                 actual: launch.words)
    }

    /// Whether the claimed words name the process: the same words (a program may be named without its directory), or
    /// what the shell runs for a shell-form line.
    static func matches(_ claimed: [String], _ launch: Launch) -> Bool {
        if same(claimed, launch.words) { return true }
        guard let call = launch.shellCall, let script = call.last else { return false }
        if same(claimed, call) { return true }
        if ShellWords.isCompound(script) {
            return normalized(claimed.joined(separator: " ")) == normalized(script)
        }
        return ShellWords.split(script).map { same(claimed, $0) } ?? false
    }

    static func same(_ claimed: [String], _ actual: [String]) -> Bool {
        guard claimed.count == actual.count, let first = claimed.first, let program = actual.first else { return false }
        let programMatches = first == program || Launch.basename(first) == Launch.basename(program)
        return programMatches && claimed.dropFirst() == actual.dropFirst()
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func statement(_ claim: EntrypointClaim, _ statement: EntrypointClaim.Statement) -> EntrypointFinding {
        let outcome: EntrypointFinding.Outcome = switch statement {
        case .argumentsReplaceCmd, .overrideClearsCmd, .shellEntrypointIgnoresArguments, .lastCmdCounts,
             .entrypointResetsBaseCmd, .execFormNeedsDoubleQuotes:
            .exact
        case .argumentsAppendToEntrypoint:
            claim.image?.entrypointIsShellForm == true ? .wrong(.shellFormTakesArguments) : .exact
        case .argumentsAppendToCmd: .wrong(.argumentsAppendToCmd)
        case .argumentsReplaceEntrypoint: .wrong(.argumentsReplaceEntrypoint)
        case .overrideKeepsCmd: .wrong(.overrideKeepsCmd)
        case .shellEntrypointTakesArguments: .wrong(.shellFormTakesArguments)
        case .everyCmdRuns: .wrong(.earlierCmdCounts)
        case .entrypointKeepsBaseCmd: .wrong(.entrypointKeepsBaseCmd)
        case .singleQuotesWork: .wrong(.brokenExecForm)
        }
        return EntrypointFinding(claim: claim, outcome: outcome)
    }

    static func line(_ claim: EntrypointClaim, _ line: EntrypointClaim.Line) -> EntrypointFinding {
        let image = claim.image
        let actual = image.map { $0.launch(DockerRun(image: "")).words } ?? []
        switch line {
        case .shellCmdUnderExecEntrypoint:
            return EntrypointFinding(claim: claim, outcome: .wrong(.shellCmdIsWords), actual: actual,
                                     fix: Fixes.execForm("CMD", image?.cmdLine))
        case .brokenExecForm:
            return EntrypointFinding(claim: claim, outcome: .wrong(.brokenExecForm), actual: actual,
                                     fix: Fixes.repaired(claim.sentence))
        case .notStringArray, .leadingFlag:
            return EntrypointFinding(claim: claim, outcome: .wrong(nil))
        case .shellEntrypointDropsCmd:
            return EntrypointFinding(claim: claim, outcome: .wrong(.shellFormTakesArguments), actual: actual,
                                     fix: Fixes.execForm("ENTRYPOINT", image?.entrypointLine))
        case .severalCmd, .severalEntrypoint:
            return EntrypointFinding(claim: claim, outcome: .caveat(.onlyLastCounts), actual: actual)
        case .inheritedCmdCleared:
            return EntrypointFinding(claim: claim, outcome: .caveat(.inheritedCmdCleared), actual: actual,
                                     fix: image?.clearedCmd.map { "CMD " + Fixes.json($0) })
        }
    }
}

/// Lines that do what a flagged line was meant to do.
enum Fixes {
    /// A shell-form line written in the exec form, when its text is one plain command.
    static func execForm(_ keyword: String, _ line: CommandInstruction?) -> String? {
        guard case let .shell(script)? = line?.form, !ShellWords.isCompound(script),
              let words = ShellWords.split(script), !words.isEmpty else { return nil }
        return keyword + " " + json(words)
    }

    /// A broken exec-form line with double quotes and no trailing comma.
    static func repaired(_ text: String) -> String? {
        let keyword = String(text.prefix { !$0.isWhitespace })
        let line = CommandInstruction.parsing(String(text.dropFirst(keyword.count)).trimmed, keyword: keyword)
        return line.intendedWords.map { keyword + " " + json($0) }
    }

    static func json(_ words: [String]) -> String {
        "[" + words.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\"" }.joined(separator: ", ") + "]"
    }
}

/// The processes a claim would describe under each recognisable misreading of Docker's rules.
enum Misreadings {
    typealias Reading = (EntrypointFinding.Slip, [String])

    static func all(_ image: ImageCommands, _ run: DockerRun) -> [Reading] {
        let entry = image.entrypoint.words ?? []
        let cmd = image.cmd.words ?? []
        if let override = run.entrypoint { return overridden(override, cmd, run) }
        var result = arguments(entry, cmd, run)
        if image.entrypointIsShellForm, let script = image.launch(DockerRun(image: "")).script,
           let words = ShellWords.split(script) {
            let tail = run.arguments.isEmpty ? cmd : run.arguments
            if !tail.isEmpty { result.append((.shellFormTakesArguments, words + tail)) }
        }
        return run.arguments.isEmpty ? result + lines(image, entry, cmd) : result
    }

    /// `--entrypoint` read as keeping `CMD`, or its value read as a command line.
    static func overridden(_ override: String, _ cmd: [String], _ run: DockerRun) -> [Reading] {
        var result: [Reading] = []
        if run.arguments.isEmpty, !cmd.isEmpty { result.append((.overrideKeepsCmd, [override] + cmd)) }
        if override.contains(where: \.isWhitespace), let words = ShellWords.split(override) {
            result.append((.overrideIsSplit, words + run.arguments))
        }
        return result
    }

    /// Arguments after the image read as added to `CMD`, or as replacing the `ENTRYPOINT`.
    static func arguments(_ entry: [String], _ cmd: [String], _ run: DockerRun) -> [Reading] {
        guard !run.arguments.isEmpty else { return [] }
        var result: [Reading] = []
        if !cmd.isEmpty { result.append((.argumentsAppendToCmd, entry + cmd + run.arguments)) }
        if !entry.isEmpty { result.append((.argumentsReplaceEntrypoint, run.arguments)) }
        return result
    }

    /// The Dockerfile's own lines read the way they look: an inherited `CMD` kept, the first `CMD` counting, a
    /// broken exec form read as JSON, a shell-form `CMD` read as plain words.
    static func lines(_ image: ImageCommands, _ entry: [String], _ cmd: [String]) -> [Reading] {
        var result: [Reading] = []
        if let cleared = image.clearedCmd { result.append((.entrypointKeepsBaseCmd, entry + cleared)) }
        if image.stageCmdLines.count > 1, let first = image.stageCmdLines.first {
            result.append((.earlierCmdCounts, entry + first.words(shell: image.shell)))
        }
        if let intended = image.cmdLine?.intendedWords { result.append((.brokenExecForm, entry + intended)) }
        if let intended = image.entrypointLine?.intendedWords { result.append((.brokenExecForm, intended + cmd)) }
        if !entry.isEmpty, !image.entrypointIsShellForm, case let .shell(script)? = image.cmdLine?.form,
           let words = ShellWords.split(script) {
            result.append((.shellCmdIsWords, entry + words))
        }
        return result
    }
}
