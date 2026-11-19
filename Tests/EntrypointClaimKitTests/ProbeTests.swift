import Testing
@testable import EntrypointClaimKit

let correctProbes: [String] = [
        pythonApp + built + "Then `docker run api` runs `python app.py --port 80`, and `docker run api --port 8080` runs "
            + "`python app.py --port 8080`.",
        dockerfile("FROM node:20-alpine", "CMD [\"node\", \"server.js\"]") + "By default the container runs `node server.js`.",
        dockerfile("FROM node:20", "RUN apt-get install -y tini", "ENTRYPOINT [\"tini\", \"--\"]", "CMD [\"node\", \"server.js\"]")
            + "Build it as `docker build -t app .`; `docker run app` runs `tini -- node server.js`.",
        dockerfile("FROM node:20", "CMD [\"node\", \"server.js\"]") + "Build with `docker build -t app .`, then `docker run app` "
            + "runs `node server.js`.",
        dockerfile("FROM node:20 AS build", "RUN npm ci", "CMD [\"npm\", \"test\"]", "", "FROM nginx:1.27-alpine",
                   "COPY --from=build /src/dist /usr/share/nginx/html", "CMD [\"nginx\", \"-g\", \"daemon off;\"]")
            + "Build with `docker build -t site .`; `docker run -p 8080:80 site` runs `nginx -g \"daemon off;\"`.",
        dockerfile("FROM node:20", "CMD npm run migrate && npm start") + "Build with `docker build -t web .`. On startup "
            + "the container runs `npm run migrate && npm start` through `/bin/sh -c`.",
        dockerfile("FROM postgres:16", "ENTRYPOINT [\"/entrypoint.sh\"]", "CMD [\"postgres\"]") + "Build with "
            + "`docker build -t db .`; `docker run db` runs `/entrypoint.sh postgres`, and `docker run db bash` runs "
            + "`/entrypoint.sh bash`.",
        pythonApp + "After `docker build -t api .`, `docker run --entrypoint python api -m pytest` runs `python -m pytest`.",
        "Arguments passed to `docker run` after the image name replace CMD. With `--entrypoint`, Docker also clears CMD. "
            + "A shell form ENTRYPOINT ignores CMD and any arguments.",
        dockerfile("FROM nginx:1.27", "HEALTHCHECK CMD [\"curl\", \"-f\", \"http://localhost\"]", "ONBUILD CMD [\"x\"]",
                   "CMD [\"nginx\", \"-g\", \"daemon off;\"]") + "The HEALTHCHECK runs `curl -f http://localhost` every 30 "
            + "seconds. When the container starts it runs `nginx -g \"daemon off;\"`."
    ]

let wrapperProbes: [String] = [
    dockerfile("FROM postgres:16", "ENTRYPOINT [\"/entrypoint.sh\"]", "CMD [\"postgres\"]") + "Build with "
        + "`docker build -t db .`. `docker run -it db bash` starts `bash`.",
    dockerfile("FROM node:20", "ENTRYPOINT [\"tini\", \"--\"]", "CMD npm start") + "Build with `docker build -t web .`. "
        + "`docker run web` runs `npm start` under tini.",
    dockerfile("FROM node:20", "ENTRYPOINT [\"dumb-init\"]", "CMD [\"node\", \"server.js\"]") + "Build with "
        + "`docker build -t web .`. `docker run web node -v` runs `node -v`.",
    dockerfile("FROM node:20", "ENTRYPOINT [\"docker-entrypoint\"]", "CMD [\"node\"]") + "Build with "
        + "`docker build -t web .`. `docker run web` runs `node`."
]

let wrongProbes: [(String, EntrypointFinding.Slip)] = [
        (pythonApp + built + "`docker run api --debug` runs `python app.py --port 80 --debug`.",
         EntrypointFinding.Slip.argumentsAppendToCmd),
        (dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]") + built + "To get a shell, "
            + "`docker run -it api bash` starts `bash`.", .argumentsReplaceEntrypoint),
        (dockerfile("FROM node:20", "ENTRYPOINT node server.js", "CMD [\"--port\", \"3000\"]") + "After "
            + "`docker build -t web .`, `docker run web` runs `node server.js --port 3000`.", .shellFormTakesArguments),
        (pythonApp + built + "`docker run --entrypoint sh api` runs `sh --port 80`.", .overrideKeepsCmd),
        (dockerfile("FROM node:20", "CMD ['node', 'server.js']") + "When the container starts it runs `node server.js`.",
         .brokenExecForm),
        (pythonApp + "\(fence)bash\ndocker build -t api .\ndocker run --rm api --verbose\n\(fence)\nThis runs "
            + "`python app.py --port 80 --verbose`.", .argumentsAppendToCmd),
        (dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]") + "After `docker build -t api .`, "
            + "`docker run --entrypoint \"sh -c\" api ls` runs `sh -c ls`.", .overrideIsSplit),
        (dockerfile("FROM node:20", "CMD [\"node\", \"migrate.js\"]", "CMD [\"node\", \"server.js\"]") + "Build with "
            + "`docker build -t app .`. `docker run app` runs `node migrate.js`, then the second CMD runs the server.",
         .earlierCmdCounts),
        (dockerfile("FROM node:20", "CMD [\"node\", \"server.js\"]") + "Build with `docker build -t app .`, then "
            + "`docker run app --inspect` runs `node server.js --inspect`.", .argumentsAppendToCmd)
    ]

let lineProbes: [(String, [EntrypointClaim.Line])] = [
        (dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]", "CMD python app.py --port 80"),
         [EntrypointClaim.Line.shellCmdUnderExecEntrypoint]),
        (dockerfile("FROM a", "ENTRYPOINT p", "CMD [\"c\"]"), [.shellEntrypointDropsCmd]),
        (dockerfile("FROM a", "ENTRYPOINT ['python', 'app.py']", "CMD [\"--x\"]"), [.brokenExecForm]),
        (dockerfile("FROM node:20", "ENTRYPOINT [\"tini\", \"--\"]", "CMD npm start"), []),
        (dockerfile("FROM a", "CMD [\"a\", 1]", "CMD ['b']"), [.notStringArray]),
        (dockerfile("FROM a", "ENTRYPOINT [\"p\"]", "CMD --port 80"), [.leadingFlag]),
        (dockerfile("FROM a", "CMD [\"a\"]", "CMD [\"b\"]"), [.severalCmd]),
        (dockerfile("FROM a", "ENTRYPOINT [\"a\"]", "ENTRYPOINT [\"b\"]"), [.severalEntrypoint]),
        (dockerfile("FROM a AS b", "CMD [\"c\"]", "FROM b", "ENTRYPOINT [\"p\"]"), [.inheritedCmdCleared]),
        (dockerfile("FROM node:20", "RUN [\"npm\", \"ci\"]", "CMD [\"node\", \"server.js\"]"), [])
    ]

let quietProbes: [String] = [
        "In docker compose, `command:` replaces CMD and `entrypoint:` replaces ENTRYPOINT.",
        "In Kubernetes, `args` overrides CMD and `command` overrides the ENTRYPOINT.",
        dockerfile("FROM nginx:1.27", "COPY site /usr/share/nginx/html") + "You can check the base with "
            + "`docker run nginx:1.27 nginx -v`, which runs `nginx -v`.",
        dockerfile("FROM node:20", "RUN npm ci", "CMD [\"node\", \"server.js\"]") + "The `RUN` step executes `npm ci` "
            + "during the build.",
        "The `cron` job runs `backup.sh` every night, and `make test` runs `pytest -q`.",
        dockerfile("FROM ubuntu:24.04", "CMD [\"bash\"]") + "Try `docker run -it ubuntu bash`, which starts `bash`.",
        dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]") + built + "Then `docker exec -it api-1 sh` "
            + "runs `sh` inside the running container. `docker compose run api --debug` runs `python app.py --debug`.",
        dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]") + built + "`docker run --frobnicate api --x` "
            + "runs `python app.py`.",
        dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]") + "The test suite runs `pytest -q`, and the "
            + "Makefile target `lint` runs `ruff check .`. In CI, the workflow executes `make test`.",
        dockerfile("FROM python:3.12", "ENTRYPOINT [\"python\", \"app.py\"]") + "Arguments to `docker run` do not replace "
            + "the ENTRYPOINT. `docker build -t api .` then `docker run api bash` does not start `bash`.",
        "On Windows, cmd runs `dir` and PowerShell runs `Get-ChildItem`.",
        pythonApp + "If you used shell form instead, `docker run api` would run `python app.py` alone."
    ]

/// Answers an assistant might give, right and wrong, and sentences from other domains beside a Dockerfile. Kept from
/// the probing done before tagging 1.0.0.
@Suite("Probes")
struct ProbeTests {
    @Test("Correct answers stay unflagged", arguments: correctProbes)
    func correct(_ answer: String) {
        #expect(check(answer).flagged.isEmpty, "\(answer)")
    }

    @Test("A wrapper ENTRYPOINT hands the command on: claims about that command hold", arguments: wrapperProbes)
    func wrappers(_ answer: String) {
        let report = check(answer)
        #expect(report.flagged.isEmpty, "\(answer)")
        #expect(report.verdict == .verified, "\(answer)")
    }

    @Test("An apostrophe in the sentence does not hide the build tag")
    func apostrophe() {
        let report = check(pythonApp + "Here's the build: `docker build -t api .`. Then `docker run api --debug` runs "
            + "`python app.py --port 80 --debug`.")
        #expect(report.slips == [.argumentsAppendToCmd])
    }

    @Test("A before-and-after answer: each sentence is read against the Dockerfile just above it")
    func beforeAndAfter() {
        let before = dockerfile("FROM node:20", "ENTRYPOINT node server.js", "CMD [\"--port\", \"3000\"]")
        let after = dockerfile("FROM node:20", "ENTRYPOINT [\"node\", \"server.js\"]", "CMD [\"--port\", \"3000\"]")
        let answer = "Build with `docker build -t web .`.\n" + before + "Here `docker run web` runs `/bin/sh -c \"node server.js\"`. "
            + "Use the exec form:\n" + after + "Now `docker run web` runs `node server.js --port 3000`."
        let report = check(answer)
        #expect(report.verdict == .verified)
        #expect(report.findings.count == 2)
    }

    @Test("Wrong answers are caught with the right mistake", arguments: wrongProbes)
    func wrong(_ answer: String, _ slip: EntrypointFinding.Slip) {
        let report = check(answer)
        #expect(report.slips == [slip], "\(answer)")
        #expect(report.findings.count == 1, "one mistake, one finding")
    }

    @Test("Lines alone", arguments: lineProbes)
    func lines(_ answer: String, _ expected: [EntrypointClaim.Line]) {
        #expect(check(answer).lines == expected)
    }

    @Test("Other tools and other domains make no claim", arguments: quietProbes)
    func quiet(_ answer: String) {
        #expect(check(answer).findings.isEmpty, "\(answer)")
    }

    @Test("A claimed command none of the known mistakes explains is left unchecked")
    func unexplained() {
        let report = check(dockerfile("FROM node:20", "CMD npm start") + "Build with `docker build -t web .`. "
            + "`docker run web` runs `node server.js`.")
        #expect(report.verdict == .unchecked)
    }
}
