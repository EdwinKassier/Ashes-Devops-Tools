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

echo "==> OPA lib_helpers.rego copies are byte-identical"
# A VCS policy set loads only its own policies_path, so policies/opa-destructive
# carries a copy of the shared terraform.lib helpers.
cmp -s policies/opa/lib_helpers.rego policies/opa-destructive/lib_helpers.rego \
  || note "policies/opa-destructive/lib_helpers.rego differs from policies/opa/lib_helpers.rego (copy it)"

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
  # Active (uncommented) and commented-out assignments must both name real
  # variables (column 0) or, inside a <section>_overrides = { ... } object (two-
  # space indent), real attributes of an object variable of that root.
  for key in $(sed -nE 's/^(# ?)?([a-z][a-z0-9_]*)[[:space:]]+=.*/\2/p' "$preset"); do
    grep -q "variable \"$key\"" "$vars" || note "preset $preset sets unknown variable '$key' (not in $vars)"
  done
  for key in $(sed -nE 's/^  (# )?([a-z][a-z0-9_]*)[[:space:]]+=.*/\2/p' "$preset"); do
    grep -qE "^    $key[[:space:]]+= optional\(" "$vars" || note "preset $preset sets unknown override key '$key' (not an object attribute in $vars)"
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

echo "==> GitHub WIF tenant condition is the one canonical string wherever it is rendered or checked"
# Canonical: assertion.repository_owner_id == "<id>" (double quotes, nothing
# appended). custom.wifProviderTenantPinned (stages/organization) compares a
# provider's stored condition to this exact string, so app-services and the
# workload-identity primitive (which gcp-bootstrap calls) must render the same.
wif_canon='"assertion.repository_owner_id == \"<id>\""'
for f in modules/gcp/stages/app-services/main.tf modules/gcp/iam/workload-identity/main.tf modules/gcp/stages/organization/main.tf; do
  forms=$(grep -oE '"assertion\.repository_owner_id == [^$]*\$\{[^}]*\}[^ ,)]*' "$f" 2>/dev/null | sed -E 's/\$\{[^}]*\}/<id>/' | sort -u)
  [ -n "$forms" ] || { note "$f: renders no GitHub owner-pin condition"; continue; }
  echo "$forms" | while read -r form; do
    [ "$form" = "$wif_canon" ] || note "$f: GitHub owner-pin condition $form is not $wif_canon"
  done
  [ "$(echo "$forms" | grep -vcxF "$wif_canon")" -eq 0 ] || fail=1
done
sq=$(git grep -nE "repository_owner_id == '" -- 'modules/*.tf' 'envs/*.tf' 2>/dev/null || true)
[ -z "$sq" ] || { echo "$sq" | while read -r l; do note "single-quoted GitHub owner pin (use the canonical double-quoted form): $l"; done; fail=1; }
git grep -q 'repository_owner_id ==' -- modules/gcp/stages/bootstrap/main.tf && note "modules/gcp/stages/bootstrap/main.tf renders its own GitHub condition (it must come from modules/gcp/iam/workload-identity)"

echo "==> No audit provenance codes in Terraform code (CLAUDE.md: they belong in docs/known-gaps.md)"
# Comments and descriptions read as a remediation log when they carry finding
# IDs ("audit C2", "(audit H9, option C)"). Point at docs instead.
prov=$(git grep -niE '\baudit (finding )?([A-Z]{1,2}[0-9]+|round|Modularity|Security|Boilerplate|M-ops)\b|\(G[0-9]+\)|finding #[0-9]+|round-[0-9]+ ' -- '*.tf' '*.hcl' 2>/dev/null || true)
if [ -n "$prov" ]; then
  echo "$prov" | sed 's/^/  /' >&2
  echo "  ERROR: audit/finding provenance codes in Terraform code (see above)" >&2
  fail=1
fi

echo "==> Lockfiles: multi-platform and one version per provider (Renovate owns them)"
# A lockfile written by a plain local `terraform init` carries one h1: hash per
# provider (the host platform). The canonical command writes one per platform:
#   terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
# A provider block with fewer than 3 h1: hashes marks the file single-platform,
# which fails `init -lockfile=readonly` on the other platform. Both that and a
# provider locked at different versions in different lockfiles are fatal.
nlocks=0
nsingle=0
verlist=$(mktemp)
while IFS= read -r lf; do
  nlocks=$((nlocks + 1))
  if awk '/^provider /{ if (inblk && h < 3) bad=1; inblk=1; h=0 } /"h1:/{ h++ } END { if (inblk && h < 3) bad=1; exit bad ? 0 : 1 }' "$lf"; then
    nsingle=$((nsingle + 1))
    echo "  ERROR single-platform lockfile: $lf (terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64)" >&2
    fail=1
  fi
  awk -v f="$lf" '/^provider "/{ gsub(/"/, "", $2); p=$2 } /^  version[[:space:]]*=/{ gsub(/"/, "", $3); print p, $3, f }' "$lf" >> "$verlist"
done < <(git ls-files '*.terraform.lock.hcl' 2>/dev/null)
drift=$(awk '{ print $1, $2 }' "$verlist" | sort -u | awk '{ n[$1]++; s[$1]=s[$1] " " $2 } END { for (p in n) if (n[p] > 1) print p ":" s[p] }' | sort)
if [ -n "$drift" ]; then
  echo "$drift" | while read -r l; do echo "  ERROR provider locked at several versions: $l (LOCK_VERBOSE=1 lists files)" >&2; done
  [ -z "${LOCK_VERBOSE:-}" ] || sort "$verlist" | sed 's/^/  /'
  fail=1
fi
rm -f "$verlist"
echo "  ${nsingle}/${nlocks} committed lockfiles lack the linux_amd64/darwin_arm64/darwin_amd64 h1: hashes"

if [ "$fail" -eq 0 ]; then
  echo "OK: all consistency invariants hold."
else
  echo "CONSISTENCY CHECK FAILED — reconcile the drifted copies above." >&2
fi
exit "$fail"
