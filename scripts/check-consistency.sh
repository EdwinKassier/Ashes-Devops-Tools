#!/usr/bin/env bash
# Consistency guards — assert canonical strings that are hand-propagated across
# many files (and have drifted before, e.g. the AWS region regex). Cheap grep
# checks that fail CI when a copy diverges. Add new invariants here.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { echo "  - $1"; fail=1; }

echo "==> AWS region regex is canonical (single form, no single-digit-ordinal drift)"
# Canonical: ^[a-z]{2}-[a-z]+-[1-9][0-9]?$  ·  Rejected: the older ...-[0-9]$ form.
drift=$(grep -rln 'a-z]{2}-\[a-z\]+-\[0-9\]\$' --include='*.tf' modules envs 2>/dev/null)
[ -z "$drift" ] || { echo "$drift" | while read -r f; do note "region regex drift (use [1-9][0-9]?\$): $f"; done; fail=1; }

echo "==> AWS provider pin is the canonical floored pin in every AWS versions.tf"
badaws=$(grep -rl 'source *= *"hashicorp/aws"' --include='versions.tf' modules/aws envs/aws 2>/dev/null \
  | while read -r f; do grep -A1 '"hashicorp/aws"' "$f" | grep -q '">= 6.46.0, < 7.0.0"' || echo "$f"; done)
[ -z "$badaws" ] || { echo "$badaws" | while read -r f; do note "AWS pin not '>= 6.46.0, < 7.0.0': $f"; done; fail=1; }

echo "==> GCP google provider pin is the canonical range in every GCP versions.tf"
# Canonical: ">= 6.0, < 8.0" (spans the in-progress 6→7 migration, caps v8).
badgcp=$(grep -rl 'hashicorp/google' --include='versions.tf' modules/gcp envs/gcp 2>/dev/null \
  | while read -r f; do grep -E '"hashicorp/google(-beta)?"' -A1 "$f" | grep 'version' | grep -qv '">= 6.0, < 8.0"' && echo "$f"; done)
[ -z "$badgcp" ] || { echo "$badgcp" | while read -r f; do note "google pin not '>= 6.0, < 8.0': $f"; done; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "OK: all consistency invariants hold."
else
  echo "CONSISTENCY CHECK FAILED — reconcile the drifted copies above." >&2
fi
exit "$fail"
