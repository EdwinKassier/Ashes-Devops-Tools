#!/usr/bin/env bash
# Fail when a root reads a config key (local.lz.<dotted.path> in envs/**/config.tf)
# that config/landing-zone.schema.json does not define, so the schema cannot
# silently lag the roots.
#
#   scripts/check-config-schema-coverage.sh [SCHEMA] [ENVS_DIR]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="${1:-${REPO_ROOT}/config/landing-zone.schema.json}"
ENVS_DIR="${2:-${REPO_ROOT}/envs}"

paths="$(find "${ENVS_DIR}" -name config.tf -not -path '*/.terraform/*' -print0 |
  xargs -0 grep -ohE 'local\.lz\.[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*' | sed 's/^local\.lz\.//' | sort -u)"

if [[ -z "${paths}" ]]; then
  echo "check-config-schema-coverage: no local.lz.* reads found under ${ENVS_DIR}" >&2
  exit 1
fi

printf '%s\n' "${paths}" | python3 -I -c '
import json, sys
schema = json.load(open(sys.argv[1]))
missing = []
for path in sys.stdin.read().split():
    node = schema
    for seg in path.split("."):
        props = node.get("properties", {})
        if seg in props:
            node = props[seg]
            continue
        ap = node.get("additionalProperties")
        if isinstance(ap, dict):
            node = ap
            continue
        if node.get("type") == "object" and ap is None and not props:
            break  # free-form object: any deeper key is allowed
        missing.append(path)
        break
if missing:
    print("Config keys read by envs/**/config.tf but absent from the schema:", file=sys.stderr)
    for m in missing:
        print("  local.lz." + m, file=sys.stderr)
    sys.exit(1)
print("check-config-schema-coverage: all local.lz.* reads resolve in the schema")
' "${SCHEMA}"
