import DockerfileClaimKit
import EntrypointClaimKit

let checker = EntrypointClaimChecker()
let api = dockerfile("FROM python:3.12-slim", "WORKDIR /app", "COPY . .", "ENTRYPOINT [\"python\", \"app.py\"]",
                     "CMD [\"--port\", \"80\"]")
let build = "Build it with `docker build -t api .`. "

print("EntrypointClaimKit demo: what an answer says a container runs, checked with Docker's own rules")

heading(1, "A correct answer about ENTRYPOINT and CMD")
show(checker.check(api + build + "`docker run api` runs `python app.py --port 80`, and `docker run api --port 8080` "
    + "runs `python app.py --port 8080`. Arguments passed to `docker run` after the image name replace CMD."))

heading(2, "Passing a flag: arguments replace CMD, they are not added to it")
let question = "How do I turn on --debug when I run my API container?"
show(checker.check(api + build + "`docker run api --debug` runs `python app.py --port 80 --debug`.", context: question))
let rewrite = "`docker run api --port 80 --debug` runs `python app.py --port 80 --debug`."
show(checker.check(api + build + rewrite, context: question), label: "rewrite")

heading(3, "Getting a shell: the ENTRYPOINT stays unless --entrypoint replaces it")
show(checker.check(api + build + "To look around, `docker run -it api bash` starts `bash`."))
show(checker.check(api + build + "To look around, `docker run -it --entrypoint bash api` starts `bash`. "
    + "With `--entrypoint`, Docker also clears CMD."), label: "rewrite")

heading(4, "A shell-form ENTRYPOINT never sees CMD (one mistake, one finding)")
let shellForm = dockerfile("FROM node:20-slim", "WORKDIR /srv", "COPY . .", "ENTRYPOINT node server.js",
                           "CMD [\"--port\", \"3000\"]")
show(checker.check(shellForm + "After `docker build -t web .`, `docker run web` runs `node server.js --port 3000`."))
show(checker.check(shellForm), label: "Dockerfile alone")

heading(5, "Single quotes are not JSON: the exec form silently becomes the shell form")
show(checker.check(dockerfile("FROM node:20-slim", "COPY . .", "CMD ['node', 'server.js']")
    + "When the container starts it runs `node server.js`. Single quotes work fine in the exec form of CMD."))

heading(6, "A stage built on another: ENTRYPOINT empties the CMD it inherited")
let staged = dockerfile("FROM node:20-slim AS base", "WORKDIR /srv", "COPY . .", "CMD [\"node\", \"server.js\"]", "",
                        "FROM base", "RUN apt-get update && apt-get install -y tini", "ENTRYPOINT [\"tini\", \"--\"]")
show(checker.check(staged
    + "Build with `docker build -t web .`; `docker run web` runs `tini -- node server.js`, because setting ENTRYPOINT "
    + "keeps the CMD from the base image."))

heading(7, "A base image the Dockerfile does not show: quiet when the Dockerfile agrees")
let node = dockerfile("FROM node:20", "WORKDIR /srv", "COPY . .", "CMD [\"node\", \"server.js\"]")
show(checker.check(node + "Build with `docker build -t web .`, then `docker run web` runs `node server.js`."))
show(checker.check(node + "Build with `docker build -t web .`, then `docker run web --inspect` runs "
    + "`node server.js --inspect`."), label: "with an argument")

heading(8, "A conversation: a repeat is marked, another topic stays quiet")
let ledger = EntrypointLedger()
let wrongDebug = "`docker run api --debug` runs `python app.py --port 80 --debug`."
show(await ledger.review(api + build + wrongDebug, context: question), label: "turn 1")
show(await ledger.review("You're right to ask. To be precise, `docker run api --debug` runs "
    + "`python app.py --port 80 --debug`.", context: "Are you sure?"), label: "turn 2")
show(await ledger.review("The regex `^v\\d+` matches `v12`.", context: "And a version regex?"), label: "turn 3")
show(await ledger.review(rewrite, context: "So how do I keep the port?"), label: "turn 4")
let stats = await ledger.statistics
print("    ledger: \(stats.reviews) reviews, \(stats.claims) claims, \(stats.flagged) flagged, "
    + "\(stats.repeated) repeated")

heading(9, "The model on its own: what each run executes")
let source = "FROM python:3.12-slim\nENTRYPOINT [\"python\", \"app.py\"]\nCMD [\"--port\", \"80\"]"
let config = ImageCommands(Dockerfile(source))
for line in ["docker run api", "docker run api --port 9000", "docker run --entrypoint sh api -c 'ls /app'",
             "docker run -it --rm -p 8080:80 api --debug", "docker run --entrypoint \"\" api"] {
    guard let run = DockerRun(line) else { continue }
    let launch = config.launch(run)
    print("    \(line)  ->  " + (launch.refused ? "refused: no command specified" : launch.display))
}
