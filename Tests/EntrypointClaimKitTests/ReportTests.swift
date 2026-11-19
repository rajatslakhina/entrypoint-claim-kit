import Testing
@testable import EntrypointClaimKit

@Suite("Reports and the ledger")
struct ReportTests {
    let wrong = pythonApp + built + "`docker run api --debug` runs `python app.py --port 80 --debug`."

    @Test("Verdicts, notes, feedback and summaries")
    func report() {
        let none = check("Nothing about containers here.")
        #expect(none.verdict == .noClaims && none.note == nil && none.feedback == nil)
        #expect(none.summary == "no claims about what a container runs")
        let report = check(wrong)
        #expect(report.verdict == .wrong)
        #expect(report.note?.hasPrefix("Container command check: ") == true)
        #expect(report.feedback?.contains("- `docker run api --debug` does not run") == true)
        #expect(report.summary == "1 claim checked, 0 hold, 1 wrong")
        let mixed = check(dockerfile("FROM a", "CMD [\"x\"]", "CMD [\"y\"]") + "Only the last CMD takes effect. "
            + "Build with `docker build -t app .`; `docker run app` runs `z`.")
        #expect(mixed.verdict == .caution)
        #expect(mixed.summary == "3 claims checked, 1 hold, 1 unchecked, 1 to check")
        #expect(check("Only the last CMD takes effect.").verdict == .verified)
        #expect(check(pythonApp + built + "`docker run api` runs `node x.js`.").verdict == .unchecked)
    }

    @Test("The ledger marks a repeat, keeps the Dockerfile and tags, and forgets on request")
    func ledger() async {
        let ledger = EntrypointLedger()
        let first = await ledger.review(wrong, context: "How do I pass --debug?")
        #expect(first.repeatedCount == 0)
        let second = await ledger.review("Sorry: `docker run api --debug` runs `python app.py --port 80 --debug`.")
        #expect(second.repeatedCount == 1)
        #expect(second.note?.contains("stated again") == true)
        #expect(second.summary.hasSuffix("1 repeated"))
        let later = await ledger.review("A regex `a+` matches `aaa`.")
        #expect(later.findings.isEmpty)
        let unrelated = await ledger.review("By default the container runs `python app.py --port 80 --x`.")
        #expect(unrelated.findings.isEmpty)
        let fixed = await ledger.review("`docker run api --debug` runs `python app.py --debug`.")
        #expect(fixed.verdict == .verified)
        let stats = await ledger.statistics
        #expect(stats == EntrypointLedger.Statistics(reviews: 5, claims: 3, flagged: 2, repeated: 1))
        await ledger.forget()
        let again = await ledger.review("`docker run api --debug` runs `python app.py --port 80 --debug`.")
        #expect(again.findings.isEmpty)
    }

    @Test("Explanations of runs")
    func explanations() {
        let holds = check(pythonApp + built + "`docker run --entrypoint sh api -c ls` runs `sh -c ls`.")
        #expect(holds.findings.first?.explanation == "`docker run --entrypoint sh api -c ls` runs `sh -c ls`, as the answer says.")
        let base = check(dockerfile("FROM node", "CMD [\"node\"]") + "By default the container runs `node`.")
        #expect(base.findings.first?.explanation
            == "Starting the container runs `node` after the base image's ENTRYPOINT, if any, as the answer says.")
        let unchecked = check(pythonApp + built + "`docker run api` runs `node x.js`.")
        #expect(unchecked.findings.first?.explanation.contains("was not checked against `node x.js`") == true)
        #expect(EntrypointFinding.display(DockerRun(image: "", arguments: ["x"])) == "That run")
    }
}
