#!/usr/bin/env python3
"""Report modules that no deployable root reaches (informational unless --check).

A module is a directory under modules/ holding a versions.tf (same definition as
scripts/check-docs-counts.sh). Every `source = "<relative path>"` in a *.tf file
is resolved against that file's directory, building a module-call graph. Each
module is then classified:

  wired         reachable (transitively) from an envs/** root
  example-only  not wired, but called by an examples/ configuration
  experimental  unreferenced, and its README carries the line "> Status: experimental"
  unreferenced  not wired, not called by any example, and not marked experimental

Calls made from *.tftest.hcl suites do not count: a test harness is not a caller.
Modules labelled "library-only" in README.md are expected to appear here.

Usage: scripts/check-module-usage.py [--quiet] [--check]
  default  informational, exit status 0
  --check  exit 1 when any module is `unreferenced:` (wire it, or mark its README
           with the line "> Status: experimental")
"""

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict
from pathlib import Path

# MODULE_USAGE_ROOT lets tests point the script at a temp tree.
ROOT = Path(os.environ.get("MODULE_USAGE_ROOT") or Path(__file__).resolve().parent.parent).resolve()
SKIP_DIRS = {".git", ".terraform", ".claude", "node_modules"}
SOURCE = re.compile(r'^\s*source\s*=\s*"(\.{1,2}/[^"]+)"', re.MULTILINE)


def tf_files(base: Path):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(".tf"):
                yield Path(dirpath) / name


def module_dirs() -> set[Path]:
    mods = set()
    for f in (ROOT / "modules").rglob("versions.tf"):
        if any(part in ("examples", "tests", ".terraform") for part in f.relative_to(ROOT).parts):
            continue
        mods.add(f.parent.resolve())
    return mods


def rel(p: Path) -> str:
    return p.relative_to(ROOT).as_posix()


def main() -> int:
    quiet = "--quiet" in sys.argv[1:]
    modules = module_dirs()
    edges: dict[Path, set[Path]] = defaultdict(set)  # caller config dir -> called module dirs
    for base in ("envs", "modules", "examples"):
        if not (ROOT / base).is_dir():
            continue
        for f in tf_files(ROOT / base):
            text = f.read_text(encoding="utf-8", errors="replace")
            for src in SOURCE.findall(text):
                target = (f.parent / src.split("//", 1)[0]).resolve()
                if target in modules:
                    edges[f.parent.resolve()].add(target)

    def reach(starts: set[Path]) -> set[Path]:
        seen: set[Path] = set()
        stack = list(starts)
        while stack:
            node = stack.pop()
            for nxt in edges.get(node, ()):
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        return seen

    def under(top: str, p: Path) -> bool:
        parts = p.relative_to(ROOT).parts
        return parts[0] == top if top != "examples" else "examples" in parts

    callers = set(edges)
    wired = reach({c for c in callers if under("envs", c)})
    from_examples = reach({c for c in callers if under("examples", c)}) - wired

    example_only = sorted(rel(m) for m in from_examples)
    uncalled = sorted(rel(m) for m in modules - wired - from_examples)
    marker = "> Status: experimental"

    def has_marker(m: str) -> bool:
        readme = ROOT / m / "README.md"
        if not readme.is_file():
            print(f"check-module-usage: {m} has no README.md; treated as unmarked", file=sys.stderr)
            return False
        text = readme.read_text(encoding="utf-8", errors="replace")
        return any(line.strip() == marker for line in text.splitlines())

    experimental = [m for m in uncalled if has_marker(m)]
    # Stale markers: a module that is wired or example-called but still says experimental.
    stale = sorted(rel(m) for m in (wired | from_examples) & modules if has_marker(rel(m)))
    unreferenced = [m for m in uncalled if m not in experimental]

    print(f"check-module-usage: {len(modules)} modules — {len(wired & modules)} wired into a root, "
          f"{len(example_only)} example-only, {len(experimental)} experimental, "
          f"{len(unreferenced)} unreferenced")
    if not quiet:
        for m in example_only:
            print(f"  example-only:  {m}")
        for m in experimental:
            print(f"  experimental:  {m}")
        for m in unreferenced:
            print(f"  unreferenced:  {m}")
    for m in stale:
        print(f"check-module-usage: WARNING {m} has a caller but still carries "
              f'"{marker}"; remove the marker', file=sys.stderr)
    if "--check" in sys.argv[1:] and unreferenced:
        print("check-module-usage: FAIL - wire the module, or add the line "
              f'"{marker}" to its README.', file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
