#!/usr/bin/env bash
# GCP region and zone regexes must accept multi-digit regions (europe-west10,
# europe-west12, ...). Fails on a letter class followed by a single digit class
# and then `-` or the end anchor, i.e. `[a-z]+[0-9]-` or `[a-z]+[0-9]$`; use
# `[a-z]+[0-9]+`. AWS region patterns (`-[1-9][0-9]?$`) and time-of-day
# patterns (`[0-5][0-9]$`) have no letter class before the digit and are not
# matched. Run by scripts/check-consistency.sh (make consistency).
#
#   scripts/check-gcp-region-regex.sh [path ...]
#   (default: modules envs config scripts templates examples tests)
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ "$#" -eq 0 ]; then
  set -- modules envs config scripts templates examples tests
fi

hits="$(grep -rnE '\[a-z\]\+\[0-9\](-|\$)' \
  --include='*.tf' --include='*.hcl' --include='*.json' --include='*.yaml' --include='*.yml' \
  --include='*.sh' --include='*.py' \
  --exclude-dir=.terraform \
  "$@" 2>/dev/null \
  | grep -vE '^(\./)?scripts/(check-gcp-region-regex\.sh|tests/test-check-gcp-region-regex\.sh):' || true)"

if [ -n "${hits}" ]; then
  while IFS= read -r h; do
    echo "  FAIL single-digit GCP region/zone regex (use [a-z]+[0-9]+): ${h}" >&2
  done <<<"${hits}"
  exit 1
fi
echo "check-gcp-region-regex: OK"
