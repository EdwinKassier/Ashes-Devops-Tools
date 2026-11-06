#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"

cd "$(dirname "$0")/.."

collect_modules() {
  # maxdepth 5 covers the cloud-grouped structure
  # (modules/<cloud>/<category>/<name>/main.tf = depth 4, e.g. modules/gcp/network/vpc,
  # modules/aws/stages/organization) plus a submodule level
  # (modules/<cloud>/<category>/<name>/<submodule>/main.tf = depth 5).
  # Without enough depth, any nested module would be silently excluded from CI validate,
  # lint, and docs generation.
  find modules -mindepth 1 -maxdepth 5 -type f -name main.tf \
    ! -path '*/.terraform/*' ! -path '*/examples/*' | sed 's#/main.tf##' | sort -u
}

collect_envs() {
  # Env roots are grouped by cloud: envs/<cloud>/<root> (depth 2), plus the flat
  # envs/saas leaf root (depth 1). maxdepth 2 covers both; the .tf check excludes
  # the grouping dirs (envs/gcp, envs/aws hold no .tf) and any .tfvars-only dirs.
  find envs -mindepth 1 -maxdepth 2 -type d ! -name '.terraform' | while read -r dir; do
    if find "$dir" -maxdepth 1 -name '*.tf' | grep -q .; then
      echo "$dir"
    fi
  done | sort
}

# Examples are only included when they have a versions.tf (self-contained).
# Searches both the top-level examples/ directory and examples/ subdirectories
# inside any module (HashiCorp module convention: modules/<name>/examples/<example>/).
collect_examples() {
  {
    find examples -mindepth 1 -maxdepth 2 -type f -name versions.tf \
      ! -path '*/.terraform/*' | sed 's#/versions.tf##'
    find modules -mindepth 3 -maxdepth 6 -type f -name versions.tf \
      -path '*/examples/*' ! -path '*/.terraform/*' | sed 's#/versions.tf##'
  } | sort -u
}

# Opt-in real-apply e2e roots (tests/e2e/<cloud>). Their *.tftest.hcl suites
# need real credentials and run only in sandbox-e2e.yml, but the roots
# themselves must still `terraform init -backend=false && terraform validate`
# cleanly without credentials, so they join the validate discovery set.
collect_e2e() {
  find tests/e2e -mindepth 2 -maxdepth 2 -type f -name versions.tf \
    ! -path '*/.terraform/*' 2>/dev/null | sed 's#/versions.tf##' | sort -u
}

# Directories holding mock_provider `terraform test` suites (the `make test`
# set): every dir under envs/ or modules/ that contains *.tftest.{hcl,json},
# normalised to the module root (a trailing /tests is stripped). tests/e2e is
# deliberately excluded: those suites do REAL applies (sandbox-e2e.yml).
collect_test_dirs() {
  find envs modules -type f \( -name '*.tftest.hcl' -o -name '*.tftest.json' \) \
    ! -path '*/.terraform/*' -exec dirname {} \; | sed 's#/tests$##' | sort -u
}

emit_json() {
  local roots=("$@")
  printf '['
  local first=1
  local root
  for root in ${roots[@]+"${roots[@]}"}; do
    if [ $first -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$root"
  done
  printf ']\n'
}

case "$mode" in
  modules)
    collect_modules
    ;;
  envs)
    collect_envs
    ;;
  examples)
    collect_examples
    ;;
  e2e)
    collect_e2e
    ;;
  tests)
    collect_test_dirs
    ;;
  tests-json)
    dirs=()
    while IFS= read -r line; do dirs+=("$line"); done < <(collect_test_dirs)
    emit_json ${dirs[@]+"${dirs[@]}"}
    ;;
  all)
    {
      collect_modules
      collect_envs
      collect_examples
      collect_e2e
    } | sort -u
    ;;
  all-json)
    roots=()
    while IFS= read -r line; do roots+=("$line"); done < <(
      {
        collect_modules
        collect_envs
        collect_examples
        collect_e2e
      } | sort -u
    )
    emit_json ${roots[@]+"${roots[@]}"}
    ;;
  *)
    echo "Usage: $0 [modules|envs|examples|e2e|all|all-json|tests|tests-json]" >&2
    exit 1
    ;;
esac
