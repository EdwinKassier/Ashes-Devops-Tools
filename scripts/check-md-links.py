#!/usr/bin/env python3
"""Fail if any Markdown file links to a repo-relative path that does not exist.

Offline and dependency-free (stdlib only), so it runs identically in CI and
locally via `make links`. Scope is deliberately narrow:

  * checks inline links `[text](target)`, images `![alt](target)` and
    reference definitions `[id]: target`;
  * ignores external schemes (http, https, mailto, ...) and pure `#anchor`
    links — anchors are not validated, only that the target file/dir exists;
  * ignores anything inside fenced code blocks or inline code spans.

Strict backtick-path mode (opt-in, per file): in the files listed in
STRICT_PATH_FILES, every inline-code span that names a repo path under
`modules/`, `envs/`, `policies/` (e.g. `modules/aws/governance/scp/main.tf`) must
exist on disk. Spans with glob/placeholder syntax (`*`, `<env>`, `{a,b}`, `$`)
are skipped and a trailing `:LINE` / `#anchor` is ignored. A `policies/<file>`
span that is not under the top-level `policies/` dir may be module-relative
shorthand (e.g. `policies/tag-policy.json` of the organization-policy module):
it passes if exactly that file exists in some `modules/**/policies/` dir, so a
renamed file (`.json` -> `.json.tftpl`) still fails. Files mapped to True
FAIL the run on a missing path; files mapped to False only report it.

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
# Backtick-path strict mode: repo-relative file -> fail on a missing path?
STRICT_PATH_FILES = {
    "docs/compliance/control-matrix.md": True,
    "docs/known-gaps.md": False,
}
CODE_SPAN = re.compile(r"`([^`\n]+)`")
REPO_PATH = re.compile(r"^(?:\./)?((?:modules|envs|policies)/[A-Za-z0-9_./-]+)")
PATH_PLACEHOLDER = re.compile(r"[*<>{}$]")


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


def backtick_paths(text: str):
    """Yield (lineno, path) for repo paths named in inline code spans."""
    for lineno, line in enumerate(text.splitlines(), start=1):
        if FENCE.match(line):
            continue
        for span in CODE_SPAN.finditer(line):
            content = span.group(1).strip()
            match = REPO_PATH.match(content)
            if not match:
                continue
            # Only the leading path token; placeholders anywhere in it are skipped.
            token = content.split()[0]
            if PATH_PLACEHOLDER.search(token):
                continue
            path = re.sub(r":\d+(?:-\d+)?$", "", match.group(1).split("#", 1)[0]).rstrip(".,;:/")
            yield lineno, path


def check_strict_paths(root: Path) -> tuple[list[str], list[str]]:
    failing: list[str] = []
    advisory: list[str] = []
    for rel, fatal in STRICT_PATH_FILES.items():
        md = root / rel
        if not md.is_file():
            continue
        text = md.read_text(encoding="utf-8", errors="replace")
        module_policies = {
            str(p.relative_to(p.parent.parent)) for p in (root / "modules").glob("**/policies/*") if p.is_file()
        }
        for lineno, path in backtick_paths(text):
            if path.startswith("policies/") and path in module_policies:
                continue
            if not (root / path).exists():
                msg = f"{rel}:{lineno}: backtick path does not exist -> {path}"
                (failing if fatal else advisory).append(msg)
    return failing, advisory


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
    strict_fail, strict_advisory = check_strict_paths(root)
    for line in strict_fail:
        print(line)
    for line in strict_advisory:
        print(f"{line} (advisory)")
    print(
        f"check-md-links: strict backtick paths: {len(strict_fail)} failing, {len(strict_advisory)} advisory",
        file=sys.stderr,
    )
    return 1 if broken or strict_fail else 0


if __name__ == "__main__":
    sys.exit(main())
