import Testing
@testable import EntrypointClaimKit

@Suite("Reading statements, runs and tags")
struct ReaderTests {
    @Test("Statements read from a sentence", arguments: [
        ("Arguments passed to `docker run` after the image name replace CMD.", [EntrypointClaim.Statement.argumentsReplaceCmd]),
        ("The CMD is overridden by any arguments you give `docker run`.", [.argumentsReplaceCmd]),
        ("Arguments to `docker run` are appended to the CMD.", [.argumentsAppendToCmd]),
        ("Arguments you pass to `docker run` replace the ENTRYPOINT.", [.argumentsReplaceEntrypoint]),
        ("Anything after the image name in `docker run` replaces CMD and is appended to the ENTRYPOINT.",
         [.argumentsReplaceCmd]),
        ("With `--entrypoint`, Docker also clears CMD.", [.overrideClearsCmd]),
        ("The `--entrypoint` flag keeps the CMD and passes it to the new entrypoint.", [.overrideKeepsCmd]),
        ("The `--entrypoint` flag keeps CMD but also drops CMD.", []),
        ("With `--entrypoint bash`, the arguments you give are passed to bash and CMD is gone.", [.overrideClearsCmd]),
        ("With `--entrypoint`, the image's CMD is still passed to the new program.", [.overrideKeepsCmd]),
        ("If you have multiple CMD lines, only the last one is executed.", [.lastCmdCounts]),
        ("The ENTRYPOINT empties the CMD, so the final stage sets it again and `docker run api` runs the app.", []),
        ("In the exec form of CMD, single quotes fail and double quotes work.", []),
        ("In shell-form CMD, single quotes work fine.", []),
        ("Single quotes, in the JSON form of CMD, are a problem.", []),
        ("Setting CMD keeps the ENTRYPOINT inherited from the base image.", []),
        ("Arguments on the `docker run` command line override the ENTRYPOINT's default arguments, which come from CMD.",
         []),
        ("Setting ENTRYPOINT resets and keeps the CMD inherited from the base image.", []),
        ("The CMD inherited from the base image is reset by ENTRYPOINT.", []),
        ("A shell form ENTRYPOINT ignores CMD and any arguments.", [.shellEntrypointIgnoresArguments]),
        ("In shell form, the ENTRYPOINT still receives the CMD as arguments.", [.shellEntrypointTakesArguments]),
        ("Only the last CMD takes effect.", [.lastCmdCounts]),
        ("Each CMD runs in order when the container starts.", [.everyCmdRuns]),
        ("Setting ENTRYPOINT resets the CMD inherited from the base image.", [.entrypointResetsBaseCmd]),
        ("Setting ENTRYPOINT keeps the CMD from the base image.", [.entrypointKeepsBaseCmd]),
        ("Single quotes work fine in the exec form of CMD.", [.singleQuotesWork]),
        ("The exec form of CMD must use double quotes.", [.execFormNeedsDoubleQuotes]),
        ("Arguments to `docker run` do not replace the ENTRYPOINT.", []),
        ("Arguments to `docker run` won't replace the ENTRYPOINT.", []),
        ("In docker compose, `command:` replaces CMD.", []),
        ("Arguments to `docker run` replace the cmd in Windows.", []),
        ("The entrypoint script runs first.", []),
        ("Arguments to the CMD are parsed by the program.", []),
        ("A shell form ENTRYPOINT ignores any arguments you pass.", [.shellEntrypointIgnoresArguments]),
        ("Arguments to `docker run` override and replace CMD.", [.argumentsReplaceCmd])
    ])
    func statements(_ sentence: String, _ expected: [EntrypointClaim.Statement]) {
        #expect(StatementReader.statements(in: sentence, image: nil) == expected)
    }

    @Test("Arguments follow the ENTRYPOINT: read only when the Dockerfile has one")
    func appendToEntrypoint() {
        let sentence = "Arguments to `docker run` are appended to the ENTRYPOINT."
        #expect(StatementReader.statements(in: sentence, image: nil).isEmpty)
        #expect(StatementReader.statements(in: sentence, image: image("FROM a", "ENTRYPOINT [\"p\"]"))
            == [.argumentsAppendToEntrypoint])
        #expect(StatementReader.pick("x", ["y"], .lastCmdCounts, ["z"], .everyCmdRuns).isEmpty)
    }

    @Test("Image tags from docker build", arguments: [
        ("docker build -t api .", ["api"]), ("docker build --tag=api:latest .", ["api"]), ("docker build -tapi:2 .", ["api:2"]),
        ("docker buildx build --tag Api .", ["api"]), ("docker image build -t a -t b .", ["a", "b"]),
        ("docker run -t api", []), ("cd x && docker build -t api . && docker run api", ["api"]), ("docker build -t", []),
        ("docker 'build", [])
    ])
    func tags(_ line: String, _ expected: [String]) {
        #expect(Tags.find(in: [line]) == Set(expected))
    }

    @Test("Whether a text is about what a container runs")
    func about() {
        #expect(EntrypointClaimReader.isAboutContainerCommands("Set CMD in the image."))
        #expect(EntrypointClaimReader.isAboutContainerCommands("Use `--entrypoint` to override it."))
        #expect(EntrypointClaimReader.isAboutContainerCommands("Then `docker run app`."))
        #expect(EntrypointClaimReader.isAboutContainerCommands(dockerfile("FROM a", "RUN true")))
        #expect(!EntrypointClaimReader.isAboutContainerCommands("\(fence)python\nprint(1)\n\(fence)\nThe cmd tool."))
    }

    @Test("A run in a code block, with a prompt, then a sentence about it")
    func codeBlockRun() {
        let text = pythonApp + "\(fence)bash\n$ docker build -t api .\n$ docker run --rm api --verbose\n\(fence)\n"
            + "This runs `python app.py --verbose`."
        let report = check(text)
        #expect(report.verdict == .verified)
        #expect(EntrypointClaimReader.command("$ docker run x") == "docker run x")
    }

    @Test("A sentence's verb comes right before the claimed words")
    func verbs() {
        #expect(RunClaimReader.endsWithVerb("then it runs "))
        #expect(RunClaimReader.endsWithVerb("runs"))
        #expect(!RunClaimReader.endsWithVerb("reruns "))
        #expect(!RunClaimReader.endsWithVerb("and "))
    }

    @Test("The Dockerfile can come from the question or from an earlier turn")
    func sources() {
        let question = "Here is my Dockerfile:\n" + pythonApp
        let report = check(built + "`docker run api --port 9` runs `python app.py --port 9`.", context: question)
        #expect(report.verdict == .verified)
        var earlier = Earlier()
        EntrypointClaimReader.remember(pythonApp + built, context: "", into: &earlier)
        #expect(earlier.dockerfile != nil && earlier.tags == ["api"])
        let claims = EntrypointClaimReader().allClaims(in: "`docker run api` runs `python app.py --port 80`.", context: "",
                                                       earlier: earlier)
        #expect(claims.count == 1)
    }

    @Test("Lines are read only from the answer's own Dockerfile, and only when asked")
    func linesOnlyWhenShown() {
        let broken = dockerfile("FROM a", "CMD ['node', 'a.js']")
        #expect(check(broken).lines == [.brokenExecForm])
        #expect(check("Looks fine.", context: broken).findings.isEmpty)
        #expect(check(broken, policy: EntrypointPolicy(checksLines: false)).findings.isEmpty)
    }
}
