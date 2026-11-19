import DockerfileClaimKit
import Testing
@testable import EntrypointClaimKit

/// The README's examples, run as written.
@Suite("README")
struct ReadmeTests {
    @Test("The usage example reports what the README says")
    func usage() throws {
        let answer = """
        ```dockerfile
        FROM python:3.12-slim
        ENTRYPOINT ["python", "app.py"]
        CMD ["--port", "80"]
        ```
        Build it with `docker build -t api .`. Then `docker run api --debug` runs `python app.py --port 80 --debug`.
        """
        let report = EntrypointClaimChecker().check(answer, context: "How do I turn on --debug?")
        #expect(report.verdict == .wrong)
        #expect(report.note == "Container command check: `docker run api --debug` does not run "
            + "`python app.py --port 80 --debug`: it runs `python app.py --debug` (arguments after the image replace "
            + "CMD; they are not added to it).")
        #expect(report.feedback?.hasPrefix("Some of what your answer says about what the container runs") == true)
    }

    @Test("The model on its own")
    func model() throws {
        let image = ImageCommands(Dockerfile("FROM python:3.12-slim\nENTRYPOINT [\"python\", \"app.py\"]"))
        #expect(image.entrypoint == .known(["python", "app.py"]))
        let launch = image.launch(try #require(DockerRun("docker run --entrypoint sh api -c 'ls /app'")))
        #expect(launch.words == ["sh", "-c", "ls /app"])
        #expect(!launch.refused)
    }
}
