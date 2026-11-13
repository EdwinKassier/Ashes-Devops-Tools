#!/usr/bin/env bash
# Tests for scripts/check-workflow-pipefail.py (a `run:` step with a pipe must
# run under pipefail).
#   bash scripts/tests/test-check-workflow-pipefail.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-workflow-pipefail.py"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# wf <name> <workflow defaults> <job defaults> <step shell> <run line>:
# one workflow, one job, one step. An empty argument leaves that key out.
wf() {
  local d="${workdir}/$1"
  rm -rf "$d"; mkdir -p "$d"
  {
    echo "name: t"
    echo "on: push"
    echo "permissions: {}"
    if [ -n "$2" ]; then
      echo "defaults:"
      echo "  run:"
      echo "    shell: $2"
    fi
    echo "jobs:"
    echo "  j:"
    echo "    runs-on: ubuntu-latest"
    if [ -n "$3" ]; then
      echo "    defaults:"
      echo "      run:"
      echo "        shell: $3"
    fi
    echo "    steps:"
    echo "      - name: Checkout"
    echo "        run: echo first"
    echo "      - name: The step"
    [ -z "$4" ] || echo "        shell: $4"
    echo "        run: |"
    echo "          echo start"
    echo "          $5"
    echo "          echo end"
  } >"${d}/w.yml"
  echo "$d"
}

# run <dir>...: exit status of the guard on those directories
run() { python3 -I "${SCRIPT}" "$@" >"${workdir}/out" 2>&1; }

pipe='./scripts/plan.sh | tee plan.log'

d=$(wf bare '' '' '' "if ! ${pipe}; then exit 1; fi")
if run "$d"; then bad "a pipe under the default shell fails"; else ok "a pipe under the default shell fails"; fi
grep -q 'w.yml: job j, step "The step"' "${workdir}/out" \
  && ok "the failure names the file, job and step" || bad "the failure names the file, job and step: $(cat "${workdir}/out")"

d=$(wf wf-bash bash '' '' "${pipe}")
if run "$d"; then ok "workflow defaults shell: bash passes"; else bad "workflow defaults shell: bash passes"; fi

d=$(wf job-bash '' bash '' "${pipe}")
if run "$d"; then ok "job defaults shell: bash passes"; else bad "job defaults shell: bash passes"; fi

d=$(wf step-bash '' '' bash "${pipe}")
if run "$d"; then ok "step shell: bash passes"; else bad "step shell: bash passes"; fi

d=$(wf step-custom '' '' 'bash -e {0}' "${pipe}")
if run "$d"; then bad "a custom 'bash -e {0}' shell (no pipefail) fails"; else ok "a custom 'bash -e {0}' shell (no pipefail) fails"; fi

d=$(wf step-custom-pf '' '' 'bash -eo pipefail {0}' "${pipe}")
if run "$d"; then ok "a custom shell with pipefail passes"; else bad "a custom shell with pipefail passes"; fi

d=$(wf wf-sh sh '' '' "${pipe}")
if run "$d"; then bad "workflow defaults shell: sh fails"; else ok "workflow defaults shell: sh fails"; fi

d=$(wf step-override sh '' bash "${pipe}")
if run "$d"; then ok "a step shell: bash overrides a workflow sh default"; else bad "a step shell: bash overrides a workflow sh default"; fi

d=$(wf set-pipefail '' '' '' "set -euo pipefail; ${pipe}")
if run "$d"; then ok "a script that sets pipefail passes"; else bad "a script that sets pipefail passes"; fi

d=$(wf or-only '' '' '' 'make test || exit 1')
if run "$d"; then ok "|| alone is not a pipe"; else bad "|| alone is not a pipe"; fi

d=$(wf comment-only '' '' '' '# a | b in a comment')
if run "$d"; then ok "a pipe in a comment line does not count"; else bad "a pipe in a comment line does not count"; fi

d=$(wf quoted-only '' '' '' "jq -r '.data[] | .id' file.json")
if run "$d"; then ok "a pipe inside single quotes does not count"; else bad "a pipe inside single quotes does not count"; fi

d=$(wf dquoted-only '' '' '' 'echo "| Check | ${RESULT} |" >> summary.md')
if run "$d"; then ok "a pipe inside double quotes does not count"; else bad "a pipe inside double quotes does not count"; fi

d=$(wf python '' '' python 'print("a | b")')
if run "$d"; then ok "a non-POSIX shell (python) is skipped"; else bad "a non-POSIX shell (python) is skipped"; fi

d=$(wf inline-run '' '' '' 'echo')
sed -i.bak 's/^        run: |$/        run: echo a | tee b/' "${d}/w.yml" && rm -f "${d}/w.yml.bak"
if run "$d"; then bad "an inline (single-line) run with a pipe fails"; else ok "an inline (single-line) run with a pipe fails"; fi

mkdir -p "${workdir}/empty"
if run "${workdir}/empty"; then bad "an empty directory fails"; else ok "an empty directory fails"; fi

if (cd "${REPO_ROOT}" && run); then ok "the repository workflows and app-delivery examples pass"; else bad "the repository workflows and app-delivery examples pass: $(cat "${workdir}/out")"; fi

printf 'test-check-workflow-pipefail: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
