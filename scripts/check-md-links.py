#!/usr/bin/env python3
"""Fail if any Markdown file links to a repo-relative path that does not exist.

Offline and dependency-free (stdlib only), so it runs identically in CI and
locally via `make links`. Scope is deliberately narrow:

  * checks inline links `[text](target)`, images `![alt](target)` and
    reference definitions `[id]: target`;
  * ignores external schemes (http, https, mailto, ...) and pure `#anchor`
    links — anchors are not validated, only that the target file/dir exists;
  * ignores anything inside fenced code blocks or inline code spans.

Usage: scripts/check-md-links.py [ROOT]   (default: repository root)
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

SKIP_DIRS = {".git", ".terraform", "node_modules", ".claude", ".venv", "reports"}
INLINE_LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$")
INLINE_CODE = re.compile(r"`+[^`]*`+")
FENCE = re.compile(r"^\s*(```|~~~)")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
# github.com UI routes reached by climbing out of the blob tree, e.g. SECURITY.md
# linking `../../discussions`. They only resolve on github.com, never on disk.
GITHUB_UI_ROUTES = {"discussions", "issues", "pulls", "security", "actions", "wiki", "releases"}
# Scaffolding placeholders in templates/ (replaced when a module is cloned).
PLACEHOLDER = "MODULE_NAME"


def iter_markdown(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.lower().endswith(".md"):
                yield Path(dirpath) / name


def targets(text: str):
    in_fence = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        stripped = INLINE_CODE.sub("", line)
        for match in INLINE_LINK.finditer(stripped):
            yield lineno, match.group(1)
        ref = REF_DEF.match(stripped)
        if ref:
            yield lineno, ref.group(1)


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent).resolve()
    broken: list[str] = []
    checked = 0
    for md in sorted(iter_markdown(root)):
        text = md.read_text(encoding="utf-8", errors="replace")
        for lineno, target in targets(text):
            if SCHEME.match(target) or target.startswith("#"):
                continue
            path_part = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not path_part:
                continue
            base = root if path_part.startswith("/") else md.parent
            resolved = (base / path_part.lstrip("/")).resolve()
            if PLACEHOLDER in path_part:
                continue
            if root not in resolved.parents and resolved != root:
                if resolved.name in GITHUB_UI_ROUTES:
                    continue
            checked += 1
            if not resolved.exists():
                broken.append(f"{md.relative_to(root)}:{lineno}: broken link -> {target}")
    for line in broken:
        print(line)
    print(f"check-md-links: {checked} relative links checked, {len(broken)} broken", file=sys.stderr)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
