import EntrypointClaimKit

let fence = "```"

func dockerfile(_ lines: String...) -> String {
    "\(fence)dockerfile\n" + lines.joined(separator: "\n") + "\n\(fence)\n"
}

func heading(_ number: Int, _ title: String) {
    print("")
    print("[\(number)] \(title)")
}

func show(_ report: EntrypointReport, label: String = "answer") {
    print("    \(label): \(report.verdict.rawValue) (\(report.summary))")
    for finding in report.findings {
        let mark = switch finding.severity {
        case .holds: "ok"
        case .unchecked: "??"
        case .caution: "!!"
        case .wrong: "XX"
        }
        let repeated = finding.isRepeated ? " [repeated]" : ""
        print("      \(mark) \(finding.explanation)\(repeated)")
    }
}
