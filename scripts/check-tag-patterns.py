#!/usr/bin/env python3
"""Deployment-tag patterns agree between the release workflow and its docs.

The release-metadata workflow (.github/workflows/terraform-apply.yml) runs on
the tags in its on.push.tags list. Three documents must protect and admit
exactly those tags (re-audit 5 CICD-4): the deployment-tag ruleset and the
tfc-readonly environment row in docs/guides/CI_SECRETS.md, and the tag
ruleset in docs/guides/BRANCH_PROTECTION.md. GitHub's `*` does not cross
`/`, so a broader-looking pattern such as `gcp-*/v*` does not cover
`gcp-workload/<env>/v*`: the lists must match one for one. Both rulesets must
also restrict creation, update and deletion of the tags, name bypass actors
(else nobody can create a release tag), and be valid JSON.

    python3 scripts/check-tag-patterns.py [ROOT]   (make consistency)

Exit 0 when they agree, 1 otherwise.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/terraform-apply.yml"
CI_SECRETS = ROOT / "docs/guides/CI_SECRETS.md"
BRANCH_PROTECTION = ROOT / "docs/guides/BRANCH_PROTECTION.md"
REQUIRED_RULES = {"creation", "update", "deletion"}


def workflow_tags() -> list[str]:
    text = WORKFLOW.read_text()
    m = re.search(r"^on:\n  push:\n    tags:\n((?:      - \"[^\"]+\"\n)+)", text, re.M)
    if not m:
        sys.exit(f"check-tag-patterns: no on.push.tags list in {WORKFLOW}")
    return re.findall(r'"([^"]+)"', m.group(1))


def ruleset(text: str, where: str) -> dict:
    """The one tag ruleset in a document: the JSON body of its
    `gh api ... rulesets --input - <<'JSON'` heredoc."""
    bodies = re.findall(r"rulesets\" --input - <<'JSON'\n(.*?)\nJSON\n|rulesets --input - <<'JSON'\n(.*?)\nJSON\n", text, re.S)
    bodies = [a or b for a, b in bodies]
    if len(bodies) != 1:
        sys.exit(f"check-tag-patterns: expected one ruleset heredoc in {where}, found {len(bodies)}")
    try:
        return json.loads(bodies[0])
    except json.JSONDecodeError as exc:
        sys.exit(f"check-tag-patterns: the ruleset in {where} is not valid JSON ({exc})")


def main() -> int:
    tags = workflow_tags()
    problems = []
    for path in (CI_SECRETS, BRANCH_PROTECTION):
        text = path.read_text()
        rs = ruleset(text, path.name)
        pats = [p.removeprefix("refs/tags/") for p in rs.get("conditions", {}).get("ref_name", {}).get("include", [])]
        rules = {r.get("type") for r in rs.get("rules", [])}
        if rs.get("target") != "tag" or rs.get("enforcement") != "active":
            problems.append(f"{path.name}: the ruleset must be target tag, enforcement active")
        if rs.get("conditions", {}).get("ref_name", {}).get("exclude", None) != []:
            problems.append(f"{path.name}: the ruleset's exclude must be [] (an exclude carves "
                            "deployment tags out of the protection)")
        if not rs.get("bypass_actors"):
            problems.append(f"{path.name}: the ruleset has no bypass_actors, so its creation rule "
                            "would block every release tag, admins included")
        if sorted(pats) != sorted(tags):
            problems.append(f"{path.name}: ruleset patterns {sorted(pats)} differ from "
                            f"terraform-apply.yml on.push.tags {sorted(tags)}")
        if not REQUIRED_RULES <= rules:
            problems.append(f"{path.name}: tag ruleset lacks {sorted(REQUIRED_RULES - rules)}; "
                            "without creation a writer can still create a deployment tag")
    row = re.search(r"^\| `tfc-readonly` \|[^|]*\| tags ([^|]+)\|", CI_SECRETS.read_text(), re.M)
    if not row:
        problems.append("CI_SECRETS.md: no tfc-readonly environment row")
    elif sorted(re.findall(r"`([^`]+)`", row.group(1))) != sorted(tags):
        problems.append("CI_SECRETS.md: the tfc-readonly tag policy differs from "
                        "terraform-apply.yml on.push.tags")
    for p in problems:
        print(f"  ERROR {p}", file=sys.stderr)
    print(f"check-tag-patterns: {len(tags)} workflow tag patterns, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
