extension EntrypointFinding {
    /// One sentence a reader can act on.
    public var explanation: String {
        switch claim.subject {
        case let .runs(run, claimed): runExplanation(run, claimed)
        case let .statement(statement): Self.statementExplanation(statement, outcome)
        case let .line(line, number): lineExplanation(line, number)
        }
    }

    func runExplanation(_ run: DockerRun, _ claimed: [String]) -> String {
        let said = "`" + Launch(words: claimed, prefixFromBase: false).display + "`"
        let invocation = Self.display(run)
        switch outcome {
        case .exact, .caveat:
            return "\(invocation) runs \(said)\(afterBase(run)), as the answer says."
        case let .unchecked(reason):
            return "\(invocation) was not checked against \(said): \(reason)."
        case let .wrong(slip):
            // A wrong run claim has a recognisable slip unless Docker refuses to start the container at all.
            guard !actual.isEmpty, let slip else {
                return "\(invocation) starts nothing: with no ENTRYPOINT and no command, Docker refuses with "
                    + "\"no command specified\"."
            }
            let real = "`" + Launch(words: actual, prefixFromBase: false).display + "`"
            return "\(invocation) does not run \(said): it runs \(real)\(afterBase(run)) (\(Self.reason(slip)))."
        }
    }

    /// The base image's `ENTRYPOINT`, which the Dockerfile does not show, comes first.
    func afterBase(_ run: DockerRun) -> String {
        let fromBase = run.entrypoint == nil && claim.image?.entrypoint == .fromBase
        return fromBase ? " after the base image's ENTRYPOINT, if any" : ""
    }

    static func display(_ run: DockerRun) -> String {
        guard !run.image.isEmpty else {
            return run.arguments.isEmpty && run.entrypoint == nil ? "Starting the container" : "That run"
        }
        var words = ["docker", "run"]
        if let entrypoint = run.entrypoint { words += ["--entrypoint", Launch.quoted(entrypoint)] }
        words.append(run.image)
        words += run.arguments.map(Launch.quoted)
        return "`" + words.joined(separator: " ") + "`"
    }

    static func reason(_ slip: Slip) -> String {
        switch slip {
        case .argumentsAppendToCmd: "arguments after the image replace CMD; they are not added to it"
        case .argumentsReplaceEntrypoint:
            "arguments after the image follow the ENTRYPOINT; only --entrypoint replaces it"
        case .shellFormTakesArguments:
            "a shell-form ENTRYPOINT runs `sh -c` with its text, which never uses CMD or the run's arguments"
        case .overrideKeepsCmd: "--entrypoint drops the image's CMD"
        case .overrideIsSplit: "--entrypoint names one executable; its value is never split into words"
        case .entrypointKeepsBaseCmd:
            "an ENTRYPOINT empties the CMD the stage inherited unless the stage sets CMD itself"
        case .earlierCmdCounts: "only the last CMD counts"
        case .brokenExecForm:
            "the array is not JSON, because of single quotes or a trailing comma, so Docker runs it as shell-form text"
        case .shellCmdIsWords:
            "a shell-form CMD is stored as `/bin/sh -c \"...\"`, and those words follow the ENTRYPOINT"
        }
    }

    static func statementExplanation(_ statement: EntrypointClaim.Statement, _ outcome: Outcome) -> String {
        let holds = "The statement about \(topic(statement)) holds."
        return switch statement {
        case .argumentsReplaceCmd, .overrideClearsCmd, .shellEntrypointIgnoresArguments, .lastCmdCounts,
             .entrypointResetsBaseCmd, .execFormNeedsDoubleQuotes:
            holds
        case .argumentsAppendToEntrypoint:
            outcome == .exact ? holds : "Arguments to `docker run` do not reach this shell-form ENTRYPOINT: `sh -c` "
                + "ignores them. Use the exec form."
        case .argumentsAppendToCmd:
            "Arguments after the image in `docker run` replace CMD; they are not appended to it."
        case .argumentsReplaceEntrypoint:
            "Arguments after the image do not replace the ENTRYPOINT: they are passed to it. Only `--entrypoint` "
                + "replaces it."
        case .overrideKeepsCmd:
            "`--entrypoint` also drops the image's CMD: the new entrypoint gets only the arguments given after the "
                + "image."
        case .shellEntrypointTakesArguments:
            "A shell-form ENTRYPOINT receives neither CMD nor `docker run` arguments: `sh -c` takes them as `$0`, "
                + "`$1`, ... and the text never uses them."
        case .everyCmdRuns:
            "Only the last CMD in a Dockerfile takes effect; earlier CMD lines do nothing."
        case .entrypointKeepsBaseCmd:
            "Setting ENTRYPOINT empties a CMD inherited from the base image; set CMD again in the same stage."
        case .singleQuotesWork:
            "The exec form is JSON and needs double quotes: with single quotes Docker runs the text through the shell, "
                + "which fails to find a command named like the array."
        }
    }

    static func topic(_ statement: EntrypointClaim.Statement) -> String {
        switch statement {
        case .argumentsReplaceCmd, .argumentsAppendToCmd, .argumentsAppendToEntrypoint, .argumentsReplaceEntrypoint:
            "`docker run` arguments"
        case .overrideClearsCmd, .overrideKeepsCmd: "`--entrypoint`"
        case .shellEntrypointIgnoresArguments, .shellEntrypointTakesArguments: "a shell-form ENTRYPOINT"
        case .lastCmdCounts, .everyCmdRuns: "several CMD lines"
        case .entrypointResetsBaseCmd, .entrypointKeepsBaseCmd: "a CMD inherited from the base"
        case .execFormNeedsDoubleQuotes, .singleQuotesWork: "quotes in the exec form"
        }
    }

    func lineExplanation(_ line: EntrypointClaim.Line, _ number: Int) -> String {
        let shown = "`" + claim.sentence + "` (line \(number))"
        let shownRun = Launch(words: actual, prefixFromBase: false).display
        let runs = actual.isEmpty ? "" : ": the container runs `" + shownRun + "`"
        let instead = fix.map { " Use `" + $0 + "`." } ?? ""
        return switch line {
        case .shellCmdUnderExecEntrypoint:
            "\(shown) is shell form under an exec-form ENTRYPOINT, so the ENTRYPOINT receives `/bin/sh`, `-c` and the "
                + "text\(runs).\(instead)"
        case .brokenExecForm:
            "\(shown) is not JSON, so Docker runs it as shell-form text and the shell looks for a command named like "
                + "the array\(runs).\(instead)"
        case .notStringArray:
            "\(shown) stops the build: an exec-form array may hold only strings. Quote every element."
        case .leadingFlag:
            "\(shown) stops the build: Docker reads the leading `--` word as a flag of the instruction. Use the exec "
                + "form."
        case .shellEntrypointDropsCmd:
            "\(shown) is a shell-form ENTRYPOINT, so the CMD never reaches the program\(runs).\(instead)"
        case .severalCmd:
            "\(shown) is not the only CMD in the final stage; only the last one takes effect\(runs)."
        case .severalEntrypoint:
            "\(shown) is not the only ENTRYPOINT in the final stage; only the last one takes effect\(runs)."
        case .inheritedCmdCleared:
            "\(shown) empties the CMD this stage inherited from the stage it is built on\(runs).\(instead)"
        }
    }
}
