/// Reads "`docker run app --debug` runs `python app.py --debug`" and "the container starts `node server.js`":
/// a run (inline, the last `docker run` shown just before, or starting the container with no arguments) and the
/// words the sentence says it executes, right after a verb such as "runs" or "executes".
enum RunClaimReader {
    static let verbs = ["runs", "will run", "executes", "will execute", "starts", "will start", "launches",
                        "becomes", "is executed as", "ends up running", "results in", "invokes", "runs as",
                        "is equivalent to", "is effectively", "executes as", "you get", "process is", "command is"]
    static let startPhrases = ["the container", "by default", "on startup", "at startup", "on start", "the image runs",
                               "the image starts", "container starts", "starting the container"]
    static let anaphora = ["this", "that", "it", "which", "here", "the command above", "this command", "that command"]
    static let blockers = Lexicon.blockers + ["during the build", "at build time", "while building", "build step",
                                              "when building", "in the build", "think", "expect"]

    struct Context {
        var image: ImageCommands?
        let tags: Set<String>
        /// The last `docker run` shown before this sentence (in a code block or an earlier sentence).
        var lastRun: DockerRun?
    }

    static func claims(in sentence: String, context: inout Context) -> [EntrypointClaim] {
        let pieces = Sentences.pieces(sentence)
        let inline = pieces.filter(\.isCode).compactMap { DockerRun($0.text) }
        defer { if let last = inline.last { context.lastRun = last } }
        let text = " " + sentence.replacingOccurrences(of: "`", with: "").folded + " "
        guard let image = context.image, !Words.containsAny(text, blockers), !text.contains("n't") else { return [] }
        var claims: [EntrypointClaim] = []
        var runBefore: DockerRun?
        for index in pieces.indices {
            let piece = pieces[index]
            if piece.isCode, let run = DockerRun(piece.text) { runBefore = run; continue }
            guard piece.isCode, index > 0, let claimed = ShellWords.split(piece.text), let first = claimed.first,
                  first.lowercased() != "docker", endsWithVerb(pieces[index - 1].text) else { continue }
            let prose = pieces[..<index].filter { !$0.isCode }.map(\.text).joined(separator: " ")
            guard let run = runBefore ?? implied(prose, context: context) else { continue }
            guard run.image.isEmpty || belongs(run.image, image: image, tags: context.tags) else { continue }
            claims.append(EntrypointClaim(subject: .runs(run, claimed: claimed), sentence: sentence, image: image))
        }
        return claims
    }

    static func endsWithVerb(_ prose: String) -> Bool {
        let tail = prose.folded.trimmed
        return verbs.contains { tail == $0 || tail.hasSuffix(" " + $0) }
    }

    /// The run a sentence without an inline `docker run` talks about: the one shown just before ("this runs ..."),
    /// or starting the container with no arguments ("by default the container runs ...").
    static func implied(_ prose: String, context: Context) -> DockerRun? {
        let text = " " + prose.folded + " "
        if let last = context.lastRun, Words.containsAny(text, anaphora) { return last }
        return Words.containsAny(text, startPhrases) ? DockerRun(image: "") : nil
    }

    /// Whether a run's image is the one the Dockerfile builds: a tag from a `docker build` in the conversation, and
    /// not an image the Dockerfile starts `FROM`.
    static func belongs(_ image: String, image config: ImageCommands, tags: Set<String>) -> Bool {
        let name = Tags.normalized(image)
        return tags.contains(name) && !config.baseImages.map(Tags.normalized).contains(name)
    }
}

/// Image names given to `docker build -t` (or `--tag`), normalised so `app` and `app:latest` are the same.
enum Tags {
    /// Tags from the code in a text: its code blocks' lines and its inline code spans (prose is never shell-split,
    /// so an apostrophe in a sentence cannot hide a tag).
    static func find(inText text: String) -> Set<String> {
        let code = AnswerBlocks.split(text).flatMap { block -> [String] in
            if case .code = block.kind { return block.lines }
            return block.lines.flatMap { Sentences.pieces($0).filter(\.isCode).map(\.text) }
        }
        return find(in: code)
    }

    static func find(in lines: [String]) -> Set<String> {
        var tags: Set<String> = []
        for line in lines {
            guard let words = ShellWords.split(line) else { continue }
            for start in words.indices where words[start] == "docker" {
                let rest = Array(words[(start + 1)...].prefix { !["&&", "||", ";", "|"].contains($0) })
                guard let build = rest.firstIndex(of: "build"), build <= 2 else { continue }
                tags.formUnion(tagValues(Array(rest[(build + 1)...])))
            }
        }
        return tags
    }

    static func tagValues(_ words: [String]) -> [String] {
        var tags: [String] = []
        for (index, word) in words.enumerated() {
            if word == "-t" || word == "--tag", index + 1 < words.count {
                tags.append(normalized(words[index + 1]))
            } else if word.hasPrefix("--tag=") {
                tags.append(normalized(String(word.dropFirst(6))))
            } else if word.hasPrefix("-t"), word.count > 2, !word.hasPrefix("--") {
                tags.append(normalized(String(word.dropFirst(2))))
            }
        }
        return tags
    }

    static func normalized(_ image: String) -> String {
        let lower = image.lowercased()
        return lower.hasSuffix(":latest") ? String(lower.dropLast(7)) : lower
    }
}
