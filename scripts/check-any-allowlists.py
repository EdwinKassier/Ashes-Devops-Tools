#!/usr/bin/env python3
"""Fail when a key allowlist for an untyped (`type = any`) input drifts from the
typed object it is forwarded to, or when an `any` input has no allowlist.

An `any` input keeps a misspelled key visible, and a validation rejects keys
outside an allowlist. If the allowlist names a key the downstream object type
does not declare, type conversion drops it silently. If the downstream type
gains an attribute the allowlist lacks, nobody can set it.

Allowlists live in <owner>/allowed_keys.tf, and only there:
    locals { allowed_keys = { <variable> = { <path> = ["key", ...] } } }
<path> is "self" for the top level or a dotted attribute path. The validations
of <variable> read local.allowed_keys.<variable>. The manifest
(scripts/any-allowlists.json) maps each (owner, variable, path) to the stage
variable whose type must match, and lists exempt `any` inputs with a reason.

Checks:
  - every allowlist equals the attribute set of the stage type at that path
    (less the row's root_only keys, which the owner consumes itself);
  - every path in allowed_keys.tf has a manifest row, and every row a path;
  - every `type = any` input under envs/ and modules/ has a row or an
    exempt entry with a reason, and every row names a real `any` input;
  - each allowlisted variable's block reads local.allowed_keys.<variable>.

Standard library only (python-hcl2 returns a type constraint as an opaque
"${...}" string, so a small tokenizer reads the type expressions instead).

Usage: scripts/check-any-allowlists.py [ROOT] [MANIFEST]
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
MANIFEST = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "scripts" / "any-allowlists.json"
SKIP = {".terraform", "tests", "examples", ".git"}
TOKEN = re.compile(r'\s+|#[^\n]*|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_-]*|-?[0-9][0-9.]*|.', re.S)
WRAPPERS = {"map", "list", "set", "optional"}
VAR_HEAD = re.compile(r'^variable\s+"([^"]+)"\s*\{', re.M)
ANY_TYPE = re.compile(r"^\s*type\s*=\s*any\s*(#.*)?$", re.M)


def tokens(text: str) -> list[str]:
    out = []
    for m in TOKEN.finditer(text):
        t = m.group(0)
        if t.isspace() or t.startswith(("#", "//", "/*")):
            continue
        out.append(t)
    return out


class Parser:
    def __init__(self, toks: list[str]):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self, want=None):
        tok = self.peek()
        if tok is None or (want is not None and tok != want):
            raise SyntaxError(f"expected {want!r}, got {tok!r}")
        self.i += 1
        return tok

    def seq(self, close: str):
        items = []
        while self.peek() != close:
            items.append(self.expr())
            if self.peek() == ",":
                self.take()
        self.take(close)
        return items

    def expr(self):
        tok = self.take()
        if tok == "{":
            obj = {}
            while self.peek() != "}":
                key = self.take().strip('"')
                if self.peek() in ("=", ":"):
                    self.take()
                obj[key] = self.expr()
                if self.peek() == ",":
                    self.take()
            self.take("}")
            return ("obj", obj)
        if tok == "[":
            return ("list", self.seq("]"))
        if self.peek() == "(":
            self.take("(")
            return ("call", tok, self.seq(")"))
        return ("lit", tok[1:-1] if tok.startswith('"') else tok)


def variable_blocks(text: str) -> dict[str, str]:
    """Variable name -> text of its block (up to the next variable)."""
    heads = list(VAR_HEAD.finditer(text))
    return {
        m.group(1): text[m.end(): heads[i + 1].start() if i + 1 < len(heads) else len(text)]
        for i, m in enumerate(heads)
    }


def variable_type(path: Path, name: str):
    body = variable_blocks(path.read_text(encoding="utf-8")).get(name)
    if body is None:
        raise LookupError(f"{path.relative_to(ROOT)}: no variable {name!r}")
    t = re.compile(r"^\s*type\s*=", re.M).search(body)
    if not t:
        raise LookupError(f"{path.relative_to(ROOT)}: variable {name!r} has no type")
    return Parser(tokens(body[t.end():])).expr()


def attributes(node):
    while node and node[0] == "call" and node[1] in WRAPPERS and node[2]:
        node = node[2][0]
    if node and node[0] == "call" and node[1] == "object" and node[2] and node[2][0][0] == "obj":
        return node[2][0][1]
    return None


def resolve(node, dotted: str):
    attrs = attributes(node)
    for seg in [s for s in dotted.split(".") if s and s != "self"]:
        if attrs is None or seg not in attrs:
            return None
        attrs = attributes(attrs[seg])
    return attrs


def allowlists(owner: Path) -> dict:
    f = owner / "allowed_keys.tf"
    if not f.is_file():
        return {}
    text = f.read_text(encoding="utf-8")
    m = re.search(r"^\s*allowed_keys\s*=", text, re.M)
    if not m:
        return {}
    node = Parser(tokens(text[m.end():])).expr()
    return {
        var: {p: sorted(item[1] for item in lst[1]) for p, lst in paths[1].items()}
        for var, paths in node[1].items()
    }


def any_inputs() -> dict[tuple[str, str], str]:
    """(owner, variable) -> variable block text, for every `type = any` input."""
    found = {}
    for base in ("envs", "modules"):
        for dirpath, dirnames, filenames in os.walk(ROOT / base):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
            if "variables.tf" not in filenames:
                continue
            vf = Path(dirpath) / "variables.tf"
            owner = vf.parent.relative_to(ROOT).as_posix()
            for name, body in variable_blocks(vf.read_text(encoding="utf-8")).items():
                if ANY_TYPE.search(body):
                    found[(owner, name)] = body
    return found


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    rows = manifest["allowlists"]
    exempt = manifest.get("exempt", [])
    inputs = any_inputs()
    errors: list[str] = []
    owners: dict[str, dict] = {}

    for row in rows:
        where = f"{row['owner']}/allowed_keys.tf allowed_keys.{row['variable']}.{row['path']}"
        lists = owners.setdefault(row["owner"], allowlists(ROOT / row["owner"]))
        allowed = lists.get(row["variable"], {}).get(row["path"])
        if allowed is None:
            errors.append(f"{where}: missing")
            continue
        stage_path = row.get("stage_path", row["path"])
        try:
            node = variable_type(ROOT / row["stage"] / "variables.tf", row["stage_variable"])
        except (LookupError, OSError, SyntaxError) as exc:
            errors.append(f"{where}: cannot read the stage type ({exc})")
            continue
        attrs = resolve(node, stage_path)
        if attrs is None:
            errors.append(f"{where}: {row['stage']} variable {row['stage_variable']} has no object at {stage_path}")
            continue
        # root_only: keys the owner consumes itself and strips before forwarding
        # (app_services.service_team picks the project), so the stage never sees them.
        root_only = set(row.get("root_only", []))
        extra = sorted(set(allowed) - set(attrs) - root_only)
        missing = sorted(set(attrs) - set(allowed))
        if extra:
            errors.append(f"{where}: {', '.join(extra)} not in {row['stage']} {row['stage_variable']} (the stage type would drop them silently)")
        if missing:
            errors.append(f"{where}: lacks {', '.join(missing)} that {row['stage']} {row['stage_variable']} accepts")

    listed = {(r["owner"], r["variable"], r["path"]) for r in rows}
    for owner, lists in sorted(owners.items()):
        for var, paths in sorted(lists.items()):
            for p in sorted(paths):
                if (owner, var, p) not in listed:
                    errors.append(f"{owner}/allowed_keys.tf allowed_keys.{var}.{p}: no row in {MANIFEST.name}, so nothing checks it")

    covered = {(r["owner"], r["variable"]) for r in rows}
    for e in exempt:
        if not str(e.get("reason", "")).strip():
            errors.append(f"{MANIFEST.name}: exempt {e['owner']} {e['variable']} has no reason")
    for owner, var in sorted(covered | {(e["owner"], e["variable"]) for e in exempt}):
        if (owner, var) not in inputs:
            errors.append(f"{MANIFEST.name}: {owner} variable {var} is not a `type = any` input (stale row)")
    for owner, var in sorted(covered):
        body = inputs.get((owner, var))
        if body is not None and f"local.allowed_keys.{var}" not in body:
            errors.append(f"{owner}: variable {var} has an allowlist row but no validation reads local.allowed_keys.{var}")
    exempted = {(e["owner"], e["variable"]) for e in exempt}
    for owner, var in sorted(inputs):
        if (owner, var) not in covered | exempted:
            errors.append(f"{owner}: variable {var} is `any` with no allowlist row in {MANIFEST.name}")

    for e in errors:
        print(f"check-any-allowlists: {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"check-any-allowlists: {len(rows)} allowlists match their stage types; {len(exempted)} exempt any input(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
