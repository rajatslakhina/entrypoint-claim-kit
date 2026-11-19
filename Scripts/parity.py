#!/usr/bin/env python3
"""Builds every case with the classic `docker build --no-cache` (the build cache can hand back an image whose CMD was
kept by an earlier build, so it is always off), reads the image's Entrypoint and Cmd with `docker inspect`, then asks
the daemon what each `docker run` would execute: `docker create` composes the process from the image config and the
run's flags and arguments, and `docker inspect` of the container shows it as Path and Args. Writes a Swift fixture.

Usage: python3 -I Scripts/parity.py Tests/EntrypointClaimKitTests/ParityFixture.swift
Needs a running Docker daemon and the swift:6.0 image (any local image works as the base; its own config is
Entrypoint null, Cmd ["/bin/bash"]). Removes every image and container it makes.
"""
import json, os, subprocess, sys, tempfile

B = "FROM swift:6.0 AS base0\n"
T = "parity-entrypoint"
# (name, Dockerfile, runs). A run is (flags, arguments); the image goes between them.
CASES = [
    ("exec cmd", B + 'CMD ["node", "server.js"]\n', [([], []), ([], ["bash"]), ([], ["node", "x.js"])]),
    ("shell cmd", B + "CMD node server.js\n", [([], []), ([], ["sh"])]),
    ("shell cmd compound", B + "CMD npm run migrate && npm start\n", [([], [])]),
    ("exec entrypoint", B + 'ENTRYPOINT ["python", "app.py"]\n', [([], []), ([], ["--debug"]), ([], ["bash"])]),
    ("exec entrypoint exec cmd", B + 'ENTRYPOINT ["python", "app.py"]\nCMD ["--port", "80"]\n',
     [([], []), ([], ["--port", "8080"]), (["--entrypoint", "bash"], []), (["--entrypoint", "bash"], ["-c", "ls"]),
      (["--entrypoint=sh"], []), (["--entrypoint", ""], []), (["--entrypoint", ""], ["ls", "-l"])]),
    ("exec entrypoint shell cmd", B + 'ENTRYPOINT ["python", "app.py"]\nCMD python app.py --port 80\n', [([], []), ([], ["--port", "1"])]),
    ("shell cmd starting with a flag", B + 'ENTRYPOINT ["python", "app.py"]\nCMD --port 80\n', [([], [])]),
    ("exec cmd starting with a flag", B + 'ENTRYPOINT ["python", "app.py"]\nCMD ["--port", "80"]\n', [([], [])]),
    ("shell entrypoint", B + "ENTRYPOINT python app.py\n", [([], []), ([], ["--debug"])]),
    ("shell entrypoint exec cmd", B + 'ENTRYPOINT python app.py\nCMD ["--port", "80"]\n', [([], []), ([], ["--x"])]),
    ("shell entrypoint with exec", B + "ENTRYPOINT exec python app.py\n", [([], [])]),
    ("cmd before entrypoint", B + 'CMD ["--port", "80"]\nENTRYPOINT ["python", "app.py"]\n', [([], [])]),
    ("two cmds", B + 'CMD ["node", "a.js"]\nCMD ["node", "b.js"]\n', [([], [])]),
    ("two entrypoints", B + 'ENTRYPOINT ["a"]\nENTRYPOINT ["b"]\nCMD ["c"]\n', [([], [])]),
    ("single quotes", B + "CMD ['node', 'server.js']\n", [([], [])]),
    ("trailing comma", B + 'CMD ["node", "server.js",]\n', [([], [])]),
    ("single quotes entrypoint", B + "ENTRYPOINT ['python', 'app.py']\nCMD [\"--x\"]\n", [([], [])]),
    ("spaces in array", B + 'CMD [ "node" , "a b.js" ]\n', [([], [])]),
    ("escaped quote", B + 'CMD ["echo", "say \\"hi\\""]\n', [([], [])]),
    ("backslash", B + 'CMD ["echo", "C:\\\\dir"]\n', [([], [])]),
    ("empty cmd", B + "CMD []\n", [([], []), ([], ["ls"])]),
    ("empty entrypoint clears", B + 'ENTRYPOINT ["a"]\nCMD ["c"]\nENTRYPOINT []\n', [([], [])]),
    ("variable stays literal", B + 'CMD ["echo", "$HOME"]\n', [([], [])]),
    ("shell keeps variable text", B + 'CMD echo "$HOME"\n', [([], [])]),
    ("shell instruction", B + 'SHELL ["/bin/bash", "-c"]\nCMD node server.js\n', [([], [])]),
    ("shell instruction entrypoint", B + 'SHELL ["/bin/bash", "-o", "pipefail", "-c"]\nENTRYPOINT python app.py\n', [([], [])]),
    ("stage cmd then entrypoint", B + 'CMD ["node", "a.js"]\nFROM base0\nENTRYPOINT ["tini", "--"]\n', [([], [])]),
    ("stage cmd then entrypoint and cmd", B + 'CMD ["node", "a.js"]\nFROM base0\nENTRYPOINT ["tini", "--"]\nCMD ["node", "b.js"]\n', [([], [])]),
    ("stage entrypoint then cmd", B + 'ENTRYPOINT ["tini", "--"]\nFROM base0\nCMD ["node", "b.js"]\n', [([], []), ([], ["sh"])]),
    ("stage cmd inherited", B + 'CMD ["node", "a.js"]\nFROM base0 AS mid\nRUN true\nFROM mid\n', [([], [])]),
    ("stage shell inherited", B + 'SHELL ["/bin/bash", "-c"]\nFROM base0\nCMD node a.js\n', [([], [])]),
    ("unrelated stage", B + 'CMD ["node", "a.js"]\nFROM swift:6.0\nRUN true\n', [([], [])]),
    ("base cmd cleared", B + 'ENTRYPOINT ["python"]\n', [([], []), ([], ["app.py"])]),
    ("base config", B + "RUN true\n", [([], []), ([], ["ls"])]),
    ("onbuild and healthcheck", B + 'ONBUILD CMD ["x"]\nHEALTHCHECK CMD ["true"]\nCMD ["node", "a.js"]\n', [([], [])]),
    ("continuation", B + 'CMD ["node", \\\n    "server.js"]\n', [([], [])]),
    ("lowercase keyword", B + 'cmd ["node", "a.js"]\nentrypoint ["tini", "--"]\n', [([], [])]),
    ("not string array", B + 'CMD ["node", 1]\n', [([], [])]),
    ("exec form sh -c", B + 'ENTRYPOINT ["sh", "-c", "python app.py \\"$@\\"", "--"]\nCMD ["--x"]\n', [([], []), ([], ["--y"])]),
]


def sh(*args, check=False):
    return subprocess.run(list(args), capture_output=True, text=True, check=check)


def swift_string(s):
    return json.dumps(s, ensure_ascii=False).replace("\\/", "/")


def swift_array(a):
    return "nil" if a is None else "[" + ", ".join(swift_string(x) for x in a) + "]"


def main(out_path):
    rows = []
    for name, dockerfile, runs in CASES:
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "Dockerfile"), "w") as f:
                f.write(dockerfile)
            built = sh("docker", "build", "--no-cache", "-q", "-t", T, d)
            if built.returncode != 0:
                rows.append((name, dockerfile, None, None, True, []))
                print(f"{name}: build stops", file=sys.stderr)
                continue
            cfg = json.loads(sh("docker", "inspect", "-f", "{{json .Config}}", T, check=True).stdout)
            results = []
            for flags, arguments in runs:
                made = sh("docker", "create", *flags, T, *arguments)
                if made.returncode != 0:
                    results.append((flags, arguments, None))
                    continue
                cid = made.stdout.strip()
                info = json.loads(sh("docker", "inspect", "-f", "{{json .}}", cid, check=True).stdout)
                results.append((flags, arguments, [info["Path"]] + (info["Args"] or [])))
                sh("docker", "rm", cid)
            rows.append((name, dockerfile, cfg.get("Entrypoint"), cfg.get("Cmd"), False, results))
            sh("docker", "rmi", "-f", T)
            print(f"{name}: {cfg.get('Entrypoint')} {cfg.get('Cmd')} {[r[2] for r in results]}", file=sys.stderr)
    lines = ["// Generated by Scripts/parity.py from the classic `docker build --no-cache` and `docker create`.",
             "// Do not edit by hand: rerun the script.", "", "struct ParityRun {", "    let flags: [String]",
             "    let arguments: [String]", "    /// What the daemon executes (Path then Args); nil when it refuses.",
             "    let argv: [String]?", "}", "", "struct ParityCase {", "    let name: String", "    let dockerfile: String",
             "    let entrypoint: [String]?", "    let cmd: [String]?", "    let buildStops: Bool", "    let runs: [ParityRun]",
             "}", "", "let parityCases: [ParityCase] = ["]
    for name, dockerfile, ep, cmd, stops, results in rows:
        runs = ", ".join(f"ParityRun(flags: {swift_array(f)}, arguments: {swift_array(a)}, argv: {swift_array(v)})"
                         for f, a, v in results)
        lines.append(f"    ParityCase(name: {swift_string(name)}, dockerfile: {swift_string(dockerfile)},")
        lines.append(f"               entrypoint: {swift_array(ep)}, cmd: {swift_array(cmd)}, buildStops: {'true' if stops else 'false'},")
        lines.append(f"               runs: [{runs}]),")
    lines.append("]")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
