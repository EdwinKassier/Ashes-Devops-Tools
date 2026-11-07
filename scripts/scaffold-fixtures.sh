#!/usr/bin/env bash
# Regenerates tests/fixtures/scaffold/landing-zone.<combo>.yaml with the real
# scaffolder (scripts/init-landing-zone.sh), one per supported cloud combination.
#   scripts/scaffold-fixtures.sh          write the fixtures
#   scripts/scaffold-fixtures.sh --check  fail if the committed fixtures differ
# Output is deterministic: LZ_INIT_FIXED_DATE pins the phase-0 expiry and header date.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mode="write"
[[ "${1:-}" == "--check" ]] && mode="check"

DEST="tests/fixtures/scaffold"
OUT="${DEST}"
if [[ "${mode}" == "check" ]]; then
  OUT="$(mktemp -d)"
  trap 'rm -rf "${OUT}"' EXIT
fi
mkdir -p "${OUT}"

for combo in gcp aws saas gcp,aws gcp,aws,saas; do
  name="${combo//,/-}"
  LZ_INIT_FIXED_DATE=2099-01-01 ./scripts/init-landing-zone.sh \
    --non-interactive --yes --force --profile production \
    --clouds "${combo}" --org-name acme-lz --display-name "Acme" \
    --domain acme.example --billing-account 000000-000000-000000 \
    --gcp-admin-email admin@acme.example --aws-management-account 123456789012 \
    --aws-email-pattern 'aws+{key}@acme.example' --github-owner acme \
    --supabase-org sbacmeorg1 --vercel-team team_acme0001 --github-repo acme/web \
    --vcs-repo acme/landing-zone --vcs-github-app-installation-id ghain-AAAA0001 \
    --output "${OUT}/landing-zone.${name}.yaml" >/dev/null
done

if [[ "${mode}" == "check" ]]; then
  if ! diff -ru "${DEST}" "${OUT}"; then
    echo "error: ${DEST} is stale; run 'make scaffold-fixtures' and commit" >&2
    exit 1
  fi
  echo "scaffold fixtures up to date"
fi
