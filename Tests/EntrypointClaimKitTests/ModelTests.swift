import DockerfileClaimKit
import Testing
@testable import EntrypointClaimKit

@Suite("Image config model")
struct ModelTests {
    @Test("Forms of CMD and ENTRYPOINT lines")
    func forms() {
        #expect(CommandInstruction.form(of: #"["node", "a.js"]"#) == .exec(["node", "a.js"]))
        #expect(CommandInstruction.form(of: "node a.js") == .shell("node a.js"))
        #expect(CommandInstruction.form(of: "['node']") == .shell("['node']"))
        #expect(CommandInstruction.form(of: #"["node", 1]"#) == .stopsBuild(.notStringArray))
        #expect(CommandInstruction.form(of: "--port 80") == .stopsBuild(.leadingFlag))
        let broken = CommandInstruction.parsing("['node', 'a.js',]", keyword: "CMD")
        #expect(broken.looksLikeBrokenExecForm)
        #expect(broken.intendedWords == ["node", "a.js"])
        #expect(broken.words(shell: ["/bin/sh", "-c"]) == ["/bin/sh", "-c", "['node', 'a.js',]"])
        #expect(CommandInstruction.parsing("['a' 'b']", keyword: "CMD").intendedWords == nil)
        #expect(CommandInstruction.parsing("[oops", keyword: "CMD").intendedWords == nil)
        #expect(CommandInstruction.parsing("node", keyword: "CMD").intendedWords == nil)
        #expect(!CommandInstruction.parsing(#"["a"]"#, keyword: "CMD").looksLikeBrokenExecForm)
        #expect(CommandInstruction.parsing(#"["a", 1]"#, keyword: "CMD").words(shell: []) == [])
    }

    @Test("FROM lines, stage names and the base images")
    func stages() {
        #expect(ImageCommands.from("--platform=linux/amd64 node:20 AS Build") == ("node:20", "Build"))
        #expect(ImageCommands.from("node:20") == ("node:20", nil))
        #expect(ImageCommands.from("") == ("", nil))
        let config = image("ARG V=1", "FROM node:${V} AS build", "CMD [\"a\"]", "FROM BUILD", "RUN true")
        #expect(config.cmd == .known(["a"]))
        #expect(config.baseImages == ["node:${V}"])
        #expect(config.cmdLine?.lineNumber == 3)
        #expect(config.stageCmdLines.isEmpty)
        let scratch = image("FROM scratch", "COPY app /app")
        #expect(scratch.entrypoint == .known([]))
        #expect(scratch.launch(DockerRun(image: "x")).refused)
        #expect(scratch.baseImages == ["scratch"])
    }

    @Test("Lines before any FROM, SHELL lines that are not exec form, and an empty Dockerfile")
    func oddLines() {
        #expect(image("CMD [\"x\"]", "FROM a", "SHELL /bin/bash -c", "CMD y").cmd == .known(["/bin/sh", "-c", "y"]))
        #expect(image("FROM a", "SHELL []", "CMD y").shell == ["/bin/sh", "-c"])
        let empty = ImageCommands(Dockerfile(""))
        #expect(empty.entrypoint == .fromBase && empty.cmd == .fromBase)
        #expect(!empty.launch(DockerRun(image: "x")).isKnown)
        #expect(ConfigValue.fromBase.words == nil)
    }

    @Test("ENTRYPOINT empties an inherited CMD, and remembers it")
    func clearedCmd() {
        let config = image("FROM node AS base", "CMD [\"node\", \"a.js\"]", "FROM base", "ENTRYPOINT [\"tini\", \"--\"]")
        #expect(config.clearedCmd == ["node", "a.js"])
        #expect(config.cmd == .known([]))
        #expect(image("FROM node", "ENTRYPOINT [\"tini\"]").clearedCmd == nil)
    }

    @Test("What the daemon executes")
    func launch() {
        let config = image("FROM a", "ENTRYPOINT [\"python\", \"app.py\"]", "CMD [\"--port\", \"80\"]")
        #expect(config.launch(DockerRun(image: "x")).words == ["python", "app.py", "--port", "80"])
        #expect(config.launch(DockerRun(image: "x", arguments: ["-v"])).words == ["python", "app.py", "-v"])
        #expect(config.launch(DockerRun(image: "x", entrypoint: "sh")).words == ["sh"])
        #expect(config.launch(DockerRun(image: "x", entrypoint: "")).refused)
        let tail = image("FROM node", "CMD [\"node\"]").launch(DockerRun(image: "x"))
        #expect(tail.prefixFromBase && tail.words == ["node"] && !tail.refused)
    }

    @Test("A launch through a shell, and how it is shown")
    func script() {
        #expect(Launch(words: ["/bin/sh", "-c", "a b"], prefixFromBase: false).script == "a b")
        #expect(Launch(words: ["/bin/bash", "-o", "pipefail", "-c", "a"], prefixFromBase: false).script == "a")
        #expect(Launch(words: ["python", "-c", "x"], prefixFromBase: false).script == nil)
        #expect(Launch(words: ["sh", "-c"], prefixFromBase: false).script == nil)
        #expect(Launch(words: ["sh", "x"], prefixFromBase: false).script == nil)
        #expect(Launch(words: [], prefixFromBase: false).script == nil)
        #expect(Launch(words: ["sh", "-c", #"say "hi" \ $x"#, ""], prefixFromBase: false).display
            == #"sh -c "say \"hi\" \\ $x" """#)
        #expect(Launch.basename("/usr/bin/node") == "node")
        #expect(Launch.basename("/") == "/")
    }
}
