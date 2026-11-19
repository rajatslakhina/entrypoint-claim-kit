import Testing
@testable import EntrypointClaimKit

@Suite("Judging run claims, statements and lines")
struct EvaluatorTests {
    func runClaim(_ config: ImageCommands?, _ run: DockerRun, _ claimed: String) -> EntrypointFinding {
        let claim = EntrypointClaim(subject: .runs(run, claimed: ShellWords.split(claimed) ?? []), sentence: "",
                                    image: config)
        return EntrypointClaimChecker().judge(claim)
    }

    let python = image("FROM python", "ENTRYPOINT [\"python\", \"app.py\"]", "CMD [\"--port\", \"80\"]")

    @Test("Runs that hold, including a program named by its path and the shell's script")
    func holds() {
        #expect(runClaim(python, DockerRun(image: "a"), "/usr/local/bin/python app.py --port 80").outcome == .exact)
        let shell = image("FROM a", "CMD npm run migrate && npm start")
        #expect(runClaim(shell, DockerRun(image: "a"), "npm run migrate  &&  npm start").outcome == .exact)
        #expect(runClaim(shell, DockerRun(image: "a"), "/bin/sh -c 'npm run migrate && npm start'").outcome == .exact)
        let plain = image("FROM a", "CMD node server.js")
        #expect(runClaim(plain, DockerRun(image: "a"), "node server.js").outcome == .exact)
        let base = image("FROM node", "CMD [\"node\", \"server.js\"]")
        #expect(runClaim(base, DockerRun(image: "a"), "docker-entrypoint.sh node server.js").outcome == .exact)
    }

    @Test("Each misreading of the rules", arguments: [
        (["FROM a", "ENTRYPOINT [\"p\"]", "CMD [\"c\"]"], DockerRun(image: "a", arguments: ["x"]), "p c x",
         EntrypointFinding.Slip.argumentsAppendToCmd),
        (["FROM a", "ENTRYPOINT [\"p\"]"], DockerRun(image: "a", arguments: ["bash"]), "bash", .argumentsReplaceEntrypoint),
        (["FROM a", "ENTRYPOINT p run", "CMD [\"c\"]"], DockerRun(image: "a"), "p run c", .shellFormTakesArguments),
        (["FROM a", "ENTRYPOINT p run"], DockerRun(image: "a", arguments: ["x"]), "p run x", .shellFormTakesArguments),
        (["FROM a", "ENTRYPOINT [\"p\"]", "CMD [\"c\"]"], DockerRun(image: "a", entrypoint: "sh"), "sh c", .overrideKeepsCmd),
        (["FROM a", "ENTRYPOINT [\"p\"]"], DockerRun(image: "a", arguments: ["ls"], entrypoint: "sh -c"), "sh -c ls",
         .overrideIsSplit),
        (["FROM a AS b", "CMD [\"c\"]", "FROM b", "ENTRYPOINT [\"p\"]"], DockerRun(image: "a"), "p c", .entrypointKeepsBaseCmd),
        (["FROM a", "CMD [\"one\"]", "CMD [\"two\"]"], DockerRun(image: "a"), "one", .earlierCmdCounts),
        (["FROM a", "CMD ['node', 'a.js']"], DockerRun(image: "a"), "node a.js", .brokenExecForm),
        (["FROM a", "ENTRYPOINT ['p']", "CMD [\"c\"]"], DockerRun(image: "a"), "p c", .brokenExecForm),
        (["FROM a", "ENTRYPOINT [\"p\"]", "CMD q --port 80"], DockerRun(image: "a"), "p q --port 80", .shellCmdIsWords)
    ])
    func slips(_ lines: [String], _ run: DockerRun, _ claimed: String, _ slip: EntrypointFinding.Slip) {
        let config = ImageCommands(.init(lines.joined(separator: "\n")))
        #expect(runClaim(config, run, claimed).outcome == .wrong(slip))
    }

    @Test("Runs that cannot be checked, and a run Docker refuses")
    func unchecked() {
        #expect(runClaim(nil, DockerRun(image: "a"), "x").severity == .unchecked)
        #expect(runClaim(image("FROM a", "RUN true"), DockerRun(image: "a"), "x").severity == .unchecked)
        #expect(runClaim(python, DockerRun(image: "a"), "node x.js").severity == .unchecked)
        let refused = runClaim(python, DockerRun(image: "a", entrypoint: ""), "python app.py")
        #expect(refused.outcome == .wrong(nil))
        #expect(refused.explanation.contains("no command specified"))
        #expect(runClaim(image("FROM a", "CMD echo \"hi"), DockerRun(image: "a"), "echo hi").severity == .unchecked)
        #expect(runClaim(image("FROM a", "RUN true"), DockerRun(image: "a", entrypoint: "sh"), "sh -l").severity
            == .unchecked)
        let empty = image("FROM scratch", "CMD []")
        #expect(runClaim(empty, DockerRun(image: "a"), "app").outcome == .wrong(nil))
    }

    @Test("Statements", arguments: EntrypointClaim.Statement.allCases)
    func statements(_ statement: EntrypointClaim.Statement) {
        let finding = EntrypointClaimChecker().judge(EntrypointClaim(subject: .statement(statement), sentence: "",
                                                                     image: nil))
        let holds: Set<EntrypointClaim.Statement> = [.argumentsReplaceCmd, .overrideClearsCmd, .lastCmdCounts,
                                                    .shellEntrypointIgnoresArguments, .entrypointResetsBaseCmd,
                                                    .execFormNeedsDoubleQuotes, .argumentsAppendToEntrypoint]
        #expect((finding.severity == .holds) == holds.contains(statement))
        #expect(!finding.explanation.isEmpty)
    }

    @Test("Arguments follow a shell-form ENTRYPOINT: no, they never reach it")
    func shellEntrypointArguments() {
        let claim = EntrypointClaim(subject: .statement(.argumentsAppendToEntrypoint), sentence: "",
                                    image: image("FROM a", "ENTRYPOINT p"))
        let finding = EntrypointClaimChecker().judge(claim)
        #expect(finding.outcome == .wrong(.shellFormTakesArguments))
        #expect(finding.explanation.contains("shell-form ENTRYPOINT"))
    }

    @Test("Every line issue has an outcome and a sentence", arguments: EntrypointClaim.Line.allCases)
    func lines(_ line: EntrypointClaim.Line) {
        let config = image("FROM a AS b", "CMD [\"c\"]", "FROM b", "ENTRYPOINT p x", "CMD q")
        let finding = EntrypointClaimChecker().judge(EntrypointClaim(subject: .line(line, lineNumber: 4),
                                                                     sentence: "CMD ['q']", image: config))
        #expect(finding.severity >= .caution)
        #expect(finding.explanation.contains("(line 4)"))
        let bare = EntrypointClaimChecker().judge(EntrypointClaim(subject: .line(line, lineNumber: 1), sentence: "CMD x",
                                                                  image: nil))
        #expect(bare.actual.isEmpty)
    }

    @Test("The lenient policy counts caveats as holding")
    func lenient() {
        let claim = EntrypointClaim(subject: .line(.severalCmd, lineNumber: 2), sentence: "CMD a",
                                    image: image("FROM a", "CMD a", "CMD b"))
        #expect(EntrypointClaimChecker().judge(claim).severity == .caution)
        #expect(EntrypointClaimChecker(policy: .lenient).judge(claim).severity == .holds)
        #expect(EntrypointClaimChecker(policy: .lenient).judge(EntrypointClaim(subject: .statement(.everyCmdRuns),
                                                                               sentence: "", image: nil)).severity == .wrong)
    }

    @Test("Every slip is explained", arguments: EntrypointFinding.Slip.allCases)
    func reasons(_ slip: EntrypointFinding.Slip) {
        #expect(!EntrypointFinding.reason(slip).isEmpty)
    }

    @Test("Fixes")
    func fixes() {
        #expect(Fixes.execForm("CMD", CommandInstruction.parsing("node a.js", keyword: "CMD")) == #"CMD ["node", "a.js"]"#)
        #expect(Fixes.execForm("CMD", CommandInstruction.parsing("a && b", keyword: "CMD")) == nil)
        #expect(Fixes.execForm("CMD", nil) == nil)
        #expect(Fixes.repaired("CMD ['a', 'b']") == #"CMD ["a", "b"]"#)
        #expect(Fixes.json(["say \"hi\"", #"C:\x"#]) == #"["say \"hi\"", "C:\\x"]"#)
    }
}
