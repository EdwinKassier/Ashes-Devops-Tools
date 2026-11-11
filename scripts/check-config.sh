#!/usr/bin/env bash
# Validate landing-zone configs against config/landing-zone.schema.json:
#   config/landing-zone.yaml (the fork's real file, when present), the example,
#   config/sandbox/, every test fixture, and tests/fixtures/scaffold. Then check
#   the schema covers every key a root reads, and that the negative fixtures
#   (config/tests/*.yaml and the *-missing-is-production.yaml test fixtures)
#   are rejected.
#
#   scripts/check-config.sh [ROOT]   (make config-check; CI: meta-lint)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${1:-${SCRIPT_DIR}/..}" && pwd)"
SCHEMA="${ROOT}/config/landing-zone.schema.json"
command -v check-jsonschema >/dev/null || { echo "check-jsonschema not found: pipx install check-jsonschema (see .tool-versions)" >&2; exit 1; }
cd "${ROOT}"

files=()
if [[ -f config/landing-zone.yaml ]]; then
  files+=(config/landing-zone.yaml)
else
  echo "config-check: config/landing-zone.yaml not present (a fork's real config is validated when it exists)"
fi
while IFS= read -r f; do files+=("${f}"); done < <(
  {
    [[ -f config/landing-zone.example.yaml ]] && echo config/landing-zone.example.yaml
    find config/sandbox -name 'landing-zone*.yaml' 2>/dev/null || true
    find envs modules -name 'landing-zone*.yaml' -path '*/tests/fixtures/*' ! -name '*-missing-is-production.yaml' ! -path '*/.terraform/*' 2>/dev/null || true
    find tests/fixtures/scaffold -name 'landing-zone*.yaml' 2>/dev/null || true
  } | sort -u
)
check-jsonschema --schemafile "${SCHEMA}" "${files[@]}"

"${SCRIPT_DIR}/check-config-schema-coverage.sh" "${SCHEMA}" "${SCRIPT_DIR}/../envs"

negatives=()
for f in config/tests/*.yaml; do [[ -e "${f}" ]] && negatives+=("${f}"); done
while IFS= read -r f; do negatives+=("${f}"); done < <(
  find envs -name '*-missing-is-production.yaml' -path '*/tests/fixtures/*' ! -path '*/.terraform/*' 2>/dev/null | sort
)
for f in ${negatives[@]+"${negatives[@]}"}; do
  if check-jsonschema --schemafile "${SCHEMA}" "${f}" >/dev/null 2>&1; then
    echo "config-check: ${f} should FAIL schema validation but passed" >&2
    exit 1
  fi
done
echo "config-check: ${#files[@]} files valid; ${#negatives[@]} negative fixtures rejected as expected"
