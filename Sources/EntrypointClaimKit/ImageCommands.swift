import DockerfileClaimKit

/// A field of the image config (`Entrypoint` or `Cmd`) that the Dockerfile may or may not settle.
public enum ConfigValue: Sendable, Hashable {
    /// Settled by this Dockerfile (or by `FROM scratch`): the words Docker stores; empty means none.
    case known([String])
    /// Comes from a base image the Dockerfile does not show.
    case fromBase

    public var words: [String]? {
        if case let .known(words) = self { return words }
        return nil
    }
}

/// What a Dockerfile's final stage leaves in the image config for starting a container: `Entrypoint`, `Cmd`, the
/// lines that set them, and what the Dockerfile's own lines did along the way. Built with the dispatch rules the
/// classic builder and BuildKit share: a later `CMD` or `ENTRYPOINT` replaces an earlier one; `SHELL` sets the shell
/// for shell-form lines; a stage built `FROM` an earlier stage starts with that stage's values; and `ENTRYPOINT`
/// empties a `CMD` the stage inherited, unless the stage set `CMD` itself before it.
public struct ImageCommands: Sendable, Hashable {
    public internal(set) var entrypoint: ConfigValue
    public internal(set) var cmd: ConfigValue
    /// The `ENTRYPOINT` line in effect, when this Dockerfile set it.
    public internal(set) var entrypointLine: CommandInstruction?
    /// The `CMD` line in effect, when this Dockerfile set it and no later `ENTRYPOINT` emptied it.
    public internal(set) var cmdLine: CommandInstruction?
    /// The shell for shell-form lines: `/bin/sh -c` unless a `SHELL` line changed it.
    public internal(set) var shell: [String] = ["/bin/sh", "-c"]
    /// The final stage's own `CMD` lines, in order (only the last one counts).
    public internal(set) var stageCmdLines: [CommandInstruction] = []
    /// The final stage's own `ENTRYPOINT` lines, in order.
    public internal(set) var stageEntrypointLines: [CommandInstruction] = []
    /// A `CMD` the final stage inherited from an earlier stage and its `ENTRYPOINT` then emptied, unless a later
    /// `CMD` in the stage set one again.
    public internal(set) var clearedCmd: [String]?
    /// `CMD`, `ENTRYPOINT` and `SHELL` lines anywhere in the Dockerfile on which the build stops.
    public internal(set) var stoppingLines: [CommandInstruction] = []
    /// The images the stages start from, other than earlier stages (to tell a `docker run` of a base apart).
    public internal(set) var baseImages: [String] = []
    private var cmdSetInStage = false

    init(entrypoint: ConfigValue, cmd: ConfigValue) {
        self.entrypoint = entrypoint
        self.cmd = cmd
    }

    /// The image config of the Dockerfile's last stage.
    public init(_ dockerfile: Dockerfile) {
        var stages: [ImageCommands] = []
        var names: [String: Int] = [:]
        var stopping: [CommandInstruction] = []
        var bases: [String] = []
        for instruction in dockerfile.instructions {
            if instruction.keyword == "FROM" {
                let (image, name) = Self.from(instruction.arguments)
                if names[image.lowercased()] == nil { bases.append(image) }
                let stage = Self.start(image, stages: stages, names: names)
                if let name { names[name.lowercased()] = stages.count }
                stages.append(stage)
                continue
            }
            let line = CommandInstruction(instruction)
            if ["CMD", "ENTRYPOINT", "SHELL"].contains(instruction.keyword), case .stopsBuild = line.form {
                stopping.append(line)
                continue
            }
            guard !stages.isEmpty else { continue }
            stages[stages.count - 1].apply(line)
        }
        self = stages.last ?? ImageCommands(entrypoint: .fromBase, cmd: .fromBase)
        stoppingLines = stopping
        baseImages = bases
    }

    /// `FROM [--platform=...] image [AS name]`: the image and the stage name.
    static func from(_ arguments: String) -> (image: String, name: String?) {
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.hasPrefix("--") }
        let name = words.count >= 3 && words[1].lowercased() == "as" ? words[2] : nil
        return (words.first ?? "", name)
    }

    static func start(_ image: String, stages: [ImageCommands], names: [String: Int]) -> ImageCommands {
        if let index = names[image.lowercased()] {
            var stage = stages[index]
            stage.cmdSetInStage = false
            stage.stageCmdLines = []
            stage.stageEntrypointLines = []
            stage.clearedCmd = nil
            return stage
        }
        if image.lowercased() == "scratch" {
            return ImageCommands(entrypoint: .known([]), cmd: .known([]))
        }
        return ImageCommands(entrypoint: .fromBase, cmd: .fromBase)
    }

    mutating func apply(_ line: CommandInstruction) {
        switch line.keyword {
        case "SHELL":
            if case let .exec(words) = line.form, !words.isEmpty { shell = words }
        case "CMD":
            cmd = .known(line.words(shell: shell))
            cmdLine = line
            cmdSetInStage = true
            // A CMD after the ENTRYPOINT sets again what the ENTRYPOINT emptied.
            clearedCmd = nil
            stageCmdLines.append(line)
        case "ENTRYPOINT":
            entrypoint = .known(line.words(shell: shell))
            entrypointLine = line
            stageEntrypointLines.append(line)
            if !cmdSetInStage {
                if let inherited = cmd.words, !inherited.isEmpty, cmdLine != nil { clearedCmd = inherited }
                cmd = .known([])
                cmdLine = nil
            }
        default:
            break
        }
    }

    /// Whether the `ENTRYPOINT` in effect is an exec-form wrapper that runs the command it is given: it ends in `--`,
    /// it is an init such as `tini` or `dumb-init`, or it is a lone script (`*.sh`, or named like an entrypoint).
    /// What such a wrapper finally runs is the program's business, so a claim naming the command it is handed holds.
    public var entrypointHandsOn: Bool {
        guard case let .exec(words)? = entrypointLine?.form, let first = words.first else { return false }
        let name = Launch.basename(first).lowercased()
        if words.last == "--" || Self.inits.contains(name) { return true }
        return words.count == 1 && (name.hasSuffix(".sh") || name.contains("entrypoint"))
    }

    static let inits: Set<String> = ["tini", "tini-static", "dumb-init", "catatonit"]

    /// Whether the `ENTRYPOINT` in effect is a shell-form line of this Dockerfile.
    public var entrypointIsShellForm: Bool {
        if case .shell = entrypointLine?.form { return true }
        return false
    }

    /// What the daemon executes for `run`, from this config and the run's `--entrypoint` and arguments: the
    /// `--entrypoint` value (one word, never split) replaces `Entrypoint` and drops `Cmd`; arguments after the image
    /// replace `Cmd`; whatever `Entrypoint` holds comes first.
    public func launch(_ run: DockerRun) -> Launch {
        if let override = run.entrypoint {
            return Launch(words: (override.isEmpty ? [] : [override]) + run.arguments, prefixFromBase: false)
        }
        let tail = run.arguments.isEmpty ? cmd.words : run.arguments
        switch (entrypoint, tail) {
        case let (.known(entry), tail?):
            return Launch(words: entry + tail, prefixFromBase: false)
        case let (.fromBase, tail?):
            return Launch(words: tail, prefixFromBase: true)
        default:
            return Launch(words: [], prefixFromBase: true, isKnown: false)
        }
    }
}
