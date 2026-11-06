#!/usr/bin/env bash
# Consistency guards — assert canonical strings that are hand-propagated across
# many files (and have drifted before, e.g. the AWS region regex). Cheap grep
# checks that fail CI when a copy diverges. Add new invariants here.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
note() { echo "  - $1"; fail=1; }

echo "==> AWS region regex is canonical (single form, no single-digit-ordinal drift)"
# Canonical: ^[a-z]{2}-[a-z]+-[1-9][0-9]?$  ·  Rejected: the older ...-[0-9]$ form.
drift=$(grep -rln 'a-z]{2}-\[a-z\]+-\[0-9\]\$' --include='*.tf' modules envs 2>/dev/null)
[ -z "$drift" ] || { echo "$drift" | while read -r f; do note "region regex drift (use [1-9][0-9]?\$): $f"; done; fail=1; }

echo "==> AWS provider pin is the canonical floored pin in every AWS versions.tf"
badaws=$(grep -rl 'source *= *"hashicorp/aws"' --include='versions.tf' --exclude-dir='.terraform' modules/aws envs/aws 2>/dev/null \
  | while read -r f; do grep -q '">= 6.46.0, < 7.0.0"' "$f" || echo "$f"; done)
[ -z "$badaws" ] || { echo "$badaws" | while read -r f; do note "AWS pin not '>= 6.46.0, < 7.0.0': $f"; done; fail=1; }

echo "==> GCP google provider pin is the canonical range in every GCP versions.tf"
# Canonical: "~> 7.0" (6->7 migration complete; locks on 7.x, audit L4).
badgcp=$(grep -rl 'hashicorp/google' --include='versions.tf' --exclude-dir='.terraform' modules/gcp envs/gcp 2>/dev/null \
  | while read -r f; do grep -q '"~> 7.0"' "$f" || echo "$f"; done)
[ -z "$badgcp" ] || { echo "$badgcp" | while read -r f; do note "google pin not '~> 7.0': $f"; done; fail=1; }

echo "==> Every examples/presets/*.tfvars key is a variable of its target root"
# Naming: <prod|nonprod>-<cloud>-<root>.tfvars  ->  envs/<cloud>/<root>/variables.tf
for preset in examples/presets/*.tfvars; do
  [ -e "$preset" ] || continue
  base=$(basename "$preset" .tfvars)
  rest=${base#*-}            # drop prod-/nonprod-
  cloud=${rest%%-*}
  root=${rest#*-}
  vars="envs/$cloud/$root/variables.tf"
  if [ ! -f "$vars" ]; then
    note "preset $preset targets missing root envs/$cloud/$root"
    continue
  fi
  # Active (uncommented) and commented-out assignments must both name real variables.
  for key in $(sed -nE 's/^#?[[:space:]]*([a-z][a-z0-9_]*)[[:space:]]+=.*/\1/p' "$preset"); do
    grep -q "variable \"$key\"" "$vars" || note "preset $preset sets unknown variable '$key' (not in $vars)"
  done
done

echo "==> Every preset referenced in the docs exists"
for ref in $(grep -rhoE 'presets/[a-z0-9-]+\.tfvars' --include='*.md' --include='*.tf' --exclude-dir='.terraform' --exclude-dir='audit' . 2>/dev/null | sort -u); do
  [ -f "examples/$ref" ] || note "docs reference missing preset examples/$ref"
done

echo "==> Every aws provider block in envs/aws/*/providers.tf sets default_tags"
# FinOps/governance: the canonical tag set (CostCenter/Environment/Owner/...) is
# written via provider default_tags, so every aws provider block (default AND
# aliased) must carry one. Counts provider "aws" blocks vs default_tags blocks.
for pf in envs/aws/*/providers.tf; do
  [ -e "$pf" ] || continue
  nprov=$(grep -cE '^provider "aws"' "$pf" || true)
  ntags=$(grep -cE '^[[:space:]]*default_tags[[:space:]]*\{' "$pf" || true)
  if [ "$nprov" -eq 0 ] || [ "$ntags" -lt "$nprov" ]; then
    note "$pf: $nprov aws provider block(s) but $ntags default_tags block(s)"
  fi
done

echo "==> Every google/google-beta provider block in envs/gcp/*/providers.tf sets default_labels"
# The GCP twin of the default_tags check: the canonical label set (managed-by,
# landing-zone, workspace, environment) is written via provider default_labels.
for pf in envs/gcp/*/providers.tf; do
  [ -e "$pf" ] || continue
  nprov=$(grep -cE '^provider "google(-beta)?"' "$pf" || true)
  nlabels=$(grep -cE '^[[:space:]]*default_labels[[:space:]]*=' "$pf" || true)
  if [ "$nprov" -eq 0 ] || [ "$nlabels" -lt "$nprov" ]; then
    note "$pf: $nprov google provider block(s) but $nlabels default_labels attribute(s)"
  fi
done

echo "==> Multi-platform lockfiles (INFORMATIONAL — reported, never fails yet)"
# A lockfile written by a plain local `terraform init` carries one h1: hash per
# provider (the host platform). The canonical command writes one per platform:
#   terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
# A provider block with fewer than 3 h1: hashes marks the file single-platform.
# TODO: make this fatal once the repo-wide lock sweep lands.
nlocks=0
nsingle=0
while IFS= read -r lf; do
  nlocks=$((nlocks + 1))
  if awk '/^provider /{ if (inblk && h < 3) bad=1; inblk=1; h=0 } /"h1:/{ h++ } END { if (inblk && h < 3) bad=1; exit bad ? 0 : 1 }' "$lf"; then
    nsingle=$((nsingle + 1))
    [ -z "${LOCK_VERBOSE:-}" ] || echo "  single-platform: $lf"
  fi
done < <(git ls-files '*.terraform.lock.hcl' 2>/dev/null)
echo "  ${nsingle}/${nlocks} committed lockfiles lack the linux_amd64/darwin_arm64/darwin_amd64 h1: hashes (LOCK_VERBOSE=1 lists them)"

if [ "$fail" -eq 0 ]; then
  echo "OK: all consistency invariants hold."
else
  echo "CONSISTENCY CHECK FAILED — reconcile the drifted copies above." >&2
fi
exit "$fail"
