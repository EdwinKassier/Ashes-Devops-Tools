#!/usr/bin/env bash
# Consistency guards — assert canonical strings that are hand-propagated across
# many files (and have drifted before, e.g. the AWS region regex). Cheap grep
# checks that fail CI when a copy diverges. Add new invariants here.
# -e: an unexpected command failure stops the script (non-zero exit) instead of
# being ignored. A grep whose "no match" status is expected ends in `|| true`.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
note() { echo "  - $1"; fail=1; }

echo "==> AWS region and ARN partition regexes are canonical (one form each)"
# Region canonical: ^([a-z]{2}|us-gov|eusc-[a-z]{2})-[a-z]+-[1-9][0-9]?$
#   commercial and China names keep the old two-letter form; GovCloud (us-gov-*)
#   and the European Sovereign Cloud (eusc-<cc>-*) are named explicitly.
# Partition canonical (strict ARN checks): arn:aws(-us-gov|-cn|-eusc)?:
# Every .tf or script regex that starts with a two-letter region prefix must be
# the canonical one; the older forms (...-[0-9]$, (-[a-z]+)+, the pre-sovereign
# two-letter-only form) and the pre-sovereign partition list are drift.
# templates/ is not scanned: templates/aws/root keeps the commercial-only form
# (known-gaps, "GovCloud and the AWS European Sovereign Cloud").
region_canon='^([a-z]{2}|us-gov|eusc-[a-z]{2})-[a-z]+-[1-9][0-9]?$'
drift=$(grep -rnoE --include='*.tf' --include='*.sh' --exclude-dir='.terraform' \
  '\^(\(\[a-z\]\{2\}[^$]*|\[a-z\]\{2\}[^$]*)\$' modules envs scripts 2>/dev/null \
  | grep -vF -- "${region_canon}" | grep -v '^scripts/check-consistency.sh:' || true)
[ -z "$drift" ] || { echo "$drift" | while read -r f; do note "region regex drift (use ${region_canon}): $f"; done; fail=1; }
pdrift=$(grep -rnF --include='*.tf' --exclude-dir='.terraform' 'aws(-us-gov|-cn)?' modules envs templates 2>/dev/null || true)
[ -z "$pdrift" ] || { echo "$pdrift" | while read -r f; do note "ARN partition drift (use aws(-us-gov|-cn|-eusc)?): $f"; done; fail=1; }

echo "==> Audit-retention framework floors are identical in every root that reads compliance.frameworks"
# Each such config.tf holds one retention_floor_days line; all copies must match.
floors="$(grep -rhoE 'retention_floor_days *= *\{[^}]*\}' --include='config.tf' --exclude-dir='.terraform' envs 2>/dev/null | sed 's/  */ /g' | sort -u || true)"
[ "$(printf '%s\n' "$floors" | grep -c . || true)" -le 1 ] || note "retention_floor_days drift: $(printf '%s' "$floors" | tr '\n' '|')"
nofloor=$(grep -rl 'local\.lz\.compliance\.frameworks' --include='config.tf' --exclude-dir='.terraform' envs 2>/dev/null \
  | while read -r f; do grep -q 'retention_floor_days *=' "$f" || echo "$f"; done || true)
[ -z "$nofloor" ] || { echo "$nofloor" | while read -r f; do note "reads compliance.frameworks without retention_floor_days: $f"; done; fail=1; }

echo "==> AWS provider pin is the canonical floored pin in every AWS versions.tf"
badaws=$(grep -rl 'source *= *"hashicorp/aws"' --include='versions.tf' --exclude-dir='.terraform' modules/aws envs/aws 2>/dev/null \
  | while read -r f; do grep -q '">= 6.46.0, < 7.0.0"' "$f" || echo "$f"; done)
[ -z "$badaws" ] || { echo "$badaws" | while read -r f; do note "AWS pin not '>= 6.46.0, < 7.0.0': $f"; done; fail=1; }

echo "==> GCP google provider pin is the canonical range wherever google/google-beta is required"
# Canonical: "~> 8.0" (7->8 migration complete; locks on 8.x). Checked per
# provider entry (google and google-beta each need it, so one correct pin in a
# file cannot hide a stale one), across modules, roots, examples, templates and
# the e2e tests.
badgcp=$(grep -rlE 'source *= *"hashicorp/google(-beta)?"' --include='*.tf' --exclude-dir='.terraform' \
  modules envs examples templates tests 2>/dev/null \
  | while read -r f; do
      awk -v f="$f" '
        /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*\{/ { inblk = 1; buf = "" }
        inblk { buf = buf $0 "\n" }
        inblk && /\}/ {
          if (buf ~ /"hashicorp\/google(-beta)?"/) {
            src = buf; sub(/.*"hashicorp\//, "", src); sub(/".*/, "", src)
            if (buf !~ /version[[:space:]]*=[[:space:]]*"~> 8\.0"/) print f " (" src ")"
          }
          inblk = 0
        }' "$f"
    done)
[ -z "$badgcp" ] || { echo "$badgcp" | while read -r f; do note "google pin not '~> 8.0': $f"; done; fail=1; }

echo "==> Terraform required_version is the canonical range in every versions.tf"
# Canonical: ">= 1.17, < 2.0" (mock_ephemeral, deprecated attributes, typed outputs).
badtf=$(find modules envs examples templates tests -name versions.tf -not -path '*/.terraform/*' 2>/dev/null \
  | while read -r f; do grep -q 'required_version = ">= 1.17, < 2.0"' "$f" || echo "$f"; done)
[ -z "$badtf" ] || { echo "$badtf" | while read -r f; do note "required_version not '>= 1.17, < 2.0': $f"; done; fail=1; }

echo "==> Terraform CLI pin agrees across .tool-versions, .terraform-version and CI"
tv=$(awk '$1 == "terraform" {print $2; exit}' .tool-versions 2>/dev/null)
case "$tv" in 1.1[7-9].* | 1.[2-9][0-9].*) ;; *) note ".tool-versions terraform '$tv' is below the 1.17 floor" ;; esac
[ "$(tr -d '[:space:]' <.terraform-version 2>/dev/null)" = "$tv" ] || note ".terraform-version differs from .tool-versions terraform $tv"
for wf in .github/workflows/*.yml; do
  grep -E '^[[:space:]]*TERRAFORM_VERSION:' "$wf" | grep -vq "\"$tv\"" && note "$wf: TERRAFORM_VERSION differs from .tool-versions terraform $tv"
done
# HCP Terraform runs every managed workspace on tfc-admin's terraform_version
# default, so it must be the exact version CI tests.
tfc_tv=$(awk '/^variable "terraform_version"/{inb=1} inb && /default[[:space:]]*=/{gsub(/[" ]/, "", $0); sub(/^default=/, "", $0); print; exit}' envs/tfc-admin/variables.tf 2>/dev/null)
[ "$tfc_tv" = "$tv" ] || note "envs/tfc-admin/variables.tf terraform_version default '$tfc_tv' differs from .tool-versions terraform $tv (TFC would apply with a version CI never tested)"

echo "==> No import blocks in reusable modules (adoption lives in the roots)"
# A module-level import block is inherited by every caller and fails their plan
# once the resource is managed. import blocks belong in an envs/** adoption file.
imports=$(grep -rlE '^[[:space:]]*import[[:space:]]*\{' --include='*.tf' --exclude-dir='.terraform' modules templates 2>/dev/null || true)
[ -z "$imports" ] || { echo "$imports" | while read -r f; do note "import block in a reusable module (move it to the root's adoption file): $f"; done; fail=1; }

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
  # variables. Keys inside a top-level <section>_overrides = { ... } object are
  # checked separately: each direct attribute (active or commented) must be an
  # attribute of that root's <section>_overrides variable.
  for key in $(awk '/^[a-z][a-z0-9_]*_overrides[[:space:]]*=[[:space:]]*\{/{skip=1; next} skip && /^\}/{skip=0; next} !skip' "$preset" \
    | sed -nE 's/^#?[[:space:]]*([a-z][a-z0-9_]*)[[:space:]]+=.*/\1/p'); do
    grep -q "variable \"$key\"" "$vars" || note "preset $preset sets unknown variable '$key' (not in $vars)"
  done
  for obj in $(sed -nE 's/^([a-z][a-z0-9_]*_overrides)[[:space:]]*=[[:space:]]*\{.*/\1/p' "$preset"); do
    attrs=$(awk -v v="variable \"$obj\" {" '$0 == v {inb=1; next} inb && /^\}/ {inb=0} inb' "$vars" \
      | sed -nE 's/^    ([a-z][a-z0-9_]*)[[:space:]]+= optional\(.*/\1/p')
    [ -n "$attrs" ] || { note "preset $preset sets '$obj', which is not an object variable of $vars"; continue; }
    # Direct attributes only: brace depth 1 inside the object; comments keep the depth.
    for key in $(awk -v o="$obj" '
      $0 ~ "^" o "[[:space:]]*=[[:space:]]*\\{" {inb=1; d=1; next}
      inb {
        line=$0; c=line; sub(/^[[:space:]]*#[[:space:]]?/, "", c)
        if (d == 1 && match(c, /^[[:space:]]*[a-z][a-z0-9_]*[[:space:]]+=/)) { k=c; sub(/^[[:space:]]*/, "", k); sub(/[[:space:]]+=.*/, "", k); print k }
        if (line !~ /^[[:space:]]*#/) { n=gsub(/\{/, "{", line); m=gsub(/\}/, "}", line); d += n - m }
        if (d <= 0) inb=0
      }' "$preset"); do
      printf '%s\n' "$attrs" | grep -qx "$key" || note "preset $preset sets unknown key '$obj.$key' (not an attribute of variable \"$obj\" in $vars)"
    done
  done
done

echo "==> Every committed workspace-variable entry is a variable of its workspace's root"
# tfc-admin writes each `workspaces.<ws>.<key>` of a tfc-workspaces YAML file as
# a workspace variable; a Terraform-category key the root does not declare is
# silently ignored by the run. Checked: config/tfc-workspaces.example.yaml, any
# committed config/**/tfc-workspaces.yaml, and every fenced YAML block of
# examples/presets/README.md that starts with `workspaces:`. Workspace => root:
# <cloud>-workload-<env> => envs/<cloud>/workload, saas-<name> => envs/saas,
# tfc-admin => envs/tfc-admin, <cloud>-<layer> => envs/<cloud>/<layer>.
# Format: `workspaces:`, a workspace name at indent 2, a key at indent 4; a long
# form with `category: env` (inline or at indent 6) is an env var and skipped.
ws_root_dir() {
  case "$1" in
    gcp-workload-*) echo envs/gcp/workload ;;
    aws-workload-*) echo envs/aws/workload ;;
    saas-*) echo envs/saas ;;
    tfc-admin) echo envs/tfc-admin ;;
    gcp-* | aws-*) echo "envs/${1%%-*}/${1#*-}" ;;
    *) echo "" ;;
  esac
}
ws_entries() {
  awk '
    function flush() { if (key != "") print ws, key, cat; key = "" }
    /^workspaces:/ { inw = 1; next }
    inw && /^[^[:space:]#]/ { flush(); inw = 0 }
    !inw { next }
    /^  [a-z0-9][a-z0-9-]*:/ { flush(); ws = $1; sub(/:$/, "", ws); next }
    /^    [A-Za-z_][A-Za-z0-9_]*:/ {
      flush(); key = $1; sub(/:$/, "", key)
      cat = ($0 ~ /category:[[:space:]]*"?env"?/) ? "env" : "terraform"; next
    }
    /^      category:[[:space:]]*"?env"?/ { cat = "env" }
    END { flush() }'
}
ws_files=$(find config -name 'tfc-workspaces*.yaml' -not -path '*/tests/*' 2>/dev/null | sort)
ws_blocks=$(awk '/^```yaml$/ { inb = 1; first = 1; next } /^```$/ { inb = 0 } inb && first { keep = ($0 ~ /^workspaces:/); first = 0 } inb && keep' examples/presets/README.md)
[ -n "$ws_blocks" ] || note "examples/presets/README.md has no \`workspaces:\` YAML block (the VCS-driven preset example is missing)"
while read -r src ws key cat; do
  [ -n "$ws" ] && [ "$cat" = terraform ] || continue
  dir=$(ws_root_dir "$ws")
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    note "$src: workspace '$ws' maps to no root under envs/"
    continue
  fi
  grep -qs "variable \"$key\"" "$dir"/*.tf || note "$src: $ws sets '$key', which is not a variable of $dir"
done < <(
  for f in $ws_files; do ws_entries < "$f" | sed "s|^|$f |"; done
  printf '%s\n' "$ws_blocks" | ws_entries | sed 's|^|examples/presets/README.md |'
)

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

echo "==> gcp-projects turns off google provider batching on every google/google-beta provider"
# projects-apply's delegated folderIamAdmin carries one modifiedGrantsByRole
# hasOnly() condition per 10 roles (gcp-organization). Provider IAM batching
# merges the folder IAM changes on one folder into one setIamPolicy call, which
# can span two conditions and is then denied on a real apply (mocks never show it).
pf=envs/gcp/projects/providers.tf
nprov=$(grep -cE '^provider "google(-beta)?"' "$pf" || true)
nbatch=$(grep -cE '^[[:space:]]*enable_batching[[:space:]]*=[[:space:]]*false' "$pf" || true)
if [ "$nprov" -eq 0 ] || [ "$nbatch" -lt "$nprov" ]; then
  note "$pf: $nprov google provider block(s) but $nbatch 'enable_batching = false' setting(s)"
fi

echo "==> GitHub WIF tenant condition is the one canonical string wherever it is rendered or checked"
# Canonical: assertion.repository_owner_id == "<id>" (double quotes, nothing
# appended). custom.wifProviderTenantPinned (stages/organization) compares a
# provider's stored condition to this exact string, so app-services and the
# workload-identity primitive (which gcp-bootstrap calls) must render the same.
wif_canon='"assertion.repository_owner_id == \"<id>\""'
for f in modules/gcp/stages/app-services/main.tf modules/gcp/iam/workload-identity/main.tf modules/gcp/stages/organization/main.tf; do
  forms=$(grep -oE '"assertion\.repository_owner_id == [^$]*\$\{[^}]*\}[^ ,)]*' "$f" 2>/dev/null | sed -E 's/\$\{[^}]*\}/<id>/' | sort -u || true)
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

echo "==> No plan-time code execution, unlisted providers or endpoint overrides (HCL/JSON parse)"
# A plan runs with the workspace's credentials and environment variables (TFE_TOKEN,
# SUPABASE_ACCESS_TOKEN, cloud plan identities), and HCP Terraform runs the OPA
# policy no_plan_time_code_execution only after the plan. This gate enforces the
# same rules on the repository source in the pull request, so a violation cannot
# merge when Validation Summary is a required check (a speculative plan that
# HCP Terraform starts for the same pull request is not stopped). It parses every .tf and
# .tf.json file (python-hcl2, hash-locked in .github/requirements/hcl2.txt) and
# reads its allowlists from policies/opa/no_plan_time_code_execution*.rego. It
# also covers provisioners in removed blocks, which the plan JSON does not show.
# The TFC permission model (runs = read on secret-bearing projects) covers CLI
# uploads that never reach this check.
python3 scripts/check-plan-time-exec.py \
  || note "plan/apply-time code execution or credential redirection (see the errors above; exit 2 = python-hcl2 missing or the policy unreadable)"

echo "==> Non-delegable workload folder roles are identical in bootstrap, organization and projects"
# gcp-bootstrap drops these roles from projects-apply's delegation allow-list,
# gcp-organization grants them to the workload SAs directly, and gcp-projects
# skips them. A role missing from one copy is either delegable (projects-apply
# could grant it to itself) or granted by no stage.
python3 - <<'PY_ROLES' || note "non-delegable workload folder role lists differ between bootstrap, organization and projects"
import re, sys
def roles(path, start):
    s = open(path, encoding="utf-8").read()
    i = s.index("[", s.index(start))
    return sorted(re.findall(r'"(roles/[^"]+)"', s[i:s.index("]", i)]))
a = roles("modules/gcp/stages/bootstrap/service_accounts.tf", "non_delegable_folder_roles = [")
b = roles("modules/gcp/stages/organization/variables.tf", 'variable "non_delegable_workload_folder_roles"')
c = roles("modules/gcp/stages/projects/variables.tf", 'variable "non_delegable_workload_folder_roles"')
sys.exit(0 if a and a == b == c else 1)
PY_ROLES

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

echo "==> tfc-admin root_trigger_dirs lists exactly the modules each root composes"
# envs/tfc-admin/main.tf local.root_trigger_dirs scopes each workspace's VCS
# trigger patterns to the module trees its root composes. Recompute the
# transitive closure of every root's local `source = "../..."` references and
# compare: a missing module would not trigger the plan that tests its change;
# a stale one queues needless plans. Entries outside modules/ (files a root
# reads, e.g. examples/presets) are allowed as long as the directory exists.
repo_root=$(pwd -P)
module_closure() {
  local queue=("$1") seen="" d rel abs
  while [ "${#queue[@]}" -gt 0 ]; do
    d=${queue[0]}
    queue=("${queue[@]:1}")
    for rel in $(cat "$d"/*.tf 2>/dev/null | sed -nE 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*"(\.\.?\/[^"]*)".*/\1/p'); do
      abs=$(cd "$d/$rel" 2>/dev/null && pwd -P) || { note "$d: module source $rel does not resolve"; continue; }
      abs=${abs#"$repo_root"/}
      case " $seen " in *" $abs "*) ;; *) seen="$seen $abs"; queue+=("$abs") ;; esac
    done
  done
  printf '%s\n' $seen | sed '/^$/d' | sort
}
trigger_map=$(awk '
  /^  root_trigger_dirs = \{/ { inb = 1; next }
  inb && /^  \}/ { inb = 0 }
  inb && match($0, /^    "[^"]+" = \[/) { k = $0; sub(/^    "/, "", k); sub(/".*/, "", k); next }
  inb && match($0, /^      "[^"]+",?/) { v = $0; sub(/^      "/, "", v); sub(/".*/, "", v); print k, v }
' envs/tfc-admin/main.tf)
[ -n "$trigger_map" ] || note "envs/tfc-admin/main.tf: local.root_trigger_dirs not found or empty"
for dir in $(sed -nE 's/(^|.*[^a-z_])dir[[:space:]]*=[[:space:]]*"(envs\/[^"]+)".*/\2/p' envs/tfc-admin/main.tf | sort -u); do
  printf '%s\n' "$trigger_map" | awk -v d="$dir" '$1 == d { f = 1 } END { exit f ? 0 : 1 }' \
    || { note "envs/tfc-admin/main.tf: catalog root $dir has no root_trigger_dirs entry"; continue; }
  listed=$(printf '%s\n' "$trigger_map" | awk -v d="$dir" '$1 == d && $2 ~ /^modules\// { print $2 }' | sort)
  actual=$(module_closure "$dir")
  for m in $(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$actual")); do
    note "root_trigger_dirs[\"$dir\"] is missing $m (composed by the root, so a change to it must queue the plan)"
  done
  for m in $(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$actual")); do
    note "root_trigger_dirs[\"$dir\"] lists $m, which the root does not compose (remove it)"
  done
done
for extra in $(printf '%s\n' "$trigger_map" | awk '$2 !~ /^modules\// { print $2 }' | sort -u); do
  [ -d "$extra" ] || note "root_trigger_dirs lists $extra, which is not a directory"
done

echo "==> Allowlists of any-typed inputs match their stage types (scripts/check-any-allowlists.py)"
# Each `type = any` input's key allowlist (<owner>/allowed_keys.tf) must equal the
# attributes of the stage object it is forwarded to (scripts/any-allowlists.json).
python3 -I scripts/check-any-allowlists.py >/dev/null || note "an any-typed input's allowlist drifted from its stage type (see the errors above)"

echo "==> Example tfvars set no identity or placement inputs (scripts/check-example-tfvars.sh)"
./scripts/check-example-tfvars.sh >/dev/null || note "examples/*.tfvars.example sets an input config/landing-zone.yaml owns"

echo "==> Compliance matrices cite existing paths and unique IDs (scripts/check-matrix-paths.sh)"
./scripts/check-matrix-paths.sh || note "docs/compliance matrices cite a missing path or repeat a control ID"

echo "==> Production is decided by is_production only (scripts/check-production-rule.sh)"
./scripts/check-production-rule.sh >/dev/null || note "a root decides production from an environment name"

echo "==> check-jsonschema pin agrees across CI, setup.sh and pre-commit"
cj_ci="$(grep -oE 'check-jsonschema==[0-9.]+' .github/workflows/terraform-plan.yml | head -1 | cut -d= -f3)"
cj_pc="$(awk '/check-jsonschema$/{f=1} f && /rev:/{print $2; exit}' .pre-commit-config.yaml)"
[ -n "$cj_ci" ] || note ".github/workflows/terraform-plan.yml: no check-jsonschema==<version> pin found"
grep -q 'check-jsonschema' scripts/setup.sh || note "scripts/setup.sh does not install check-jsonschema"
[ -z "$cj_pc" ] || [ "$cj_pc" = "$cj_ci" ] || note "check-jsonschema: CI ${cj_ci}, pre-commit ${cj_pc}"

echo "==> Deletion protection has one input name: enable_<thing>_deletion_protection"
dp="$(grep -rnE --include='variables.tf' '^variable "(deletion_protection|delete_protection|[a-z_]+_enable_deletion_protection)"' envs modules | grep -v '/\.terraform/' || true)"
dp_new="$(printf '%s\n' "${dp}" | while IFS=: read -r f n _; do
  [[ -z "${f}" ]] || sed -n "${n},/^}/p" "${f}" | grep -q 'deprecated *=' || printf '%s\n' "${f}:${n}"
done || true)"
[[ -z "${dp_new}" ]] || note "deletion-protection input without the enable_ prefix and no deprecated marker: ${dp_new}"

echo "==> An example's provider constraints equal its module's"
# provider_pin <versions.tf> <name>: the version string of required_providers.<name>.
provider_pin() {
  awk -v p="$2" '
    $0 ~ "^[[:space:]]*" p "[[:space:]]*=[[:space:]]*\\{" { inblk = 1; next }
    inblk && /version[[:space:]]*=/ { sub(/.*version[[:space:]]*=[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
    inblk && /}/ { inblk = 0 }
  ' "$1" 2>/dev/null
}
while IFS= read -r ex; do
  mod="${ex%%/examples/*}"
  [[ -f "${mod}/versions.tf" ]] || continue
  for p in archive random null tls time; do
    m="$(provider_pin "${mod}/versions.tf" "$p")"
    e="$(provider_pin "${ex}/versions.tf" "$p")"
    [[ -z "$m" || -z "$e" || "$m" == "$e" ]] || note "${ex}/versions.tf ${p} \"${e}\" differs from ${mod}/versions.tf \"${m}\""
  done
done < <(find modules -path '*/examples/*' -name versions.tf ! -path '*/.terraform/*' -exec dirname {} \; | sort)

echo "==> Every workflow job that holds a secret or an OIDC token blocks egress"
./scripts/check-github-governance.sh || note "a credential-holding job is not harden-runner egress-policy: block (see above)"

if [ "$fail" -eq 0 ]; then
  echo "OK: all consistency invariants hold."
else
  echo "CONSISTENCY CHECK FAILED — reconcile the drifted copies above." >&2
fi
exit "$fail"
