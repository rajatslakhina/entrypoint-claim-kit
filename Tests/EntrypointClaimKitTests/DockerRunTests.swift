import Testing
@testable import EntrypointClaimKit

@Suite("docker run command lines")
struct DockerRunTests {
    @Test("Options are skipped up to the image", arguments: [
        ("docker run app", "app", [String](), String?.none),
        ("docker run --rm -it app bash", "app", ["bash"], nil),
        ("docker run -p 8080:80 -e A=1 -v $(pwd):/src --name web app --port 80", "app", ["--port", "80"], nil),
        ("docker run -p8080:80 -dit app", "app", [], nil),
        ("docker run -dp 80:80 app", "app", [], nil),
        ("docker run --publish=80:80 --env-file .env --network=host app", "app", [], nil),
        ("docker run --entrypoint sh app -c ls", "app", ["-c", "ls"], "sh"),
        ("docker run --entrypoint=\"\" app", "app", [], ""),
        ("docker container run --init app x", "app", ["x"], nil),
        ("sudo docker run app", "app", [], nil),
        ("docker run app --debug && echo done", "app", ["--debug"], nil),
        ("docker run -- app x", "app", ["x"], nil),
        ("docker run -e=A=1 app", "app", [], nil),
        ("docker run - x", "-", ["x"], nil)
    ])
    func parses(_ line: String, _ image: String, _ arguments: [String], _ entrypoint: String?) throws {
        let run = try #require(DockerRun(line))
        #expect(run == DockerRun(image: image, arguments: arguments, entrypoint: entrypoint))
    }

    @Test("Not a docker run, or an option this reader does not know", arguments: [
        "docker build -t app .", "docker exec -it app sh", "docker compose run app", "podman run app", "docker run",
        "docker run --rm", "docker run --name", "docker run --frobnicate app", "docker run -Z app", "docker run 'app",
        "run app"
    ])
    func refuses(_ line: String) {
        #expect(DockerRun(line) == nil)
    }
}
