/// General statements about how `CMD`, `ENTRYPOINT` and `docker run` combine. A sentence is read only when it names
/// `CMD` or `ENTRYPOINT`, says nothing negated or conditional, and is not about another tool (compose, Kubernetes,
/// `docker exec`, `HEALTHCHECK`), whose rules differ.
enum StatementReader {
    typealias Statement = EntrypointClaim.Statement

    static func statements(in sentence: String, image: ImageCommands?) -> [Statement] {
        let original = sentence.replacingOccurrences(of: "`", with: "")
        // Punctuation becomes space so a verb at the end of a clause ("CMD is gone.") is still a whole word.
        let spaced = String(original.folded.map { ".,;:!?()\"".contains($0) ? " " : $0 })
        let text = " " + spaced.replacingOccurrences(of: "shell-form", with: "shell form")
            .replacingOccurrences(of: "exec-form", with: "exec form") + " "
        let hasCmd = Words.contains(original, "CMD")
        let hasEntrypoint = Words.contains(text, "entrypoint") || text.contains("--entrypoint")
        guard hasCmd || hasEntrypoint, !Words.containsAny(text, Lexicon.blockers),
              !text.contains("n't") else { return [] }
        var found: [Statement] = []
        if Words.containsAny(text, Lexicon.argumentWords), Words.containsAny(text, Lexicon.runContext),
           !text.contains("shell form"), !text.contains("--entrypoint") {
            found += arguments(text, hasCmd: hasCmd, image: image)
        }
        if text.contains("--entrypoint"), hasCmd {
            found += override(text)
        }
        if text.contains("shell form"), hasEntrypoint, hasCmd || Words.containsAny(text, Lexicon.argumentWords) {
            found += pick(text, Lexicon.ignoreVerbs, .shellEntrypointIgnoresArguments, Lexicon.receiveVerbs,
                          .shellEntrypointTakesArguments)
        }
        found += cmdLines(text, hasCmd: hasCmd)
        if hasCmd, hasEntrypoint, Words.containsAny(text, Lexicon.baseWords), !text.contains("--entrypoint") {
            // "ENTRYPOINT ... resets ... CMD": the ENTRYPOINT acts, the CMD is acted on.
            let resets = ordered(text, "entrypoint", Lexicon.resetVerbs, "cmd")
            let keeps = ordered(text, "entrypoint", Lexicon.inheritVerbs, "cmd")
            found += resets == keeps ? [] : resets ? [.entrypointResetsBaseCmd] : [.entrypointKeepsBaseCmd]
        }
        found += quotes(text)
        return found
    }

    /// "Only the last CMD takes effect" and "each CMD runs": the second only when nothing in the sentence says the
    /// last one wins.
    static func cmdLines(_ text: String, hasCmd: Bool) -> [Statement] {
        guard hasCmd else { return [] }
        let last = Words.containsAny(text, ["last", "final", "only"])
        if Words.containsAny(text, Lexicon.lastCmd), Words.containsAny(text, Lexicon.effectWords) {
            return [.lastCmdCounts]
        }
        if !last, Words.containsAny(text, Lexicon.everyCmd), Words.containsAny(text, Lexicon.runVerbs) {
            return [.everyCmdRuns]
        }
        return []
    }

    /// "Single quotes work in the exec form" (about the exec form only, with nothing in the sentence saying they
    /// fail) and "the exec form needs double quotes".
    static func quotes(_ text: String) -> [Statement] {
        var found: [Statement] = []
        if let quote = text.range(of: "single quote"), Words.containsAny(text, ["exec form", "json", "array"]),
           !text.contains("shell form"), !Words.containsAny(text, Lexicon.failWords),
           Words.containsAny(String(text[quote.upperBound...].prefix(24)), Lexicon.okWords) {
            found.append(.singleQuotesWork)
        }
        if text.contains("double quote"), Words.containsAny(text, Lexicon.mustWords) {
            found.append(.execFormNeedsDoubleQuotes)
        }
        return found
    }

    /// `--entrypoint` and `CMD`: "clears CMD" / "CMD is gone" against "keeps the CMD" / "CMD is passed to it". An
    /// active verb takes the CMD right after it; a passive one, the CMD right before it.
    static func override(_ text: String) -> [Statement] {
        let clears = near(text, Lexicon.clearVerbs, after: true) || near(text, Lexicon.clearPassive, after: false)
        let keeps = near(text, Lexicon.keepVerbs, after: true) || near(text, Lexicon.keepPassive, after: false)
        return clears == keeps ? [] : clears ? [.overrideClearsCmd] : [.overrideKeepsCmd]
    }

    /// Whether one of the verbs has "cmd" within a few words after it (or before it).
    static func near(_ text: String, _ verbs: [String], after: Bool) -> Bool {
        verbs.contains { verb in
            guard let range = text.range(of: " " + verb + " ") else { return false }
            let window = after ? String(text[range.upperBound...].prefix(16))
                : String(text[..<range.lowerBound].suffix(30))
            return window.contains("cmd")
        }
    }

    /// Whether `first` comes before one of the verbs, and `then` after it.
    static func ordered(_ text: String, _ first: String, _ verbs: [String], _ then: String) -> Bool {
        guard let subject = text.range(of: first) else { return false }
        return verbs.contains { verb in
            guard let range = text.range(of: " " + verb + " ", range: subject.upperBound..<text.endIndex) else {
                return false
            }
            return text[range.upperBound...].contains(then)
        }
    }

    /// One statement when only one side's verbs occur; none when both do.
    static func pick(_ text: String, _ yes: [String], _ yesStatement: Statement, _ no: [String],
                     _ noStatement: Statement) -> [Statement] {
        switch (Words.containsAny(text, yes), Words.containsAny(text, no)) {
        case (true, false): [yesStatement]
        case (false, true): [noStatement]
        default: []
        }
    }

    /// "Arguments after the image replace CMD / are appended to the ENTRYPOINT": each verb takes the keyword that
    /// follows it, or the one before it in a passive sentence ("CMD is overridden by ...").
    static func arguments(_ text: String, hasCmd: Bool, image: ImageCommands?) -> [Statement] {
        var found: [Statement] = []
        for (verbs, onCmd, onEntrypoint) in [(Lexicon.replaceVerbs, Statement.argumentsReplaceCmd,
                                              Statement.argumentsReplaceEntrypoint),
                                             (Lexicon.appendVerbs, .argumentsAppendToCmd,
                                              .argumentsAppendToEntrypoint)] {
            let ranges = verbs.compactMap { text.range(of: " " + $0 + " ") }
            guard let verb = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else { continue }
            // The object follows the verb closely ("appended to the CMD"); a passive replace verb may follow it
            // ("CMD is overridden by ...").
            let after = String(text[verb.upperBound...].prefix(24))
            let before = String(text[..<verb.lowerBound].suffix(24))
            let cmdAfter = after.range(of: "cmd")?.lowerBound
            let keyword: String? = switch (cmdAfter, after.range(of: "entrypoint")?.lowerBound) {
            case let (cmd?, entry?): cmd < entry ? "cmd" : "entrypoint"
            case (_?, nil): "cmd"
            case (nil, _?): "entrypoint"
            case (nil, nil) where verbs == Lexicon.replaceVerbs:
                before.contains("cmd") ? "cmd" : before.contains("entrypoint") ? "entrypoint" : nil
            case (nil, nil): nil
            }
            // "the ENTRYPOINT's default arguments" is CMD, not the ENTRYPOINT.
            guard !after.hasPrefix(" the \(keyword ?? "")'s"), !after.contains("\(keyword ?? "")'s") else { continue }
            if keyword == "cmd", hasCmd { found.append(onCmd) }
            if keyword == "entrypoint", onEntrypoint != .argumentsAppendToEntrypoint || image?.entrypointLine != nil {
                found.append(onEntrypoint)
            }
        }
        return found
    }
}

enum Lexicon {
    /// Words that make a sentence negated, conditional, hypothetical, about a misconception, or about another tool.
    static let blockers = ["not", "never", "no longer", "cannot", "without", "unless", "would", "could", "might",
                           "instead of", "rather than", "mistake", "misconception", "wrongly", "incorrectly", "myth",
                           "compose", "docker-compose", "kubernetes", "k8s", "pod", "docker exec", "healthcheck",
                           "onbuild", "command:", "args:", "podman", "helm"]
    static let argumentWords = ["argument", "arguments", "args", "anything after the image", "parameters",
                                "whatever you pass", "what you pass", "words after the image"]
    static let runContext = ["docker run", "at runtime", "at run time", "command line", "when you run",
                             "when running", "after the image name", "after the image"]
    static let replaceVerbs = ["replace", "replaces", "replaced", "override", "overrides", "overridden", "supersede",
                               "supersedes"]
    static let appendVerbs = ["appended to", "append to", "appends to", "added to", "added after", "passed to",
                              "tacked onto", "tacked on to", "become arguments to", "become arguments of"]
    static let clearVerbs = ["clears", "clear", "drops", "drop", "discards", "ignores", "resets", "removes", "wipes",
                             "replaces both", "overrides both", "empties"]
    static let clearPassive = ["is gone", "is ignored", "is dropped", "is discarded", "is cleared", "is removed",
                               "is reset", "is emptied", "goes away"]
    static let keepVerbs = ["keeps", "keep", "preserves", "still uses", "reuses"]
    static let keepPassive = ["is still passed", "still passed", "is still used", "still used", "still applies",
                              "is still appended", "still appended", "is passed to", "are passed to",
                              "becomes arguments", "become arguments", "is appended to", "are appended to",
                              "is kept", "is preserved", "survives"]
    static let failWords = ["fail", "fails", "break", "breaks", "error", "errors", "invalid", "wrong", "broken"]
    static let ignoreVerbs = ["ignores", "ignored", "discards", "discarded", "drops", "dropped"]
    static let receiveVerbs = ["receives", "receive", "gets", "appended", "passed to", "passes", "forwards",
                               "forwarded", "still works"]
    static let effectWords = ["takes effect", "wins", "is used", "counts", "applies", "is the one", "overrides",
                              "is honoured", "is honored", "is applied", "is executed", "runs", "is run"]
    static let lastCmd = ["last cmd", "final cmd", "last one", "only the last", "last instruction",
                          "last such instruction"]
    static let everyCmd = ["each cmd", "every cmd", "all cmd", "all the cmd", "multiple cmd", "several cmd",
                           "both cmd"]
    static let runVerbs = ["run", "runs", "execute", "executes", "executed", "in order", "in sequence",
                           "one after another", "are run"]
    static let baseWords = ["base image", "parent image", "base stage", "inherited", "from the base"]
    static let resetVerbs = ["resets", "reset", "clears", "cleared", "drops", "dropped", "discards", "discarded",
                             "empties", "emptied", "wipes"]
    static let inheritVerbs = ["keeps", "is kept", "preserves", "is preserved", "still uses", "still runs",
                               "still applies", "remains", "carries over", "carried over"]
    static let okWords = ["work", "works", "fine", "okay", "ok", "allowed", "valid", "acceptable", "can use",
                          "are equivalent", "either"]
    static let mustWords = ["must", "need", "needs", "require", "requires", "has to", "have to", "only"]
}
