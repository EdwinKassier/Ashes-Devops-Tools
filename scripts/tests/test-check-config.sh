#!/usr/bin/env bash
# Tests for scripts/check-config.sh: the fork's real config/landing-zone.yaml is validated.
#   bash scripts/tests/test-check-config.sh   (make test-scripts; needs check-jsonschema)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-config.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }
command -v check-jsonschema >/dev/null || { echo "check-jsonschema not found (make install)" >&2; exit 1; }

mkdir -p "${workdir}/config"
cp "${REPO_ROOT}/config/landing-zone.schema.json" "${REPO_ROOT}/config/landing-zone.example.yaml" "${workdir}/config/"

# A typo in the real file must fail and name the file.
python3 -I -c '
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
assert "is_production: false" in text
open(dst, "w").write(text.replace("is_production: false", "is_prodution: false", 1))
' "${REPO_ROOT}/config/landing-zone.example.yaml" "${workdir}/config/landing-zone.yaml"
if out="$(bash "${SCRIPT}" "${workdir}" 2>&1)"; then bad "typo in config/landing-zone.yaml fails"; else ok "typo in config/landing-zone.yaml fails"; fi
if grep -q 'landing-zone.yaml' <<<"${out}"; then ok "file is named"; else bad "file is named"; fi

cp "${REPO_ROOT}/config/landing-zone.example.yaml" "${workdir}/config/landing-zone.yaml"
if bash "${SCRIPT}" "${workdir}" >/dev/null 2>&1; then ok "valid real file passes"; else bad "valid real file passes"; fi

rm "${workdir}/config/landing-zone.yaml"
if out="$(bash "${SCRIPT}" "${workdir}" 2>&1)"; then ok "absent real file is fine"; else bad "absent real file is fine"; fi
if grep -q 'config/landing-zone.yaml not present' <<<"${out}"; then ok "absence is stated"; else bad "absence is stated"; fi

printf 'test-check-config: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
