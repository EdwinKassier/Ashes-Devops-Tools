#!/usr/bin/env python3
"""Fail when a GitHub Actions `run:` step pipes without pipefail.

GitHub runs a `run:` step with no `shell:` (step, job `defaults.run.shell` or
workflow `defaults.run.shell`) as `bash -e {0}`: no pipefail, so
`if ! cmd | tee log` tests only `tee` and a failing `cmd` passes the step.
`shell: bash` runs `bash --noprofile --norc -eo pipefail {0}`.

A step whose script has a pipe must therefore run under `shell: bash` (at step,
job or workflow level), under a custom shell string that sets pipefail, or set
`-o pipefail` itself. Steps under a non-POSIX shell (python, pwsh, node, cmd)
are skipped. A `|` inside single quotes, in a comment line or as part of `||`
is not a pipe.

No YAML library: an indentation-based reader is enough for workflow files and
keeps this runnable on a bare python3 (it runs in `make consistency`).

  python3 scripts/check-workflow-pipefail.py [dir ...]
  (default: .github/workflows examples/app-delivery)
"""
import pathlib
import re
import sys

DEFAULT_DIRS = [".github/workflows", "examples/app-delivery"]
NON_POSIX = ("python", "pwsh", "powershell", "node", "cmd")
KEY_RE = re.compile(r"^([A-Za-z0-9_.-]+):(?:\s+(.*))?$")
BLOCK_RE = re.compile(r"^[|>][-+0-9]*\s*(#.*)?$")
PIPE_RE = re.compile(r"(?<![|])\|(?![|])")
SET_PIPEFAIL_RE = re.compile(r"(^|[;&\s])set\s+(-[A-Za-z]*\s+)*-[A-Za-z]*o\s+pipefail\b|set\s+-o\s+pipefail\b")


def strip_scalar(v):
    v = re.sub(r"\s+#.*$", "", v or "").strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = v[1:-1]
    return v


def parse(text):
    """Yield (path tuple, value, step id) for every key; block scalars joined."""
    lines = text.splitlines()
    stack = []  # (indent, name)
    step_counter = 0
    i = 0
    while i < len(lines):
        raw = lines[i]
        i += 1
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        body = raw.strip()
        while body.startswith("- ") or body == "-":
            while stack and stack[-1][0] >= indent:
                stack.pop()
            if stack and stack[-1][1] == "steps":
                step_counter += 1
            stack.append((indent, "[]#%d" % step_counter))
            rest = body[1:].lstrip(" ")
            indent += len(body) - len(rest)
            body = rest
            if not body:
                break
        m = KEY_RE.match(body)
        if not m:
            continue
        key, value = m.group(1), m.group(2)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if value is not None and BLOCK_RE.match(value.strip()):
            block = []
            while i < len(lines):
                nxt = lines[i]
                if nxt.strip() and len(nxt) - len(nxt.lstrip(" ")) <= indent:
                    break
                block.append(nxt)
                i += 1
            value = "\n".join(block)
        elif value is not None:
            value = strip_scalar(value)
        path = tuple(n for _, n in stack) + (key,)
        step = next((n for _, n in reversed(stack) if n.startswith("[]#")), None)
        yield path, value, step
        stack.append((indent, key))


def has_pipe(script):
    for line in script.splitlines():
        if line.strip().startswith("#"):
            continue
        line = re.sub(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"", "", line)
        if PIPE_RE.search(line):
            return True
    return False


def shell_ok(shell, script):
    if shell is None or shell.split()[0] in ("sh", "bash"):
        if shell == "bash" or (shell and "pipefail" in shell):
            return True
        return bool(SET_PIPEFAIL_RE.search(script))
    return True  # a non-POSIX shell: pipes are not shell pipes there


def check_file(path):
    wf_shell = None
    job_shell = {}
    steps = {}  # step id -> dict(job, name, shell, run)
    for p, value, step in parse(path.read_text()):
        if p == ("defaults", "run", "shell"):
            wf_shell = value
        elif len(p) == 5 and p[0] == "jobs" and p[2:] == ("defaults", "run", "shell"):
            job_shell[p[1]] = value
        elif step and len(p) == 5 and p[0] == "jobs" and p[2] == "steps" and p[4] in ("name", "shell", "run"):
            s = steps.setdefault(step, {"job": p[1], "name": None, "shell": None, "run": None})
            s[p[4]] = value
    errors = []
    for sid, s in steps.items():
        if not s["run"] or not has_pipe(s["run"]):
            continue
        shell = s["shell"] or job_shell.get(s["job"]) or wf_shell
        if shell and shell.split()[0] in NON_POSIX:
            continue
        if not shell_ok(shell, s["run"]):
            label = s["name"] or "#" + sid.split("#")[1]
            errors.append(
                '%s: job %s, step "%s" pipes without pipefail (shell: %s); set '
                "`defaults: run: shell: bash` or `shell: bash`" % (path, s["job"], label, shell or "unset, bash -e {0}")
            )
    return errors


def main(argv):
    dirs = argv[1:] or DEFAULT_DIRS
    files = []
    for d in dirs:
        files += sorted(pathlib.Path(d).glob("*.yml")) + sorted(pathlib.Path(d).glob("*.yaml"))
    if not files:
        print("check-workflow-pipefail: no workflow files in %s" % " ".join(dirs), file=sys.stderr)
        return 1
    errors = []
    for f in files:
        errors += check_file(f)
    for e in errors:
        print("  FAIL " + e, file=sys.stderr)
    print("check-workflow-pipefail: %d workflow file(s) checked, %d failure(s)" % (len(files), len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
