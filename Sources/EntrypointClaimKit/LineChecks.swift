/// `CMD`, `ENTRYPOINT` and `SHELL` lines of a Dockerfile that do not do what they look like.
enum LineChecks {
    static func claims(_ image: ImageCommands) -> [EntrypointClaim] {
        var found: [(EntrypointClaim.Line, CommandInstruction)] = image.stoppingLines.map { line in
            if case .stopsBuild(.leadingFlag) = line.form { return (.leadingFlag, line) }
            return (.notStringArray, line)
        }
        guard found.isEmpty else { return found.map { make($0.0, $0.1, image) } }
        let lines = [image.entrypointLine, image.cmdLine].compactMap { $0 }
        for line in lines where line.looksLikeBrokenExecForm { found.append((.brokenExecForm, line)) }
        if let cmd = image.cmdLine, case .shell = cmd.form, !cmd.looksLikeBrokenExecForm,
           case .exec(let entry)? = image.entrypointLine?.form, !entry.isEmpty, !image.entrypointHandsOn {
            found.append((.shellCmdUnderExecEntrypoint, cmd))
        }
        if image.entrypointIsShellForm, let entry = image.entrypointLine, !entry.looksLikeBrokenExecForm,
           image.cmd.words?.isEmpty == false {
            found.append((.shellEntrypointDropsCmd, entry))
        }
        if image.stageCmdLines.count > 1, let first = image.stageCmdLines.first { found.append((.severalCmd, first)) }
        if image.stageEntrypointLines.count > 1, let first = image.stageEntrypointLines.first {
            found.append((.severalEntrypoint, first))
        }
        if image.clearedCmd != nil, let entry = image.entrypointLine { found.append((.inheritedCmdCleared, entry)) }
        return found.map { make($0.0, $0.1, image) }
    }

    static func make(_ issue: EntrypointClaim.Line, _ line: CommandInstruction, _ image: ImageCommands)
        -> EntrypointClaim {
        EntrypointClaim(subject: .line(issue, lineNumber: line.lineNumber), sentence: line.keyword + " " + line.text,
                        image: image)
    }
}
