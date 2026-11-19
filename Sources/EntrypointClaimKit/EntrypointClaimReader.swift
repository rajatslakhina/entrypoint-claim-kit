import DockerfileClaimKit

/// What the reader remembers from earlier turns of a conversation.
struct Earlier: Sendable, Hashable {
    var dockerfile: Dockerfile?
    var tags: Set<String> = []
}

/// Finds the claims an answer makes about what a container runs: runs it says execute some words, general
/// statements about `CMD`, `ENTRYPOINT` and `docker run`, and (with `checksLines`) the `CMD`/`ENTRYPOINT` lines of
/// the Dockerfile it shows.
public struct EntrypointClaimReader: Sendable {
    /// Also read the `CMD`/`ENTRYPOINT`/`SHELL` lines of the answer's Dockerfile as claims.
    public let checksLines: Bool

    public init(checksLines: Bool = true) {
        self.checksLines = checksLines
    }

    /// Whether a text is about what a container runs: it names `CMD` or `ENTRYPOINT`, shows a `docker run`, or shows
    /// a Dockerfile.
    public static func isAboutContainerCommands(_ text: String) -> Bool {
        let original = text.replacingOccurrences(of: "`", with: " ")
        if Words.containsAny(original, ["CMD", "ENTRYPOINT"]) || original.folded.contains("--entrypoint") {
            return true
        }
        if original.folded.contains("docker run") || original.folded.contains("docker container run") { return true }
        return AnswerBlocks.split(text).contains { block in
            if case .code = block.kind { return Dockerfile.looksLikeDockerfile(block.lines.joined(separator: "\n")) }
            return false
        }
    }

    public func claims(in text: String, context: String = "") -> [EntrypointClaim] {
        allClaims(in: text, context: context, earlier: Earlier())
    }

    func allClaims(in text: String, context: String, earlier: Earlier) -> [EntrypointClaim] {
        let blocks = AnswerBlocks.split(text)
        let shownAll = Self.dockerfiles(in: blocks)
        let shown = shownAll.last
        // Sentences are read against the Dockerfile shown most recently before them: one from the question or an
        // earlier turn, else the answer's first. Lines are read from the answer's last Dockerfile only, its final
        // version (an earlier one may be the broken "before").
        let before = Self.dockerfiles(in: AnswerBlocks.split(context)).last ?? earlier.dockerfile ?? shownAll.first
        let tags = earlier.tags.union(Tags.find(inText: text)).union(Tags.find(inText: context))
        var claims: [EntrypointClaim] = []
        if checksLines, let shown { claims += LineChecks.claims(ImageCommands(shown)) }
        var reading = RunClaimReader.Context(image: before.map(ImageCommands.init), tags: tags)
        for block in blocks {
            switch block.kind {
            case .code:
                reading.lastRun = block.lines.compactMap { DockerRun(Self.command($0)) }.last
                let text = block.lines.joined(separator: "\n")
                if Dockerfile.looksLikeDockerfile(text) { reading.image = ImageCommands(Dockerfile(text)) }
            case .prose:
                for sentence in Sentences.split(block.lines) {
                    claims += StatementReader.statements(in: sentence, image: reading.image).map {
                        EntrypointClaim(subject: .statement($0), sentence: sentence, image: reading.image)
                    }
                    claims += RunClaimReader.claims(in: sentence, context: &reading)
                }
            }
        }
        return claims
    }

    /// A shell line without its prompt (`$ `).
    static func command(_ line: String) -> String {
        let trimmed = line.trimmed
        return trimmed.hasPrefix("$ ") ? String(trimmed.dropFirst(2)) : trimmed
    }

    static func dockerfiles(in blocks: [AnswerBlock]) -> [Dockerfile] {
        blocks.compactMap { block in
            guard case .code = block.kind else { return nil }
            let text = block.lines.joined(separator: "\n")
            return Dockerfile.looksLikeDockerfile(text) ? Dockerfile(text) : nil
        }
    }

    /// What a review remembers for the next turn.
    static func remember(_ text: String, context: String, into earlier: inout Earlier) {
        if let shown = dockerfiles(in: AnswerBlocks.split(text)).last { earlier.dockerfile = shown }
        earlier.tags.formUnion(Tags.find(inText: text).union(Tags.find(inText: context)))
    }
}
