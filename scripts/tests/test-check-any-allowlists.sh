#!/usr/bin/env bash
# Tests for scripts/check-any-allowlists.py against a temp tree.
#   bash scripts/tests/test-check-any-allowlists.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-any-allowlists.py"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

t="${workdir}/t"
mkdir -p "${t}/envs/r" "${t}/modules/s" "${t}/scripts"
cat >"${t}/modules/s/variables.tf" <<'HCL'
variable "things" {
  description = "typed"
  type = map(object({
    a   = string
    sub = optional(object({ x = number, y = optional(list(string), ["d"]) }), {})
  }))
}
HCL
write_root() {
  cat >"${t}/envs/r/variables.tf" <<'HCL'
variable "things" {
  # a comment
  type    = any
  default = null

  validation {
    condition     = length([for k in keys(coalesce(var.things, {})) : k if !contains(local.allowed_keys.things.self, k)]) == 0
    error_message = "unknown key"
  }
}
HCL
}
write_manifest() {
  cat >"${t}/scripts/any-allowlists.json" <<JSON
{"allowlists": [
  {"owner": "envs/r", "variable": "things", "path": "self", "stage": "modules/s", "stage_variable": "things"},
  {"owner": "envs/r", "variable": "things", "path": "sub", "stage": "modules/s", "stage_variable": "things"}
], "exempt": [$1]}
JSON
}
write_keys() { printf 'locals {\n  allowed_keys = {\n    things = {\n      self = [%s]\n      sub  = ["x", "y"]%s\n    }\n  }\n}\n' "$1" "${2:-}" >"${t}/envs/r/allowed_keys.tf"; }
check() { python3 -I "${SCRIPT}" "${t}" >"${workdir}/out" 2>&1; }
reset() { write_root; write_manifest ''; write_keys '"a", "sub"'; }

reset
if check; then ok "matching allowlist passes"; else bad "matching allowlist passes"; cat "${workdir}/out" >&2; fi

write_keys '"a", "sub", "typo"'
if check; then bad "allowlist key the stage lacks fails"; else ok "allowlist key the stage lacks fails"; fi
grep -q 'typo' "${workdir}/out" && ok "extra key named" || bad "extra key named"

write_keys '"a"'
if check; then bad "stage attribute missing from allowlist fails"; else ok "stage attribute missing from allowlist fails"; fi
grep -q 'lacks sub' "${workdir}/out" && ok "missing key named" || bad "missing key named"

reset
write_keys '"a", "sub"' $'\n      orphan = ["z"]'
if check; then bad "allowlist path without a manifest row fails"; else ok "allowlist path without a manifest row fails"; fi

reset
printf 'variable "other" {\n  type = any\n}\n' >>"${t}/envs/r/variables.tf"
if check; then bad "uncovered any input fails"; else ok "uncovered any input fails"; fi
grep -q 'variable other' "${workdir}/out" && ok "uncovered input named" || bad "uncovered input named"

write_manifest '{"owner": "envs/r", "variable": "other", "reason": "passed through unchanged"}'
if check; then ok "exempt any input with a reason passes"; else bad "exempt any input with a reason passes"; cat "${workdir}/out" >&2; fi

write_manifest '{"owner": "envs/r", "variable": "other"}'
if check; then bad "exempt row without a reason fails"; else ok "exempt row without a reason fails"; fi

reset
write_manifest '{"owner": "envs/r", "variable": "gone", "reason": "stale"}'
if check; then bad "manifest row for a variable that is not any fails"; else ok "manifest row for a variable that is not any fails"; fi

reset
sed -i.bak 's/local\.allowed_keys\.things\.self/["a", "sub"]/' "${t}/envs/r/variables.tf"
if check; then bad "validation that does not read local.allowed_keys fails"; else ok "validation that does not read local.allowed_keys fails"; fi

reset
if python3 -I "${SCRIPT}" >"${workdir}/out" 2>&1; then ok "repo passes"; else bad "repo passes"; cat "${workdir}/out" >&2; fi
printf 'test-check-any-allowlists: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
