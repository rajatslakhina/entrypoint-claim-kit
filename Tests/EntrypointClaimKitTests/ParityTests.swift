import DockerfileClaimKit
import Testing
@testable import EntrypointClaimKit

/// Cases that build, and every run of them, checked against what the classic builder stored and what the daemon
/// composed (`Scripts/parity.py`).
let builtCases = parityCases.filter { !$0.buildStops }
let stoppedCases = parityCases.filter(\.buildStops)

@Suite("Parity with docker build and docker create")
struct ParityTests {
    @Test("The fixture covers the cases the script lists")
    func fixtureSize() {
        #expect(parityCases.count == 39)
        #expect(stoppedCases.count == 2)
        #expect(builtCases.flatMap(\.runs).count == 56)
    }

    @Test("Entrypoint and Cmd match docker inspect", arguments: builtCases)
    func config(_ parity: ParityCase) {
        let image = ImageCommands(Dockerfile(parity.dockerfile))
        #expect(image.stoppingLines.isEmpty)
        if let words = image.entrypoint.words { #expect(words == (parity.entrypoint ?? []), "\(parity.name)") }
        if let words = image.cmd.words { #expect(words == (parity.cmd ?? []), "\(parity.name)") }
    }

    @Test("Each run executes what docker create composed", arguments: builtCases)
    func runs(_ parity: ParityCase) throws {
        let image = ImageCommands(Dockerfile(parity.dockerfile))
        for run in parity.runs {
            let line = (["docker", "run"] + run.flags + ["app"] + run.arguments).map(Launch.quoted).joined(separator: " ")
            let parsed = try #require(DockerRun(line), "\(line)")
            let launch = image.launch(parsed)
            if let argv = run.argv {
                // The base (swift:6.0) has no ENTRYPOINT, so a launch whose prefix comes from it is exact here.
                if launch.isKnown { #expect(launch.words == argv, "\(parity.name): \(line)") }
                #expect(!launch.refused)
            } else {
                // An empty CMD on a base whose ENTRYPOINT is not shown: swift:6.0 has none, so Docker refuses.
                #expect(launch.refused || (launch.prefixFromBase && launch.words.isEmpty), "\(parity.name): \(line)")
            }
        }
    }

    @Test("Builds that stop are recognised", arguments: stoppedCases)
    func stops(_ parity: ParityCase) {
        #expect(!ImageCommands(Dockerfile(parity.dockerfile)).stoppingLines.isEmpty)
    }

    @Test("Only the base-image case is left to the base")
    func unknownConfigs() {
        let unknown = builtCases.filter { !ImageCommands(Dockerfile($0.dockerfile)).launch(DockerRun(image: "a")).isKnown }
        #expect(unknown.map(\.name) == ["unrelated stage", "base config"])
    }
}
