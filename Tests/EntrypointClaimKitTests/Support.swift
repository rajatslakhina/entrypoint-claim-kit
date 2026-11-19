import DockerfileClaimKit
@testable import EntrypointClaimKit

let fence = "```"

/// A fenced Dockerfile block.
func dockerfile(_ lines: String...) -> String {
    "\(fence)dockerfile\n" + lines.joined(separator: "\n") + "\n\(fence)\n"
}

func image(_ lines: String...) -> ImageCommands {
    ImageCommands(Dockerfile(lines.joined(separator: "\n")))
}

func check(_ text: String, context: String = "", policy: EntrypointPolicy = .standard) -> EntrypointReport {
    EntrypointClaimChecker(policy: policy).check(text, context: context)
}

let pythonApp = dockerfile("FROM python:3.12-slim", "WORKDIR /app", "COPY . .",
                           "ENTRYPOINT [\"python\", \"app.py\"]", "CMD [\"--port\", \"80\"]")
let built = "Build it with `docker build -t api .`. "

extension EntrypointReport {
    var slips: [EntrypointFinding.Slip?] {
        findings.compactMap { finding in
            if case let .wrong(slip) = finding.outcome { return slip }
            return nil
        }
    }

    var statements: [EntrypointClaim.Statement] {
        findings.compactMap { finding in
            if case let .statement(statement) = finding.claim.subject { return statement }
            return nil
        }
    }

    var lines: [EntrypointClaim.Line] {
        findings.compactMap { finding in
            if case let .line(line, _) = finding.claim.subject { return line }
            return nil
        }
    }
}
