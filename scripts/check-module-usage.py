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


LINK = re.compile(r"\]\((modules/[^)#]+?)/?\)")
HEADER = re.compile(r"<strong>([^<]+)</strong> — GCP (\d+) · AWS (\d+)")


def check_readme(modules: set[Path], wired: set[Path]) -> list[str]:
    """Cross-check README.md against the module graph. Skipped when there is no README.md."""
    readme = ROOT / "README.md"
    if not readme.is_file():
        return []
    text = readme.read_text(encoding="utf-8", errors="replace")
    errors: list[str] = []

    # 1. Library-only labels. The module a "*(library-only)*" mark belongs to is the
    #    last link before it. Every labelled or tabled module must be unwired, and
    #    every unwired module must be in the "Library-only modules" table.
    marked: set[str] = set()
    for line in text.splitlines():
        for segment in line.split("*(library-only)*")[:-1]:
            found = LINK.findall(segment)
            if found:
                marked.add(found[-1])
    section = ""
    if "Library-only modules" in text:
        section = text.split("Library-only modules", 1)[1].split("</details>", 1)[0]
    table = {
        path
        for line in section.splitlines() if line.startswith("| [")
        for path in LINK.findall(line.split("|")[1])
    }
    unwired = {rel(m) for m in modules - wired}
    for m in sorted((marked | table) - unwired):
        errors.append(f"README.md labels {m} library-only, but an envs/** root composes it")
    for m in sorted(unwired - table):
        errors.append(f"{m} is not wired into any root but is missing from README.md's Library-only table")

    # 2. Domain tables ("Cloud modules by domain"): each header's GCP/AWS counts must equal
    #    the distinct modules linked in that column, and every cloud module must be linked.
    if "### Cloud modules by domain" not in text:
        return errors
    domains = text.split("### Cloud modules by domain", 1)[1].split("Library-only modules", 1)[0]
    linked: set[str] = set()
    for block in domains.split("<details>")[1:]:
        header = HEADER.search(block)
        if not header:
            continue
        cols: list[set[str]] = [set(), set()]
        for line in block.splitlines():
            cells = line.split("|")
            if line.startswith("| ") and len(cells) >= 5:
                for i in (0, 1):
                    cols[i].update(LINK.findall(cells[2 + i]))
        linked |= cols[0] | cols[1]
        want = (int(header.group(2)), int(header.group(3)))
        got = (len(cols[0]), len(cols[1]))
        if want != got:
            errors.append(f"README.md domain '{header.group(1)}' says GCP {want[0]} / AWS {want[1]}, "
                          f"but its table links GCP {got[0]} / AWS {got[1]} modules")
    for m in sorted(rel(x) for x in modules):
        if m.startswith(("modules/gcp/", "modules/aws/")) and m not in linked:
            errors.append(f"{m} is not linked in any README.md domain table")
    return errors


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
    readme_errors = check_readme(modules, wired)
    for e in readme_errors:
        print(f"check-module-usage: {e}", file=sys.stderr)
    if "--check" in sys.argv[1:] and (unreferenced or readme_errors):
        if unreferenced:
            print("check-module-usage: FAIL - wire the module, or add the line "
                  f'"{marker}" to its README.', file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
