#!/usr/bin/env python3
"""Fail when an example root passes an attribute a module's object type lacks.

Terraform converts a module argument to the variable's type and silently drops
object attributes the type does not declare, so `terraform validate` passes an
example that sets, say, `iam_bindings` inside a kms `keys` entry: the grant is
never made and nothing says so. This check parses every module call with a
local source in examples/<root>/*.tf (python-hcl2, hash-locked in
.github/requirements/hcl2.txt), reads the called module's variable types and
fails on:
  - a top-level argument that is not a variable of the module;
  - a literal object key that the variable's type does not declare, at any
    depth of object(...), map(...), list(...), set(...) and optional(...).

Limits (docs/known-gaps.md): values that are expressions (a local, a for
expression, a function call) are not followed; tuple(...) and `any` types are
not checked; a variable whose type cannot be parsed is reported (exit 1) so a
gap is visible instead of silent.

  python3 scripts/check-example-module-attrs.py [EXAMPLES_DIR]
    (default: examples/; CI via scripts/check-consistency.sh)

Exit codes: 0 clean, 1 problems, 2 python-hcl2 missing.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import hcl2
except ImportError:
    sys.stderr.write(
        "check-example-module-attrs: python-hcl2 is missing. Install the pinned version:\n"
        "  python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt\n"
    )
    sys.exit(2)

REPO = Path(__file__).resolve().parent.parent
META_ARGS = {"source", "version", "count", "for_each", "providers", "depends_on"}
# Example folders that hold Markdown snippets, not a Terraform root.
SKIP_ROOTS = {"system-design"}


class TypeParseError(Exception):
    pass


def unquote(s: str) -> str:
    return s[1:-1] if len(s) >= 2 and s[0] == s[-1] == '"' else s


# --- type expressions ---------------------------------------------------------
# python-hcl2 7.3.1 renders a type as one string, with each nested expression
# wrapped as "${...}" and object attributes as "name": type. Unwrapping the
# "${ ... }" markers gives plain HCL type syntax that the parser below reads.
# Strings inside a list default lose their quotes, so any other run of text is
# one token: defaults are skipped, never interpreted.
TOKEN = re.compile(r'\s*(?:(?P<str>"(?:[^"\\]|\\.)*")|(?P<id>[A-Za-z_][A-Za-z0-9_-]*)|(?P<p>[(){}\[\],:=])|(?P<other>[^\s(){}\[\],:="]+))')


def tokenize(s: str) -> list[str]:
    out, i = [], 0
    while i < len(s):
        if s[i:].strip() == "":
            break
        m = TOKEN.match(s, i)
        if not m:
            raise TypeParseError(f"unexpected text at {s[i:i + 30]!r}")
        out.append(m.group(m.lastgroup))
        i = m.end()
    return out


class Parser:
    """Type := name | name '(' Type ')' | object '(' '{' (key ':' Type ,)* '}' ')'
    | optional '(' Type [, default] ')'. Result: ("object", {attr: Type}),
    ("map"|"list"|"set"|"optional", Type) or ("leaf",) for anything unchecked."""

    def __init__(self, toks: list[str]):
        self.t, self.i = toks, 0

    def peek(self) -> str | None:
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self, want: str | None = None) -> str:
        tok = self.peek()
        if tok is None or (want is not None and tok != want):
            raise TypeParseError(f"expected {want!r}, got {tok!r}")
        self.i += 1
        return tok

    def skip_value(self) -> None:
        depth = 0
        while True:
            tok = self.peek()
            if tok is None:
                raise TypeParseError("unbalanced default value")
            if depth == 0 and tok in (",", ")"):
                return
            if tok in "([{":
                depth += 1
            elif tok in ")]}":
                depth -= 1
            self.i += 1

    def parse(self):
        name = self.take()
        if self.peek() != "(":
            return ("leaf",)
        self.take("(")
        if name == "object":
            self.take("{")
            attrs = {}
            while self.peek() != "}":
                key = unquote(self.take())
                if self.peek() not in (":", "="):
                    raise TypeParseError(f"expected ':' after {key!r}")
                self.take()
                attrs[key] = self.parse()
                if self.peek() == ",":
                    self.take(",")
            self.take("}")
            self.take(")")
            return ("object", attrs)
        if name in ("map", "list", "set", "optional"):
            inner = self.parse()
            if name == "optional" and self.peek() == ",":
                self.take(",")
                self.skip_value()
            self.take(")")
            return ("optional" if name == "optional" else name, inner)
        # tuple(...) and anything else: skip, not checked.
        self.i -= 1
        self.skip_value_group()
        return ("leaf",)

    def skip_value_group(self) -> None:
        self.take("(")
        depth = 1
        while depth:
            tok = self.take()
            if tok in "([{":
                depth += 1
            elif tok in ")]}":
                depth -= 1


def parse_type(raw) -> tuple:
    if not isinstance(raw, str):
        raise TypeParseError(f"unexpected type value {raw!r}")
    s = raw.strip()
    if s.startswith("${") and s.endswith("}"):
        s = s[2:-1]
    s = s.replace('"${', "").replace('}"', "")
    p = Parser(tokenize(s))
    t = p.parse()
    if p.peek() is not None:
        raise TypeParseError(f"trailing text {p.peek()!r}")
    return t


# --- values ---------------------------------------------------------------------
def check_value(t: tuple, v, path: str, out: list[str]) -> None:
    kind = t[0]
    if kind == "optional":
        check_value(t[1], v, path, out)
    elif kind == "object" and isinstance(v, dict):
        for key, sub in v.items():
            k = unquote(key)
            if k not in t[1]:
                out.append(f"{path}.{k} is not an attribute of the variable's type "
                           f"(declared: {', '.join(sorted(t[1])) or 'none'})")
            else:
                check_value(t[1][k], sub, f"{path}.{k}", out)
    elif kind == "map" and isinstance(v, dict):
        for key, sub in v.items():
            check_value(t[1], sub, f'{path}["{unquote(key)}"]', out)
    elif kind in ("list", "set") and isinstance(v, list):
        for n, sub in enumerate(v):
            check_value(t[1], sub, f"{path}[{n}]", out)


def module_variables(mod_dir: Path) -> dict:
    out = {}
    for f in sorted(mod_dir.glob("*.tf")):
        with f.open(encoding="utf-8") as fh:
            doc = hcl2.load(fh)
        for block in doc.get("variable", []):
            for name, body in block.items():
                out[unquote(name)] = body.get("type")
    return out


def check_root(root: Path, rel_root: str, problems: list[str]) -> None:
    for f in sorted(root.glob("*.tf")):
        rel = f"{rel_root}/{f.name}"
        try:
            with f.open(encoding="utf-8") as fh:
                doc = hcl2.load(fh)
        except Exception as exc:  # fail closed
            problems.append(f"{rel}: cannot parse ({exc})")
            continue
        for block in doc.get("module", []):
            for name, body in block.items():
                name = unquote(name)
                src = body.get("source", "")
                if not isinstance(src, str) or not src.startswith(("./", "../")):
                    continue
                mod_dir = (root / src).resolve()
                if not mod_dir.is_dir():
                    problems.append(f'{rel}: module "{name}" source {src} does not exist')
                    continue
                try:
                    variables = module_variables(mod_dir)
                except Exception as exc:
                    problems.append(f"{rel}: cannot parse module {src} ({exc})")
                    continue
                for arg, value in body.items():
                    if arg in META_ARGS or arg.startswith("__"):
                        continue
                    where = f'{rel}: module "{name}" {arg}'
                    if arg not in variables:
                        problems.append(f"{where} is not a variable of {src}")
                        continue
                    raw = variables[arg]
                    if raw is None:
                        continue  # untyped variable: any value is accepted
                    try:
                        vtype = parse_type(raw)
                    except TypeParseError as exc:
                        problems.append(f"{where}: cannot parse the variable type ({exc})")
                        continue
                    found: list[str] = []
                    check_value(vtype, value, arg, found)
                    problems.extend(f'{rel}: module "{name}" {msg}' for msg in found)


def main() -> int:
    base = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else REPO / "examples"
    problems: list[str] = []
    roots = [d for d in sorted(base.iterdir()) if d.is_dir() and d.name not in SKIP_ROOTS and any(d.glob("*.tf"))]
    for root in roots:
        check_root(root, root.name, problems)
    for p in problems:
        print(p)
    print(f"check-example-module-attrs: {len(roots)} root(s), {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
