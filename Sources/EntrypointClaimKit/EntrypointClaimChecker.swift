/// Reads what an answer says about what a container runs and checks every claim with Docker's own rules: the one
/// call most callers need.
public struct EntrypointClaimChecker: Sendable {
    public let policy: EntrypointPolicy
    public let reader: EntrypointClaimReader

    public init(policy: EntrypointPolicy = .standard) {
        self.policy = policy
        reader = EntrypointClaimReader(checksLines: policy.checksLines)
    }

    public func claims(in text: String, context: String = "") -> [EntrypointClaim] {
        reader.claims(in: text, context: context)
    }

    public func judge(_ claim: EntrypointClaim) -> EntrypointFinding {
        EntrypointEvaluator(policy: policy).judge(claim)
    }

    /// Every claim's finding. A Dockerfile line that works as written makes no finding of its own.
    public func check(_ text: String, context: String = "") -> EntrypointReport {
        report(claims(in: text, context: context))
    }

    /// A line whose mistake a stated claim already shows (the same slip) is left out: one mistake, one finding.
    func report(_ claims: [EntrypointClaim]) -> EntrypointReport {
        let findings = claims.map(judge).filter { $0.claim.isExplicit || $0.severity != .holds }
        let stated = Set(findings.filter(\.claim.isExplicit).compactMap(\.slip))
        return EntrypointReport(findings: findings.filter { finding in
            guard case let .line(line, _) = finding.claim.subject, let slip = line.slip else { return true }
            return !stated.contains(slip)
        })
    }
}

/// Checks a conversation's answers one after another and remembers what it flagged, the last Dockerfile shown and
/// the image tags built, so a later answer is read against them and a wrong claim stated again after a correction
/// was asked for is marked as repeated rather than new.
public actor EntrypointLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: EntrypointClaimChecker
    public private(set) var statistics = Statistics()
    private var flaggedKeys: Set<String> = []
    private var earlier = Earlier()

    public init(checker: EntrypointClaimChecker = EntrypointClaimChecker()) {
        self.checker = checker
    }

    /// Checks one answer. `context` is the question it answers. A turn where neither talks about what a container
    /// runs makes no new claims; it keeps only those that repeat a claim flagged earlier in the conversation.
    public func review(_ text: String, context: String = "") -> EntrypointReport {
        let about = EntrypointClaimReader.isAboutContainerCommands(text)
            || EntrypointClaimReader.isAboutContainerCommands(context)
        let all = checker.reader.allClaims(in: text, context: context, earlier: earlier)
        EntrypointClaimReader.remember(text, context: context, into: &earlier)
        var findings = checker.report(about ? all : all.filter { flaggedKeys.contains($0.key) }).findings
        var keys: Set<String> = []
        for index in findings.indices where findings[index].severity >= .caution {
            findings[index].isRepeated = flaggedKeys.contains(findings[index].key)
            keys.insert(findings[index].key)
        }
        flaggedKeys.formUnion(keys)
        let report = EntrypointReport(findings: findings)
        statistics.reviews += 1
        statistics.claims += findings.count
        statistics.flagged += report.flagged.count
        statistics.repeated += report.repeatedCount
        return report
    }

    /// Starts a new conversation: nothing flagged so far counts as a repeat, and no Dockerfile is remembered.
    public func forget() {
        flaggedKeys.removeAll()
        earlier = Earlier()
    }
}
