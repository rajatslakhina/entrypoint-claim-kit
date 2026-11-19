/// A `docker run` (or `docker container run`) command line, read the way the Docker CLI reads it: options up to the
/// image, then the command and its arguments. Only options the CLI is known to take are accepted, so the image is
/// never mistaken for an option's value.
public struct DockerRun: Sendable, Hashable {
    public let image: String
    /// The words after the image: they replace the image's `CMD`.
    public let arguments: [String]
    /// The `--entrypoint` value, when the run gives one.
    public let entrypoint: String?

    public init(image: String, arguments: [String] = [], entrypoint: String? = nil) {
        self.image = image
        self.arguments = arguments
        self.entrypoint = entrypoint
    }

    /// Reads a command line; `nil` when it is not a `docker run` or uses an option this reader does not know.
    public init?(_ commandLine: String) {
        guard var words = ShellWords.split(commandLine) else { return nil }
        if words.first == "sudo" { words.removeFirst() }
        if let stop = words.firstIndex(where: { ["&&", "||", ";", "|", ">", ">>", "2>&1", "&"].contains($0) }) {
            words = Array(words[..<stop])
        }
        let prefix = words.prefix(3).map { $0.lowercased() }
        let skip = prefix.starts(with: ["docker", "run"]) ? 2
            : prefix.starts(with: ["docker", "container", "run"]) ? 3 : 0
        guard skip > 0, let parsed = Self.options(Array(words.dropFirst(skip))) else { return nil }
        self = parsed
    }

    static let valueOptions: Set<String> = [
        "add-host", "attach", "blkio-weight", "cap-add", "cap-drop", "cgroupns", "cidfile", "cpu-shares", "cpus",
        "cpuset-cpus", "device", "dns", "dns-search", "entrypoint", "env", "env-file", "expose", "gpus", "group-add",
        "health-cmd", "health-interval", "health-retries", "health-start-period", "health-timeout", "hostname", "ip",
        "ipc", "label", "label-file", "link", "log-driver", "log-opt", "memory", "memory-reservation", "memory-swap",
        "mount", "name", "network", "net", "network-alias", "pid", "platform", "publish", "pull", "restart", "runtime",
        "security-opt", "shm-size", "stop-signal", "stop-timeout", "storage-opt", "sysctl", "tmpfs", "ulimit", "user",
        "userns", "uts", "volume", "volumes-from", "workdir", "cpu-period", "cpu-quota", "detach-keys", "domainname",
        "mac-address", "oom-score-adj", "pids-limit"
    ]
    static let flagOptions: Set<String> = [
        "rm", "detach", "interactive", "tty", "init", "privileged", "publish-all", "read-only", "quiet",
        "no-healthcheck", "oom-kill-disable", "sig-proxy", "disable-content-trust"
    ]
    static let shortValues: [Character: String] = ["p": "publish", "e": "env", "v": "volume", "w": "workdir",
                                                   "u": "user", "h": "hostname", "l": "label", "m": "memory"]
    static let shortFlags: Set<Character> = ["d", "i", "t", "P", "q"]

    /// Walks the options; the first word that is not one is the image.
    static func options(_ words: [String]) -> DockerRun? {
        var entrypoint: String?
        var index = 0
        while index < words.count, words[index].hasPrefix("-"), words[index] != "-" {
            let word = words[index]
            index += 1
            if word == "--" { break }
            guard let (name, inline) = parse(word) else { return nil }
            guard let name else { continue }
            let value: String
            if let inline {
                value = inline
            } else {
                guard index < words.count else { return nil }
                value = words[index]
                index += 1
            }
            if name == "entrypoint" { entrypoint = value }
        }
        guard index < words.count else { return nil }
        return DockerRun(image: words[index], arguments: Array(words[(index + 1)...]), entrypoint: entrypoint)
    }

    /// One option word: `(nil, _)` for a flag that takes no value, `(name, value?)` for one that does (the value
    /// inline after `=` or in a short cluster, or `nil` when it is the next word), `nil` for an unknown option.
    static func parse(_ word: String) -> (String?, String?)? {
        if word.hasPrefix("--") {
            let body = word.dropFirst(2)
            let name = String(body.prefix { $0 != "=" })
            let inline = body.contains("=") ? String(body.drop { $0 != "=" }.dropFirst()) : nil
            if flagOptions.contains(name) { return (nil, nil) }
            return valueOptions.contains(name) ? (name, inline) : nil
        }
        var letters = Substring(word.dropFirst())
        while let letter = letters.first {
            letters = letters.dropFirst()
            if shortFlags.contains(letter) { continue }
            guard let name = shortValues[letter] else { return nil }
            return (name, letters.isEmpty ? nil : String(letters.drop { $0 == "=" }))
        }
        return (nil, nil)
    }
}
