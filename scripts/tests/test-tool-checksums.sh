#!/usr/bin/env bash
# Tests for scripts/tool-checksums.sh with a fake `curl` on PATH (offline).
#   bash scripts/tests/test-tool-checksums.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/tool-checksums.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

mkdir -p "${workdir}/bin"
# The fake curl records its URL (the last argument) and writes fixed bytes to -o.
cat >"${workdir}/bin/curl" <<'F'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 1 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift 2; else shift; fi
done
echo "$1" >>"${FAKE_LOG}"
printf 'fake release asset\n' >"${out}"
F
chmod +x "${workdir}/bin/curl"
printf 'fake release asset\n' >"${workdir}/asset"
if command -v sha256sum >/dev/null 2>&1; then
  want="$(sha256sum <"${workdir}/asset" | awk '{print $1}')"
else
  want="$(shasum -a 256 <"${workdir}/asset" | awk '{print $1}')"
fi

run() {
  : >"${workdir}/log"
  FAKE_LOG="${workdir}/log" PATH="${workdir}/bin:${PATH}" bash "${SCRIPT}" "$@" >"${workdir}/out" 2>&1
}

if run opa 1.22.2; then ok "opa runs"; else bad "opa runs"; fi
grep -qx 'https://github.com/open-policy-agent/opa/releases/download/v1.22.2/opa_linux_amd64_static' "${workdir}/log" \
  && ok "opa downloads the asset CI downloads" || bad "opa downloads the asset CI downloads"
grep -qx "OPA_SHA256: \"${want}\"" "${workdir}/out" && ok "opa prints the digest of the asset" || bad "opa prints the digest of the asset"

if run shellcheck v0.11.0; then ok "shellcheck accepts a v prefix"; else bad "shellcheck accepts a v prefix"; fi
grep -qx 'https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz' "${workdir}/log" \
  && ok "shellcheck downloads the asset CI downloads" || bad "shellcheck downloads the asset CI downloads"
grep -qx "SC_SHA256: \"${want}\"" "${workdir}/out" && ok "shellcheck prints the digest" || bad "shellcheck prints the digest"

if run trivy 0.70.0; then bad "an unknown tool fails"; else ok "an unknown tool fails"; fi
if run opa '1.22.2;rm'; then bad "a malformed version fails"; else ok "a malformed version fails"; fi
if run opa; then bad "a missing version fails"; else ok "a missing version fails"; fi

# Every tool the script knows must match a pinned digest in CI, and the reverse.
wf="${REPO_ROOT}/.github/workflows/terraform-plan.yml"
for env_name in OPA_SHA256 SC_SHA256; do
  grep -q "${env_name}:" "${wf}" && ok "${env_name} is pinned in CI" || bad "${env_name} is pinned in CI"
done

printf 'test-tool-checksums: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
