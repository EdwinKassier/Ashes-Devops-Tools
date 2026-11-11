# WS1 Every claim is true and every documented path works: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or build to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every statement in README, QUICK_START, the runbooks, CHANGELOG, CLAUDE.md and SECURITY.md is true on the day it ships, every command those documents tell an operator to run works as written, and the configuration the roots read cannot silently disagree with itself. Each fix that can drift again gets a check that fails CI when it does.

**Architecture:** Three kinds of change. (1) Documentation corrections, with exact replacement text. (2) Small offline checks under `scripts/` (bash or Python, each with a `scripts/tests/test-*.sh` that proves it fails on a bad input and passes on a good one), wired into `scripts/check-consistency.sh`, `scripts/check-docs-counts.sh`, `make config-check` or `make count-check`, which CI meta-lint already runs. (3) Terraform changes (the production flag, tfc-admin contract preconditions, the AWS layer selector, deletion-protection naming, one module-level `depends_on`) driven by failing `*.tftest.hcl` runs first.

**Tech Stack:** Terraform 1.17.1 (`mock_provider`, `override_data`, `expect_failures`, `deprecated`), HCP Terraform (`tfe` provider in `envs/tfc-admin`), bash, Python 3 (stdlib only), check-jsonschema 0.39.0, terraform-docs 0.19.0, checkov 3.3.17 (via `uvx`), GNU make.

**Conventions for every task**

- `TF=/private/tmp/claude-501/-Users-edwinkassier-Desktop-Ashes-Ashes-Devops-Tools--claude-worktrees-enterprise-devops-audit-949b65/50c7eb6b-1026-4421-925b-256b9cc0fb04/scratchpad/tf/terraform`
- Terraform test command: `make test TEST_DIRS=<dir> TERRAFORM=$TF`.
- Before each commit run the gates the task touches, and always: `make fmt-check consistency count-check links config-check scaffold-fixtures-check test-scripts TERRAFORM=$TF`.
- A renamed input keeps a `deprecated` alias and gets an `UPGRADING.md` entry under "Unreleased" and a `CHANGELOG.md` entry. A commit that removes or changes an input's meaning is `feat!:` or `fix!:` and must touch `UPGRADING.md` (meta-lint enforces this).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not commit as part of planning. Implementers commit once per task.

---

## Findings covered

| Finding | Severity | Verified state (2026-11-11, this worktree) | Task |
|---|---|---|---|
| ADO-1 | Critical | `README.md:7` "Production-grade", `README.md:38` "fully-tested"; `docs/runbooks/production-hardening.md:5` "has never been applied". | 1 |
| ADO-11 | High | `main` at `c08f3c4f`: Terraform Validation, Security Scan and Release all failed (Trivy, Checkov, yamllint, `RELEASE_PLEASE_TOKEN` missing). `CHANGELOG.md:8-15` and `README.md:324,329` describe release-please as working. | 1 |
| ADO-2 | Critical | `examples/dev.tfvars.example:20-31` sets `project_prefix`, `environment`, `region`, `terraform_admin_email`, `tfc_organization`, `organization_workspace_name`. `Makefile:31` makes it the default `APP_VARS`. Docs: `README.md:313`, `docs/guides/QUICK_START.md:290,397,424`. | 2 |
| ADO-3 | Critical | `docs/runbooks/aws-bootstrap.md:255` runs `terraform -chdir=envs/aws/organization apply`. tfc-admin creates `aws-organization` VCS-connected and remote unless `workspace_execution_modes` says `local` (`envs/tfc-admin/variables.tf:120-143`, which already allows `local` for `aws-organization`). | 3 |
| ADO-4 | Critical | `docs/guides/QUICK_START.md:315,317,335,337` list `admin_email`, `organization_admin_groups`, `break_glass_user`, `security_contact_email` as `envs/gcp/organization` variables; they exist only inside `gcp_overrides` (`envs/gcp/organization/variables.tf:121-133`). Only 4 of 15 roots have a README with terraform-docs markers, and `scripts/module-docs.sh` never regenerates them (it reads only `terraform-roots.sh modules`). | 4 |
| IAC-1 | High | Four rules: GCP roots `tobool(try(e.is_production, false))` (6 `config.tf`), tfc-admin `coalesce(..., can(regex("^prod(uction)?$", k)))` (`envs/tfc-admin/config.tf:163-164`), aws-network the same (`envs/aws/network/config.tf:51`), gcp-workload substring `regex("prod", ...)` (`envs/gcp/workload/main.tf:145`). 57 environment entries across 35 shipped YAML files omit the flag. | 5 |
| IAC-2 | High | `Makefile:333-336` validates examples, sandbox and fixtures only. `config/landing-zone.yaml` is never validated. The schema already sets `additionalProperties: false` on both environment objects, so a typo is caught once the file is checked. | 6 |
| ADO-5 | High | `docs/runbooks/aws-bootstrap.md` has no `spoke_attachments` step; `aws-add-account.md:110-124` does. | 7 |
| ADO-6 | High | `docs/runbooks/bootstrap.md:13-24`, `QUICK_START.md:12,55,190,247-250,277-283` omit `gcp-guardrails` and the security team. | 8 |
| ADO-13 | High | No tier or resources-under-management statement in README or QUICK_START. | 9 |
| ADO-14 | Medium | `scripts/init-landing-zone.sh:375,408` rewrite `@my-org.example.com` group emails and subnet names to the operator's domain and prefix; the placeholder report (`:493-512`) then lists nothing for them. | 10 |
| ADO-15 | Medium | `scripts/setup.sh` never installs check-jsonschema; no `ci-quick`; `make ci` omits `scaffold-fixtures-check`, which CI runs. | 11 |
| ADO-16, ADO-19 | Medium | `QUICK_START.md:49-55` omits the aws CLI, `gh`, check-jsonschema; `QUICK_START.md:224-229` omits `TFC_TOKEN_DRIFT`. | 12 |
| ADO-17 | Medium | `envs/tfc-admin/main.tf:251-277` creates all six AWS layer workspaces whenever `enable_aws`. `envs/aws/organization/config.tf:173-182` binds `network`, `shared_services`, `backup` even when those accounts are absent, and `modules/aws/stages/organization/variables.tf:280` then fails the plan. | 13 |
| ADO-18 | Medium | 7 of 8 presets have no YAML twin (`examples/presets/README.md:58-63`), and the README does not show the `config/tfc-workspaces.yaml` route for VCS runs. | 14 |
| ADO-20 | Medium | The example config has 6 foundational + 2 workload accounts; with the management account that is 9 of the default 10. No pre-check. | 15 |
| ADO-21 | Low | `QUICK_START.md:364` and `README.md:154` say HA VPN is not exposed through `network-hub` or config; it is (`envs/gcp/network-hub/variables.tf:106`, `config.tf:41,112`). `docs/architecture/gcp-landing-zone.md:127,174,217` name a non-existent `enable_vpn` input and the wrong stage. | 16 |
| ADO-22 | Low | README library-only table and markers list `gcp/network/app-ingress`, `gcp/monitoring/alert-policy`, `aws/network/vpn` as library-only; `scripts/check-module-usage.py` reports all three wired. | 17 |
| ADO-23 | Low | `README.md:92,97,347`, `docs/INDEX.md:14,90,150,151`, `docs/runbooks/bootstrap.md:13,25`, `docs/architecture/gcp-landing-zone.md:7,60`, `docs/architecture/ARCHITECTURE.md:58`, `QUICK_START.md:55,408` say five (or two) GCP roots; there are six. | 18 |
| ADO-24, ADO-25 | Low | `QUICK_START.md:133` says saas-workload declares `null` (its `versions.tf` declares only supabase and vercel). `CLAUDE.md`, `README.md:302` and `QUICK_START.md:425` list a `make ci` sequence that differs from `Makefile:199-214`. | 19 |
| ADO-26 | Low | Only `plan-gcp-organization` and `plan-gcp-workload` exist. | 20 |
| ADO-27 | Low | `.github/workflows/terraform-apply.yml:11-19,84-97` accept no `gcp-guardrails/v*` tag. | 21 |
| ADO-28 | Low | `SECURITY.md:7-15,108-114` name GitHub private vulnerability reporting as "the only guaranteed channel", but `gh api repos/EdwinKassier/Ashes-Devops-Tools/private-vulnerability-reporting` returns `{"enabled":false}`, and Discussions are off (`has_discussions: false`) although SECURITY.md links them. | 22 |
| IAC-4 | Medium | 9 inputs are `type = any` (plus `list(any)` in `modules/aws/ops/cloudwatch`). 6 carry hand-kept `contains([...])` allowlists; the 3 in `envs/gcp/network-hub` (`vpn`, `interconnects`, `hub_additional_regions`) have none, so a misspelled key is dropped silently by the stage's object type. | 23 |
| IAC-8 | Medium | Deletion protection is spelled `enable_deletion_protection` (14), `deletion_protection` (7 modules), `delete_protection` (`modules/aws/network/network-firewall`), `alb_enable_deletion_protection` and `app_alb_enable_deletion_protection`. | 24 |
| IAC-9 | Medium | `envs/tfc-admin/main.tf:405,481` read upstream outputs through `try(..., {})`; a renamed or missing key leaves every `TFC_GCP_*` / `TFC_AWS_*` variable unset with no error. | 25 |
| IAC-10 | Low | `modules/aws/stages/security/main.tf:240,291` (`depends_on = [module.log_archive_bucket]` in the two `cloudtrail` module blocks at 214 and 263). | 26 |
| IAC-11 | Low | checkov 3.3.17 with `.checkov.yaml`: 11 failures on `modules/` (CKV_TF_1 x3 in tag-pinned examples, CKV_GCP_26/74 x6 on the PSC NAT subnet, CKV2_AWS_20 and CKV_AWS_378 in the load-balancer example). `.checkov.yaml:1-75,138-143` cite moved paths, claim no GKE or Cloud SQL resources exist, and pin checkov 3.2.x. | 27 |
| IAC-14 | Low | `modules/aws/security/incident-response/versions.tf:11` `>= 2.0, < 3.0` vs `examples/basic/versions.tf:11` `>= 2.0`. | 28 |

## Decisions needed

1. **ADO-11 badges.** Keep the two live workflow badges (they are truthful: they show red today) and add a "CI status" paragraph that says what is red and why, or remove them until CI is green. **Recommendation: keep them and add the paragraph (Task 1).** Removing a truthful red signal reads as hiding it.
2. **IAC-1 resolution rule.** Option A: the flag is required in `config/landing-zone.yaml` (schema plus a Terraform validation in every root that reads it) and in tfc-admin's explicit `environments` variable; the GCP roots' typed `var.environments` keep `optional(bool, false)`; every name heuristic is deleted. Option B: also make `is_production` required in the six GCP roots' typed `environments` variables (17 test files set that variable). **Recommendation: A.** It closes the dangerous case (a `prod` key without the flag) on every path an operator uses (config file, tfc-admin), keeps one rule ("only the flag counts; absent in a typed variable means false"), and avoids a breaking change to an input that already behaves that way.
3. **ADO-17 default.** `aws.layers` absent means all four optional layers (no change for existing estates), or means none (minimum footprint by default). **Recommendation: all four.** A default that deletes workspaces on upgrade is a breaking change with no safety benefit.
4. **ADO-27 guardrails release tags.** Option A: accept `gcp-guardrails/v*` and verify the run with a separate read-only token (`TFC_TOKEN_GUARDRAILS`) from a security-owned team that tfc-admin grants `runs = read` on the guardrails project only. Option B: no release tag for `gcp-guardrails`; HCP run history is the record. **Recommendation: A (Task 21).** The guardrails project deliberately grants no other team, so reusing `TFC_TOKEN` would widen it.
5. **ADO-28 security channel.** A repository admin must switch on GitHub private vulnerability reporting (a repository setting; not something an agent may change). Decide whether to also run a `security@` alias. **Recommendation: switch on private vulnerability reporting now, drop the email promise from SECURITY.md, and add the live check (Task 22).**

## Findings judged invalid or overstated (with evidence)

- **IAC-4 count.** The audit says 11 `any` inputs with hand-kept allowlists. The tree has 9 `type = any` inputs (`modules/gcp/stages/environment/variables.tf` `app_services`; `envs/gcp/network-hub/variables.tf` `vpn`, `interconnects`, `hub_additional_regions`; `envs/gcp/workload/variables.tf` `additional_regions`, `app_services`, `vm_backup_schedules`, `os_patch_deployments`; `envs/aws/network/variables.tf` `vpn`) and one `list(any)`. Only 6 carry allowlists. The real defect is worse than stated: the three network-hub inputs have no allowlist.
- **ADO-20 "8 accounts vs 10".** The first stand-up fits (9 including management). The failure is the third workload account. The finding stands as a missing pre-check, not as a day-one blocker.
- **ADO-23 partly.** `README.md:42` ("5 layered roots, plus the security-team `gcp-guardrails`") is correct. Every "four control-plane roots" phrase is also correct. Only the listed "five roots", "five-root", "two-root" and "5 roots" phrases are wrong.
- **ADO-3 partly.** `aws-bootstrap.md:146` already documents the local-execution override; the defect is that step 2 then gives a CLI apply without saying it only works in that mode.
- **ADO-11 partly.** The live badges are accurate. The misleading parts are the CHANGELOG and README text about release-please and the absence of any CI-status statement.

---

## Task 1: Retitle the README and state CI and release status truthfully (ADO-1, ADO-11)

**Files**
- Modify: `README.md:7`, `README.md:26-30`, `README.md:38`, `README.md:324`, `README.md:329-331`, and add a "CI status" paragraph after the CI/CD table (after `README.md:327`).
- Modify: `CHANGELOG.md:8-15`.
- Modify: `scripts/check-docs-counts.sh` (add a claims ban).
- Create: `scripts/tests/test-check-docs-counts.sh`.

- [ ] **Step 1: Write the failing check test.** Create `scripts/tests/test-check-docs-counts.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/check-docs-counts.sh against a temp tree.
#   bash scripts/tests/test-check-docs-counts.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# new_tree <name> <readme-tagline>: one GCP module, one GCP root, no suites.
new_tree() {
  local t="${workdir}/$1"
  mkdir -p "${t}/scripts" "${t}/modules/gcp/x" "${t}/envs/gcp/a"
  cp "${REPO_ROOT}/scripts/check-docs-counts.sh" "${REPO_ROOT}/scripts/terraform-roots.sh" "${t}/scripts/"
  : >"${t}/modules/gcp/x/versions.tf"
  : >"${t}/envs/gcp/a/main.tf"
  {
    printf '%s\n' "$2"
    printf 'badge/modules-1- badge/test_suites-0-\n'
    printf '1 modules \xe2\x80\x94 **1 GCP \xc2\xb7 0 AWS \xc2\xb7 0 SaaS \xc2\xb7 0 TFC**\n'
    printf 'envs/gcp/*<br/>1 roots\nenvs/aws/*<br/>0 layered roots\n'
  } >"${t}/README.md"
  printf '1 modules, 1 deployable roots\n' >"${t}/CLAUDE.md"
  mkdir -p "${t}/docs"
  echo "${t}"
}

run() { bash "$1/scripts/check-docs-counts.sh" >"${workdir}/out" 2>&1; }

t="$(new_tree good '**Reference Terraform landing zone (pre-production)**')"
if run "${t}"; then ok "honest README passes"; else bad "honest README passes"; cat "${workdir}/out" >&2; fi

t="$(new_tree prodgrade '**Production-grade Terraform infrastructure**')"
if run "${t}"; then bad "Production-grade claim fails"; else ok "Production-grade claim fails"; fi
grep -q 'Production-grade' "${workdir}/out" && ok "claim is named" || bad "claim is named"

t="$(new_tree fullytested 'a fully-tested platform')"
if run "${t}"; then bad "fully-tested claim fails"; else ok "fully-tested claim fails"; fi

printf 'test-check-docs-counts: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

Note: the `envs/gcp/*<br/>` lines anticipate Task 18; until Task 18 lands they are inert text.

- [ ] **Step 2: Run it and see it fail.** `bash scripts/tests/test-check-docs-counts.sh`. Expected: "Production-grade claim fails" and "fully-tested claim fails" report FAIL (the script has no ban yet).

- [ ] **Step 3: Add the claims ban to `scripts/check-docs-counts.sh`.** Insert after the `expect CLAUDE.md ...` line:

```bash
# Claims the repo cannot back until a real-cloud apply exists (docs/known-gaps.md).
# A banned phrase in README.md or CLAUDE.md fails, so it cannot creep back.
ban() {
  # ban <file> <extended regex> <why>
  local hits
  hits="$(grep -nEi -- "$2" "$1" || true)"
  if [ -n "$hits" ]; then
    echo "::error file=$1::$1 claims more than the repo can show ($3):"
    printf '%s\n' "$hits"
    fail=1
  fi
}
for f in README.md CLAUDE.md; do
  ban "$f" 'production[- ](grade|ready)|fully[- ]tested|battle[- ]tested' \
    "no root has been applied to a real organization; see docs/runbooks/production-hardening.md"
done
```

- [ ] **Step 4: Fix the README.**

`README.md:7` becomes:

```markdown
**Reference Terraform landing zone for AWS, GCP, Supabase and Vercel (pre-production: not yet applied to a real organization)**
```

`README.md:26-30` (the "Maturity: v0.x" blockquote) becomes:

```markdown
> **Maturity: v0.x, pre-production.** Every module plans and is tested against mock
> providers and scanned by Trivy and Checkov. No root has yet been applied to a real
> organization, and the guardrails are unproven against real clouds. Read
> [`docs/known-gaps.md`](docs/known-gaps.md) before relying on any control,
> [`docs/runbooks/production-hardening.md`](docs/runbooks/production-hardening.md) before a
> production estate, and [`UPGRADING.md`](UPGRADING.md) before taking a new release.
```

In `README.md:38` replace the opening clause up to the first colon with:

```markdown
**Ashes DevOps Tools** is a reference landing zone, tested against mock providers and security-scanned, covering the four clouds it supports, `{aws, gcp, supabase, vercel}`. Each cloud is its own root(s) and Terraform Cloud workspace(s), so you deploy **any combination**:
```

`README.md:324` (the `release.yml` row) becomes:

```markdown
| [`release.yml`](.github/workflows/release.yml) | Push to `main` | release-please: maintains the release PR; merging it tags `vX.Y.Z` and updates CHANGELOG. **Inactive until a maintainer sets `RELEASE_PLEASE_TOKEN`** ([CI secrets](docs/guides/CI_SECRETS.md#release_please_token)) |
```

`README.md:329-331` (the "Releasing" paragraph, first sentence) becomes:

```markdown
**Releasing:** the repository is versioned `vX.Y.Z` by release-please from Conventional Commits once `RELEASE_PLEASE_TOKEN` is set; until then a maintainer tags releases by hand (`v0.1.0` was cut that way). Separately, a per-workspace deployment tag records release metadata for a Terraform Cloud run:
```

Add after the CI/CD table (after `README.md:327`):

```markdown
**CI status.** The two workflow badges at the top are live and show the state of `main`.
A red badge means a gate is failing on `main` now; open the latest run to see which one.
Known causes are tracked in [`docs/known-gaps.md`](docs/known-gaps.md): the release job
needs `RELEASE_PLEASE_TOKEN`, and the sandbox end-to-end job needs funded sandbox accounts
([sandbox E2E](docs/guides/sandbox-e2e.md)).
```

- [ ] **Step 5: Fix the CHANGELOG versioning note.** In `CHANGELOG.md:8-15`, append to the end of the "Versioning." paragraph:

```markdown
**Status:** release-please is configured but does not run until a maintainer sets the
`RELEASE_PLEASE_TOKEN` secret ([CI secrets](docs/guides/CI_SECRETS.md#release_please_token)).
`v0.1.0` was tagged by hand.
```

- [ ] **Step 6: Add a known-gaps entry** in `docs/known-gaps.md` under the open section:

```markdown
- **CI on `main` is red.** Security Scan fails (Trivy and Checkov findings), Release fails
  because `RELEASE_PLEASE_TOKEN` is not set, and sandbox E2E has never run green. Badges in
  README.md are live, so they show this. **Close by:** fixing the scanner findings (WS1
  Task 27 covers the Checkov false positives), setting the token, and funding the sandbox.
```

- [ ] **Step 7: Run and pass.** `bash scripts/tests/test-check-docs-counts.sh && ./scripts/check-docs-counts.sh && make links`. Expected: all ok; `check-docs-counts: README.md and CLAUDE.md counts match the tree`.

- [ ] **Step 8: Wire the test.** Nothing to add: `make test-scripts` runs every `scripts/tests/test-*.sh`.

- [ ] **Step 9: Commit.** `docs(readme): call the repo a pre-production reference and state CI and release status`

---

## Task 2: Make the documented workload plan work (ADO-2)

**Files**
- Modify: `examples/dev.tfvars.example:15-31`.
- Modify: `Makefile:31` and `Makefile:225-226`.
- Modify: `docs/guides/QUICK_START.md:288-291,394-398,424`, `README.md:313`.
- Create: `scripts/check-example-tfvars.sh`, `scripts/tests/test-check-example-tfvars.sh`.
- Modify: `scripts/check-consistency.sh` (call the new script).

- [ ] **Step 1: Write the failing test** `scripts/tests/test-check-example-tfvars.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/check-example-tfvars.sh.
#   bash scripts/tests/test-check-example-tfvars.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-example-tfvars.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

printf 'enable_cloud_armor = false\nterraform_admin_email = "x@y.iam.gserviceaccount.com"\n' >"${workdir}/dev.tfvars.example"
if out="$(bash "${SCRIPT}" "${workdir}" 2>&1)"; then bad "identity key fails"; else ok "identity key fails"; fi
grep -q 'terraform_admin_email' <<<"${out}" && ok "key is named" || bad "key is named"

printf '  # tfc_organization = "commented out is fine"\nenable_cloud_armor = false\n' >"${workdir}/dev.tfvars.example"
if bash "${SCRIPT}" "${workdir}" >/dev/null 2>&1; then ok "tuning-only file passes"; else bad "tuning-only file passes"; fi

if bash "${SCRIPT}" >/dev/null 2>&1; then ok "repo examples pass"; else bad "repo examples pass"; fi

printf 'test-check-example-tfvars: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

- [ ] **Step 2: Run it and see it fail** (script missing): `bash scripts/tests/test-check-example-tfvars.sh`.

- [ ] **Step 3: Create `scripts/check-example-tfvars.sh`:**

```bash
#!/usr/bin/env bash
# Fail when a local-plan example tfvars file sets an identity or placement input.
# Those come from config/landing-zone.yaml and the TFC workspace variables that
# envs/tfc-admin writes. An explicit variable beats the config file, so an
# example that sets one points a fork's plan at the upstream placeholder estate.
#
#   scripts/check-example-tfvars.sh [DIR]   (default: examples/; CI via check-consistency.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-${REPO_ROOT}/examples}"
FORBIDDEN='project_prefix|environment|region|default_region|terraform_admin_email|tfc_organization|organization_workspace_name|projects_workspace_name|network_hub_workspace_name|domain|billing_account|landing_zone_name|management_account_id'

hits=""
for f in "${DIR}"/*.tfvars.example; do
  [[ -e "${f}" ]] || continue
  found="$(grep -nE "^[[:space:]]*(${FORBIDDEN})[[:space:]]*=" "${f}" || true)"
  [[ -z "${found}" ]] || hits+="$(printf '%s\n' "${found}" | sed "s|^|${f#"${REPO_ROOT}/"}:|")"$'\n'
done

if [[ -n "${hits}" ]]; then
  echo "Example tfvars set inputs that config/landing-zone.yaml or tfc-admin owns:" >&2
  printf '%s' "${hits}" >&2
  echo "Remove them: an explicit variable overrides the config file." >&2
  exit 1
fi
echo "check-example-tfvars: no identity or placement inputs in example tfvars"
```

`chmod +x scripts/check-example-tfvars.sh`.

- [ ] **Step 4: Strip the example.** Replace `examples/dev.tfvars.example:15-31` (from the "Project & identity" banner through `organization_workspace_name = "gcp-organization"`) with:

```hcl
# ── Identity and placement come from config/landing-zone.yaml ────────────────
# project_prefix, environment, region, tfc_organization and the upstream
# workspace names are NOT set here: the root reads them from
# config/landing-zone.yaml (org.prefix, gcp.environments.<env>, org.tfc.*) and
# from the workspace variables tfc-admin writes. An explicit value here would
# override them. terraform_admin_email stays unset: plans run in HCP Terraform
# with the workspace's own plan identity (CLAUDE.md "State & Apply Rules").
```

Also update the header comment at `examples/dev.tfvars.example:8-9` to:

```hcl
#   make plan-gcp-workload APP_ENV=dev APP_VARS=examples/dev.tfvars.example
#   (without APP_VARS the plan uses config/landing-zone.yaml alone)
```

- [ ] **Step 5: Make `APP_VARS` optional.** `Makefile:31` becomes `APP_VARS ?=`. `Makefile:225-226` becomes:

```make
plan-gcp-workload: ## Plan gcp-workload-<APP_ENV> in HCP Terraform (read-only); APP_VARS=<file> adds a tuning -var-file
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload plan $(if $(APP_VARS),-var-file=$(abspath $(APP_VARS)))
```

- [ ] **Step 6: Fix the docs.** `docs/guides/QUICK_START.md:290`: drop `-var-file=../../../examples/dev.tfvars.example`. `QUICK_START.md:397` and `README.md:313` become `make plan-gcp-workload APP_ENV=dev`. `QUICK_START.md:424` row becomes ``| `make plan-gcp-workload APP_ENV=dev` | Plan an app environment (add `APP_VARS=examples/dev.tfvars.example` for local tuning knobs) |``.

- [ ] **Step 7: Wire into consistency.** Append to `scripts/check-consistency.sh`, before its final exit block:

```bash
echo "==> Example tfvars set no identity or placement inputs (scripts/check-example-tfvars.sh)"
./scripts/check-example-tfvars.sh >/dev/null || note "examples/*.tfvars.example sets an input config/landing-zone.yaml owns"
```

- [ ] **Step 8: Run and pass.** `bash scripts/tests/test-check-example-tfvars.sh && ./scripts/check-consistency.sh && make -n plan-gcp-workload APP_ENV=dev` (the dry run must show `plan` with no `-var-file`).

- [ ] **Step 9: Commit.** `fix(examples): stop dev.tfvars.example from overriding the config file in workload plans`

---

## Task 3: Give the first aws-organization apply a path HCP Terraform accepts (ADO-3)

**Files**
- Modify: `docs/runbooks/aws-bootstrap.md:146` and `:252-258`.

- [ ] **Step 1: Replace the "Run #1 state note" paragraph at `aws-bootstrap.md:146`** with:

```markdown
**Run #1: where it executes.** tfc-admin creates `aws-organization` connected to VCS in
**remote** execution mode. HCP Terraform refuses `terraform apply` from the CLI on a
VCS-connected remote workspace, so pick one:

- **Option B roles (recommended):** queue the run in HCP Terraform (workspace
  `aws-organization` > **New run** > **Plan and apply**), review the plan, and confirm it.
  The run uses the `TFC_AWS_*` variables tfc-admin set in pass 1.
- **Option A static key, or no TFC credentials yet:** set tfc-admin
  `workspace_execution_modes = { "gcp-bootstrap" = "local", "aws-organization" = "local" }`
  and re-apply tfc-admin. Keep the `gcp-bootstrap` entry if GCP is enabled: the map
  replaces the default, it does not merge with it. The run then executes on your
  machine with the credentials in your shell, while state lands in the TFC workspace.
  After run #1, remove the `aws-organization` entry and re-apply tfc-admin so every
  later run is remote and policy-checked.

The `-backend=false` local-state-then-migrate route also works, but is rarely needed now
that tfc-admin creates the workspace up front.
```

- [ ] **Step 2: Replace the command block at `aws-bootstrap.md:254-256`** with:

```markdown
   - Remote (Option B): queue a run on `aws-organization` in HCP Terraform and confirm the apply.
   - Local execution mode (Option A, see Step 3): `terraform -chdir=envs/aws/organization apply`.
     This works only while tfc-admin holds `aws-organization` in `local` mode.
```

- [ ] **Step 3: Verify.** `make links`; `grep -n 'terraform -chdir=envs/aws/organization apply' docs/runbooks/aws-bootstrap.md` shows only the line inside the local-mode bullet.

- [ ] **Step 4: Commit.** `docs(aws-bootstrap): queue the first aws-organization run in HCP Terraform or use local mode`

---

## Task 4: Generate every root's variable reference and stop hand-writing it (ADO-4)

**Files**
- Create: `.terraform-docs-envs.yml`.
- Modify: `scripts/module-docs.sh` (also process `envs/**` roots).
- Create: `README.md` with markers in each of the 11 roots that lack one: `envs/gcp/{bootstrap,projects,network-hub}`, `envs/aws/{organization,security,network,identity,shared-services,backup,workload}`, `envs/saas`.
- Modify: `docs/guides/QUICK_START.md:295-362` (section 6).
- Create: `scripts/tests/test-module-docs.sh`.

- [ ] **Step 1: Write the failing test** `scripts/tests/test-module-docs.sh`:

```bash
#!/usr/bin/env bash
# Every deployable root has a README whose terraform-docs block is current, so
# the variable reference cannot drift from variables.tf (ADO-4).
#   bash scripts/tests/test-module-docs.sh   (make test-scripts; needs terraform-docs)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

while IFS= read -r root; do
  readme="${REPO_ROOT}/${root}/README.md"
  if [[ -f "${readme}" ]] && grep -q '<!-- BEGIN_TF_DOCS -->' "${readme}"; then
    ok "${root} has a generated reference"
  else
    bad "${root} has no README with BEGIN_TF_DOCS"
  fi
done < <(cd "${REPO_ROOT}" && ./scripts/terraform-roots.sh envs)

if (cd "${REPO_ROOT}" && bash scripts/module-docs.sh check >/dev/null 2>&1); then
  ok "module-docs check passes"
else
  bad "module-docs check passes"
fi
grep -q 'terraform-roots.sh envs' "${REPO_ROOT}/scripts/module-docs.sh" && ok "envs roots are generated" || bad "envs roots are generated"

printf 'test-module-docs: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

- [ ] **Step 2: Run it and see 11 FAIL lines plus "envs roots are generated" FAIL.**

- [ ] **Step 3: Create `.terraform-docs-envs.yml`** (roots get no "Usage: module" block):

```yaml
formatter: "markdown table"
version: ">=0.19"
sections:
  show:
    - requirements
    - providers
    - inputs
    - outputs
output:
  file: README.md
  mode: inject
  template: |-
    <!-- BEGIN_TF_DOCS -->
    {{ .Content }}
    <!-- END_TF_DOCS -->
sort:
  enabled: true
  by: required
settings:
  anchor: true
  default: true
  escape: true
  hide-empty: true
  html: true
  required: true
  sensitive: true
  type: true
```

Check `.terraform-docs.yml` for its `output:` block and copy any setting the module config uses that this one omits, so formatting matches.

- [ ] **Step 4: Extend `scripts/module-docs.sh`.** Replace the loop input `done < <(./scripts/terraform-roots.sh modules)` with a loop over both sets, choosing the config per set:

```bash
run_docs() {
  # run_docs <config> <dir>
  case "$mode" in
    generate) terraform-docs --config "$1" "$2" ;;
    check) terraform-docs --config "$1" --output-check "$2" || fail=1 ;;
    *) echo "Usage: $0 [generate|check]" >&2; exit 1 ;;
  esac
}
while IFS= read -r module_dir; do run_docs .terraform-docs.yml "$module_dir"; done \
  < <(./scripts/terraform-roots.sh modules)
while IFS= read -r root_dir; do run_docs .terraform-docs-envs.yml "$root_dir"; done \
  < <(./scripts/terraform-roots.sh envs)
```

(Keep the existing comments; remove the old `case` inside the first loop.)

- [ ] **Step 5: Create the 11 missing READMEs.** Each starts with one paragraph that names the workspace, what the root deploys, what it reads, and the config keys it reads, then the markers. Template (fill in per root from `envs/<root>/main.tf` header comments and `docs/architecture/provider-selection.md:42-62`):

```markdown
# `envs/aws/network` (workspace `aws-network`)

Shared AWS networking in the network account: Transit Gateway, IPAM, inspection VPC with
Network Firewall, egress, Route 53 Resolver. Reads the `aws-organization` contract. Most
inputs come from `config/landing-zone.yaml` (`aws.network.*`); an explicit variable
(tfvars or a TFC workspace variable) wins over the config file.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
```

- [ ] **Step 6: Generate.** `make docs`. Then `make docs-check` passes.

- [ ] **Step 7: Replace QUICK_START section 6** (`QUICK_START.md:295-362`, from `## 6. Variable Reference` up to and including the "Hybrid connectivity" note) with:

```markdown
## 6. Variable Reference

Each root's full input list (name, type, default, description) is generated from its
`variables.tf` into the root's README by `make docs`, and `make docs-check` (CI) fails when
it is stale. Most inputs are optional because they default to a key in
`config/landing-zone.yaml`; the description of each input names that key.

| Root | Workspace | Inputs |
|---|---|---|
| `envs/gcp/bootstrap` | `gcp-bootstrap` | [README](../../envs/gcp/bootstrap/README.md#inputs) |
| `envs/gcp/organization` | `gcp-organization` | [README](../../envs/gcp/organization/README.md#inputs) |
| `envs/gcp/guardrails` | `gcp-guardrails` | [README](../../envs/gcp/guardrails/README.md#inputs) |
| `envs/gcp/projects` | `gcp-projects` | [README](../../envs/gcp/projects/README.md#inputs) |
| `envs/gcp/network-hub` | `gcp-network-hub` | [README](../../envs/gcp/network-hub/README.md#inputs) |
| `envs/gcp/workload` | `gcp-workload-<env>` | [README](../../envs/gcp/workload/README.md#inputs) |
| `envs/tfc-admin` | `tfc-admin` | [README](../../envs/tfc-admin/README.md#inputs) |

The values operators most often look for, and where they really live:

| Setting | Set it in `config/landing-zone.yaml` | Or as a variable on |
|---|---|---|
| Org admin email | `gcp.admin_email` | `gcp-organization`: `gcp_overrides.admin_email` |
| Org admin groups | `gcp.organization_admin_groups` | `gcp-organization`: `gcp_overrides.organization_admin_groups` |
| Break-glass group | `gcp.break_glass_group` | `gcp-organization`: `gcp_overrides.containment_exempt_principals` |
| Security contact (Essential Contacts) | (no config key) | `gcp-organization`: `gcp_overrides.security_contact_email` |
| Break-glass user | (no config key) | `gcp-organization`: `gcp_overrides.break_glass_user` |

`gcp_overrides` is one object variable: set every key you need in the same value, because a
later value replaces the whole object ([presets README](../../examples/presets/README.md)).
Hybrid connectivity (HA VPN, Interconnect) is configured under `gcp.network.vpn` and
`gcp.network.interconnect`; the VPN pre-shared key is the write-only `vpn_shared_secret_wo`
variable on `gcp-network-hub` ([hybrid connectivity runbook](../runbooks/gcp-hybrid-connectivity.md)).
```

Check the anchor names terraform-docs emits (`#inputs`) in one generated README before committing; `make links` validates them.

- [ ] **Step 8: Run and pass.** `bash scripts/tests/test-module-docs.sh && make docs-check links count-check`.

- [ ] **Step 9: Commit.** `docs: generate every root's variable reference and replace the hand-written QUICK_START table`

---

## Task 5: One production rule: the explicit `is_production` flag (IAC-1)

Implements Decision 2, option A.

**Files**
- Modify: `config/landing-zone.schema.json` (`required: ["is_production"]` on `gcp.environments.*` and `aws.workload_environments.*`).
- Create: `config/tests/missing_is_production.yaml`.
- Modify: `config.tf` and the `environments` (or listed) variable in `envs/gcp/{bootstrap,organization,guardrails,projects,network-hub,workload}`, `envs/aws/network`, `envs/tfc-admin`.
- Modify: `envs/tfc-admin/config.tf:159-165`, `envs/tfc-admin/variables.tf:33-36,168`, `envs/aws/network/config.tf:47-52`, `envs/aws/network/variables.tf:266-270`, `envs/gcp/workload/main.tf:143-145,313-320`.
- Modify: every shipped YAML without the flag (57 entries in 35 files; list below) and the tfc-admin tests that rely on the name fallback.
- Create: `scripts/check-production-rule.sh`, `scripts/tests/test-check-production-rule.sh`.
- Modify: `config/landing-zone.example.yaml:82-83,347` (comments that describe the old fallback), `UPGRADING.md`, `CHANGELOG.md`.

- [ ] **Step 1: Failing check test** `scripts/tests/test-check-production-rule.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/check-production-rule.sh.
#   bash scripts/tests/test-check-production-rule.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-production-rule.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

mkdir -p "${workdir}/envs/x"
printf 'locals {\n  p = can(regex("^prod(uction)?$", var.environment))\n}\n' >"${workdir}/envs/x/main.tf"
if bash "${SCRIPT}" "${workdir}/envs" >/dev/null 2>&1; then bad "name regex fails"; else ok "name regex fails"; fi

printf 'locals {\n  p = coalesce(x, can(regex("prod", lower(var.environment))))\n}\n' >"${workdir}/envs/x/main.tf"
if bash "${SCRIPT}" "${workdir}/envs" >/dev/null 2>&1; then bad "substring regex fails"; else ok "substring regex fails"; fi

printf 'locals {\n  p = try(local.env_config.is_production, null) == true\n}\n' >"${workdir}/envs/x/main.tf"
if bash "${SCRIPT}" "${workdir}/envs" >/dev/null 2>&1; then ok "flag-only rule passes"; else bad "flag-only rule passes"; fi

if bash "${SCRIPT}" >/dev/null 2>&1; then ok "repo passes"; else bad "repo passes"; fi
printf 'test-check-production-rule: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

- [ ] **Step 2: Create `scripts/check-production-rule.sh`:**

```bash
#!/usr/bin/env bash
# Fail when Terraform code decides "production" from an environment's name.
# The rule: an environment is production when its is_production is true.
# config/landing-zone.schema.json requires the flag on every environment, and
# each root that reads it rejects a config entry without it, so no name-based
# fallback (regex on "prod", "^prod(uction)?$") may exist.
#
#   scripts/check-production-rule.sh [DIR...]   (default: envs modules; CI via check-consistency.sh)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -eq 0 ]]; then set -- "${REPO_ROOT}/envs" "${REPO_ROOT}/modules"; fi
hits="$(grep -rnE --include='*.tf' 'regex\("[^"]*prod' "$@" | grep -v '/\.terraform/' || true)"
if [[ -n "${hits}" ]]; then
  echo "Production is decided from an environment name; use is_production only:" >&2
  printf '%s\n' "${hits}" >&2
  exit 1
fi
echo "check-production-rule: no name-based production checks"
```

`chmod +x`. Run the test: "repo passes" FAILS (4 hits). That is the expected red.

- [ ] **Step 3: Failing Terraform tests.** Create the fixture `envs/gcp/organization/tests/fixtures/landing-zone-missing-is-production.yaml` as a copy of `landing-zone-starter.yaml` (which stays without the flag only in this copy). Add to `envs/gcp/organization/tests/root.tftest.hcl`:

```hcl
run "config_environment_without_is_production_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-missing-is-production.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  expect_failures = [var.environments]
}
```

Add the same shape to each other root, with a `-missing-is-production.yaml` fixture copied from the fixture its template run uses, and the template run's variable nulls:

| Root | Template run (copy its `variables`) | `expect_failures` |
|---|---|---|
| `envs/gcp/bootstrap` | `identity_wiring.tftest.hcl` run `principal_access_boundary_from_config` | `[var.environments]` |
| `envs/gcp/guardrails` | `root.tftest.hcl` run `containment_spec_from_config` | `[var.environments]` |
| `envs/gcp/projects` | the first run in `config.tftest.hcl` | `[var.environments]` |
| `envs/gcp/network-hub` | `hybrid.tftest.hcl` run `gcp_vpn_reaches_net_hub_from_config` | `[var.environments]` |
| `envs/gcp/workload` | the first run in `config.tftest.hcl` | `[var.environment]` |
| `envs/aws/network` | `contract.tftest.hcl` run `config_without_contract_still_reads_remote_state` | `[var.enforce_egress_allowlist]` |
| `envs/tfc-admin` | the first run in `config.tftest.hcl` | `[var.environments]` |

Also add to `envs/tfc-admin/tests/root.tftest.hcl`:

```hcl
run "explicit_environment_without_is_production_fails" {
  command = plan
  variables {
    environments = { prod = {} }
  }
  expect_failures = [var.environments]
}

run "prod_key_without_flag_is_not_production_by_name" {
  command = plan
  variables {
    environments = { prod = { is_production = false } }
  }
  assert {
    condition     = !contains(local.production_workloads, "gcp-workload-prod")
    error_message = "Only is_production decides production; the key prod alone must not."
  }
}
```

And to `envs/gcp/workload/tests/root.tftest.hcl` (or the suite that sets `projects_contract`), a run whose `projects_contract.environment_config.<env>` omits `is_production` with `expect_failures = [terraform_data.projects_contract_guard]`.

Run each root: `make test TEST_DIRS=envs/gcp/organization TERRAFORM=$TF` (and the others). Expected: the new runs FAIL ("expected failure not raised") because nothing checks the flag yet.

- [ ] **Step 4: Schema.** In `config/landing-zone.schema.json`, add `"required": ["is_production"]` to the object at `properties.gcp.properties.environments.additionalProperties` and at `properties.aws.properties.workload_environments.additionalProperties`. Create `config/tests/missing_is_production.yaml`:

```yaml
# Expected to FAIL schema validation: every environment must set is_production.
version: 1
org:
  name: acme
gcp:
  environments:
    prod:
      region: europe-west2
```

- [ ] **Step 5: Add the flag to every shipped YAML.** Use this one-off helper from the scratchpad (do not commit it). It adds `is_production: true` for keys `prod` / `production` and `false` otherwise, which reproduces the old effective value in every listed file (GCP fixtures only have `dev`; the AWS and tfc-admin fixtures relied on the name match for `prod`):

```python
#!/usr/bin/env python3
# scratchpad/add_is_production.py FILE...: add is_production to environments that lack it.
import re, sys, yaml
for path in sys.argv[1:]:
    lines = open(path).read().split("\n")
    doc = yaml.safe_load("\n".join(lines)) or {}
    todo = []
    for sec, key in (("gcp", "environments"), ("aws", "workload_environments")):
        envs = ((doc.get(sec) or {}).get(key)) or {}
        todo += [(sec, key, k) for k, e in envs.items() if not (isinstance(e, dict) and "is_production" in e)]
    for sec, key, env in todo:
        flag = "true" if env in ("prod", "production") else "false"
        in_sec = in_key = False
        for i, line in enumerate(lines):
            if re.match(r"^[a-z_]+:", line):
                in_sec, in_key = line.startswith(sec + ":"), False
                continue
            if in_sec and re.match(r"^\s+%s:\s*$" % key, line):
                in_key, key_indent = True, len(line) - len(line.lstrip())
                continue
            m = re.match(r"^(\s+)%s:(.*)$" % re.escape(env), line) if in_key else None
            if m and len(m.group(1)) > key_indent:
                rest = m.group(2).strip()
                if rest.startswith("{"):
                    lines[i] = "%s%s: {is_production: %s, %s" % (m.group(1), env, flag, rest[1:].lstrip())
                else:
                    lines.insert(i + 1, "%s  is_production: %s" % (m.group(1), flag))
                break
        else:
            sys.exit("%s: could not place %s.%s.%s" % (path, sec, key, env))
    open(path, "w").write("\n".join(lines))
    after = yaml.safe_load(open(path)) or {}
    for sec, key in (("gcp", "environments"), ("aws", "workload_environments")):
        for env, e in (((after.get(sec) or {}).get(key)) or {}).items():
            assert isinstance(e, dict) and "is_production" in e, f"{path}: {sec}.{key}.{env} still lacks is_production"
```

Run it on: `config/sandbox/landing-zone.yaml`, every `landing-zone*.yaml` under `envs/tfc-admin/tests/fixtures`, `envs/gcp/{organization,guardrails,projects,workload}/tests/fixtures`, `envs/aws/{organization,network,workload}/tests/fixtures`, and `modules/gcp/stages/bootstrap/tests/fixtures/landing-zone.scaffolded.yaml` (exclude the new `-missing-is-production.yaml` fixtures). Then `make scaffold-fixtures` (regenerates `tests/fixtures/scaffold/*` from the example, which already sets the flag) and `make config-check`.

- [ ] **Step 6: Terraform: one rule in every root.**

GCP roots (`envs/gcp/{bootstrap,organization,guardrails,projects,network-hub}/config.tf`): inside `local.cfg`, next to `environments`, add:

```hcl
    # Environment keys whose is_production is missing or not a boolean. The
    # schema requires it; the environments validation names them.
    environments_missing_is_production = sort([
      for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : k
      if try(tobool(e.is_production), null) == null
    ])
```

and in each root's `variable "environments"` add:

```hcl
  validation {
    condition     = var.environments != null || length(local.cfg.environments_missing_is_production) == 0
    error_message = "Every gcp.environments entry in config/landing-zone.yaml must set is_production: true or false; the environment name is not read. Missing or invalid: ${join(", ", local.cfg.environments_missing_is_production)}."
  }
```

(`envs/gcp/guardrails/config.tf` builds `local.environments` rather than `local.cfg.environments`; put the new key wherever its config-only values live, keeping the "config-only, no variable references" rule stated at the top of each `config.tf`.)

`envs/gcp/workload`: add the same `environments_missing_is_production` key to `local.cfg` in `config.tf`, put the validation on `variable "environment"`, and replace `main.tf:143-145` with:

```hcl
  # Production is the environment_config flag from gcp-projects, nothing else.
  # projects_contract_guard fails the plan when the contract omits it.
  is_production = try(local.env_config.is_production, null) == true
```

and add a second precondition to `terraform_data.projects_contract_guard` (`main.tf:313-320`):

```hcl
    precondition {
      condition     = try(local.env_config.is_production, null) != null
      error_message = "The gcp-projects contract environment_config.${var.environment} has no is_production (projects_contract / gcp.contracts.projects, else the ${var.projects_workspace_name} workspace's contract output). Set it to true or false; the environment name is not read."
    }
```

`envs/aws/network/config.tf:47-52` becomes:

```hcl
    # aws.workload_environments production flags (is_production is required).
    workload_production = try([
      for k, e in local.lz.aws.workload_environments : k if try(tobool(e.is_production), false)
    ], [])
    workload_missing_is_production = sort([
      for k, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : k
      if try(tobool(e.is_production), null) == null
    ])
```

and `variable "enforce_egress_allowlist"` (`envs/aws/network/variables.tf:266-270`) gets the description suffix change ("an aws.workload_environments entry is_production") and:

```hcl
  validation {
    condition     = length(local.cfg.workload_missing_is_production) == 0
    error_message = "Every aws.workload_environments entry in config/landing-zone.yaml must set is_production: true or false; the environment name is not read. Missing or invalid: ${join(", ", local.cfg.workload_missing_is_production)}."
  }
```

`envs/tfc-admin/config.tf`: in `local.cfg` add

```hcl
    missing_is_production = sort(concat(
      [for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : "gcp.environments.${k}" if try(tobool(e.is_production), null) == null],
      [for k, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : "aws.workload_environments.${k}" if try(tobool(e.is_production), null) == null],
    ))
```

and replace `config.tf:159-165` with:

```hcl
  # Production environments: is_production true, nothing else (the variable
  # validation guarantees every environment states it).
  gcp_production_flags = var.environments != null ? { for k, e in var.environments : k => e.is_production } : local.cfg.gcp_production
  production_workloads = toset(concat(
    [for k in local.gcp_environment_keys : "${local.catalog_family.gcp}-${k}" if try(local.gcp_production_flags[k], null) == true],
    [for k, e in local.aws_environments : "${local.catalog_family.aws}-${k}" if e.is_production == true],
  ))
```

In `envs/tfc-admin/variables.tf` add to `variable "environments"`:

```hcl
  validation {
    condition = (var.environments != null
      ? alltrue([for e in values(var.environments) : e.is_production != null])
    : length(local.cfg.missing_is_production) == 0)
    error_message = "is_production must be true or false on every environment (environments[*].is_production, or gcp.environments / aws.workload_environments in config/landing-zone.yaml); a name such as prod is not read. Missing: ${var.environments != null ? join(", ", [for k, e in var.environments : k if e.is_production == null]) : join(", ", local.cfg.missing_is_production)}."
  }
```

and rewrite the two descriptions that say "unset = true only for the keys prod / production" (`variables.tf:33`, `:168`) to "is_production (required) marks a production workload".

- [ ] **Step 7: Update tfc-admin tests that relied on the name.** `grep -n 'prod *= *{}' envs/tfc-admin/tests/*.hcl`: set `{ is_production = true }` on `prod` and `{ is_production = false }` on the others (including the top-level `variables` block in `root.tftest.hcl:12-15`). Leave the new failing run with `prod = {}`.

- [ ] **Step 8: Fix the comments.** `config/landing-zone.example.yaml:82-83` and `:347`: drop "unset = keys prod/production" and say "is_production is required on every environment". Same in `envs/aws/network/variables.tf:267`.

- [ ] **Step 9: Wire the check.** Append to `scripts/check-consistency.sh`:

```bash
echo "==> Production is decided by is_production only (scripts/check-production-rule.sh)"
./scripts/check-production-rule.sh >/dev/null || note "a root decides production from an environment name"
```

- [ ] **Step 10: Run and pass.** For each of the 8 roots: `make test TEST_DIRS=<root> TERRAFORM=$TF`. Then `make test TEST_DIRS="modules/gcp/stages/bootstrap" TERRAFORM=$TF`, `make config-check scaffold-fixtures-check test-scripts consistency`. Expected: all suites pass; `config-check: negative fixtures rejected as expected` includes `missing_is_production.yaml`.

- [ ] **Step 11: UPGRADING and CHANGELOG.** `UPGRADING.md` under "Unreleased":

```markdown
### `is_production` is required on every environment

**Who:** every fork. **Before the apply:** add `is_production: true` or `is_production: false`
to each entry under `gcp.environments` and `aws.workload_environments` in
`config/landing-zone.yaml`, and to each entry of tfc-admin's `environments` variable if you
set it. The plan now fails naming any entry without it. The names `prod` and `production`
no longer make an environment production on their own: previously tfc-admin and aws-network
treated an unflagged `prod` as production while the GCP roots treated it as non-production.
Check that each flag matches what you intend before applying.
```

`CHANGELOG.md` "Unreleased" under a "Changed" heading: one bullet with the same summary.

- [ ] **Step 12: Commit.** `feat!: decide production from the is_production flag alone and require it on every environment`

---

## Task 6: Schema-validate the fork's real config file (IAC-2)

**Files**
- Create: `scripts/check-config.sh` (moves the logic out of `Makefile:333-341`).
- Modify: `Makefile:333-341`, `.pre-commit-config.yaml` (new hook).
- Create: `scripts/tests/test-check-config.sh`.

The Terraform-side guard for the typo case is Task 5's required-key validation: `is_prodution: true` leaves `is_production` missing, so every root that reads it fails the plan and names the environment. The schema check catches every other unknown key.

- [ ] **Step 1: Failing test** `scripts/tests/test-check-config.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/check-config.sh: the fork's real config/landing-zone.yaml is validated.
#   bash scripts/tests/test-check-config.sh   (make test-scripts; needs check-jsonschema)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-config.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }
command -v check-jsonschema >/dev/null || { echo "check-jsonschema not found (make install)" >&2; exit 1; }

mkdir -p "${workdir}/config"
cp "${REPO_ROOT}/config/landing-zone.schema.json" "${REPO_ROOT}/config/landing-zone.example.yaml" "${workdir}/config/"

# A typo in the real file must fail and name the file.
sed '0,/is_production: false/s//is_prodution: false/' "${REPO_ROOT}/config/landing-zone.example.yaml" >"${workdir}/config/landing-zone.yaml"
if out="$(bash "${SCRIPT}" "${workdir}" 2>&1)"; then bad "typo in config/landing-zone.yaml fails"; else ok "typo in config/landing-zone.yaml fails"; fi
grep -q 'landing-zone.yaml' <<<"${out}" && ok "file is named" || bad "file is named"

cp "${REPO_ROOT}/config/landing-zone.example.yaml" "${workdir}/config/landing-zone.yaml"
if bash "${SCRIPT}" "${workdir}" >/dev/null 2>&1; then ok "valid real file passes"; else bad "valid real file passes"; fi

rm "${workdir}/config/landing-zone.yaml"
if bash "${SCRIPT}" "${workdir}" >/dev/null 2>&1; then ok "absent real file is fine"; else bad "absent real file is fine"; fi

printf 'test-check-config: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

(The `sed '0,/re/'` form is GNU; on macOS run `make test-scripts` with `gsed` on PATH or replace with a `python3 -I -c` one-liner. CI runs Linux.)

- [ ] **Step 2: Create `scripts/check-config.sh`:**

```bash
#!/usr/bin/env bash
# Validate landing-zone configs against config/landing-zone.schema.json:
#   config/landing-zone.yaml (the fork's real file, when present), the example,
#   config/sandbox/, every test fixture, and tests/fixtures/scaffold. Then check
#   the schema covers every key a root reads, and that config/tests/*.yaml (the
#   negative fixtures) are rejected.
#
#   scripts/check-config.sh [ROOT]   (make config-check; CI: meta-lint)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${1:-${SCRIPT_DIR}/..}" && pwd)"
SCHEMA="${ROOT}/config/landing-zone.schema.json"
command -v check-jsonschema >/dev/null || { echo "check-jsonschema not found: make install" >&2; exit 1; }
cd "${ROOT}"

files=()
[[ -f config/landing-zone.yaml ]] && files+=(config/landing-zone.yaml)
while IFS= read -r f; do files+=("${f}"); done < <(
  {
    [[ -f config/landing-zone.example.yaml ]] && echo config/landing-zone.example.yaml
    find config/sandbox -name 'landing-zone*.yaml' 2>/dev/null || true
    find envs modules -name 'landing-zone*.yaml' -path '*/tests/fixtures/*' 2>/dev/null || true
    find tests/fixtures/scaffold -name 'landing-zone*.yaml' 2>/dev/null || true
  } | sort -u
)
check-jsonschema --schemafile "${SCHEMA}" "${files[@]}"

"${SCRIPT_DIR}/check-config-schema-coverage.sh" "${SCHEMA}" "${SCRIPT_DIR}/../envs"

for f in config/tests/*.yaml; do
  [[ -e "${f}" ]] || continue
  if check-jsonschema --schemafile "${SCHEMA}" "${f}" >/dev/null 2>&1; then
    echo "config-check: ${f} should FAIL schema validation but passed" >&2
    exit 1
  fi
done
echo "config-check: ${#files[@]} files valid; negative fixtures rejected as expected"
```

- [ ] **Step 3: Makefile.** Replace the body of `config-check` (`Makefile:333-341`) with `@./scripts/check-config.sh` and update its `##` text to start "Validate config/landing-zone.yaml (when present), the examples, ...".

- [ ] **Step 4: Pre-commit hook** in `.pre-commit-config.yaml` (repos list):

```yaml
  - repo: https://github.com/python-jsonschema/check-jsonschema
    rev: 0.39.0
    hooks:
      - id: check-jsonschema
        name: config/landing-zone.yaml matches the schema
        files: ^config/(landing-zone|sandbox/landing-zone).*\.yaml$
        args: ["--schemafile", "config/landing-zone.schema.json"]
```

- [ ] **Step 5: Run and pass.** `bash scripts/tests/test-check-config.sh && make config-check && pre-commit run check-jsonschema --all-files`.

- [ ] **Step 6: Commit.** `fix(config): schema-validate the fork's real config/landing-zone.yaml in config-check and pre-commit`

---

## Task 7: Add the spoke hand-off to the AWS stand-up (ADO-5)

**Files:** `docs/runbooks/aws-bootstrap.md:274` (step 11).

- [ ] **Step 1: Replace step 11** with:

```markdown
11. **Apply `aws-workload-<env>`** *(per environment).* Queue a run on each
    `aws-workload-<env>` workspace. Each apply stands up that environment's spoke VPC,
    workload roles and per-account baseline, and creates a Transit Gateway attachment that
    waits in `pendingAcceptance`.

    **MANUAL HAND-OFF: wire each spoke into the hub.** Until this step the spoke has **no
    routing**. Only the network account (the Transit Gateway owner) can accept the
    attachment. Copy each workspace's `tgw_attachment_id` output into
    `config/landing-zone.yaml`, commit it, and apply `aws-network` again:

    ```yaml
    aws:
      network:
        spoke_attachments:
          dev: {attachment_id: tgw-attach-0123456789abcdef0, segment: nonprod}   # segment: prod | nonprod
    ```

    aws-network accepts the attachment, associates it with the `prod` or `nonprod` route
    table and propagates the spoke CIDR into the inspection table
    ([add an account, Step 4](aws-add-account.md#step-4--apply-the-layer)). Verify in the
    network account: `aws ec2 describe-transit-gateway-attachments --filters Name=state,Values=available`
    lists the spoke.
```

- [ ] **Step 2:** `make links`. **Commit:** `docs(aws-bootstrap): add the spoke_attachments hand-off after the first workload apply`

---

## Task 8: Put `gcp-guardrails` and the security team into the GCP stand-up (ADO-6)

**Files:** `docs/runbooks/bootstrap.md:13-24` and `:211-224`; `docs/guides/QUICK_START.md:12,55,190-191,247-250,277-283`.

- [ ] **Step 1: `bootstrap.md:13`** first sentence becomes "Where the AWS SRA spreads its foundation across seven layered roots, GCP uses **six roots**: five layered roots applied in order, plus the security-team root `gcp-guardrails` (see ...):". After item 5 add:

```markdown
6. **`envs/gcp/guardrails`** (workspace `gcp-guardrails`, security team only) applies the
   organization IAM deny policies, including admin containment. It reads no state; it
   looks up the org and the `containment/protected` tag that `gcp-organization` creates,
   so apply it after `gcp-organization`. See [Security team and gcp-guardrails](#security-team-and-gcp-guardrails).
```

- [ ] **Step 2: Add a section** to `bootstrap.md` after "Creating and wiring the TFC workspaces" (before "Standing up the first environment"):

```markdown
## Security team and gcp-guardrails

Setting `gcp.break_glass_group` (the scaffolder does) or marking any environment
`is_production: true` turns admin containment **on**, but `gcp-organization` only creates the
`containment/protected` tag. The deny policy itself is applied by `gcp-guardrails`, and
nothing applies it until the security team does:

1. An HCP Terraform organization owner creates a team for the security staff
   (**Settings > Teams > Create a team**) with no organization-level permissions, adds its
   members, and copies its ID (`team-...`).
2. Set `security_team_id = "team-..."` on tfc-admin. It must differ from `platform_team_id`
   and `control_plane_approvers_team_id`. Keep `enable_projects = true`. Apply tfc-admin. It
   puts `gcp-guardrails` in its own `<prefix>guardrails` project and grants only that team
   (a check warns while `security_team_id` is null).
3. Production estates: run `make bootstrap-ids` again so `tfc_workspace_ids` includes
   `gcp-guardrails`, then apply `gcp-bootstrap`. It binds the guardrails plan and apply
   service accounts to the workspace by its immutable ID.
4. After `gcp-organization` has applied, a security-team member queues a run on
   `gcp-guardrails` and confirms the apply.
5. Verify: `gcloud iam policies list --kind=denypolicies --attachment-point=cloudresourcemanager.googleapis.com%2Forganizations%2F<org-id>`
   lists the containment policy.

Details and the break-glass path: [production hardening](production-hardening.md).
```

- [ ] **Step 3: QUICK_START.** `:12` step 4 becomes: "**Bootstrap in order:** GCP `gcp-bootstrap` → `gcp-organization` → `gcp-guardrails` (security team) → `gcp-projects` → `gcp-network-hub` → `gcp-workload-<env>` (below)." `:55`: "the five GCP workspaces" becomes "the GCP workspaces (`gcp-bootstrap`, `gcp-organization`, `gcp-guardrails`, `gcp-projects`, `gcp-network-hub` and one `gcp-workload-<env>` per environment)". In the step-7 list (`:247-250`) insert after item 1: "2. `gcp-guardrails`: org IAM deny policies, applied by the security team (`[bootstrap runbook](../runbooks/bootstrap.md#security-team-and-gcp-guardrails)`)" and renumber. In the table at `:277-283` add a row after step 2: ``| 2a | `envs/gcp/guardrails` | `gcp-guardrails` | Org IAM deny policies (admin containment); security team only; after gcp-organization |``.

- [ ] **Step 4:** `make links`. **Commit:** `docs(gcp): add gcp-guardrails and the security team to the GCP stand-up`

---

## Task 9: State the HCP Terraform tier and cost model (ADO-13)

**Files:** `docs/guides/QUICK_START.md` (pre-flight, new subsection after `:55`), `README.md` (one line after the execution-model line at `:47`), `docs/known-gaps.md`.

- [ ] **Step 1: Verify against the live pricing page** (`https://www.hashicorp.com/products/terraform/pricing` and `https://developer.hashicorp.com/terraform/cloud-docs/overview`) which tiers include: teams with project-level custom permissions, policy sets (count and VCS source), health assessments, agents. Record the check date in the text.

- [ ] **Step 2: Add to QUICK_START** (pre-flight checklist):

```markdown
### HCP Terraform tier and cost

The landing zone uses these HCP Terraform features (verified against the pricing page on <date>):

| Feature | Used for | Where | Tier needed |
|---|---|---|---|
| Teams with project-level custom permissions | Platform, approvers, security, viewers, state backup | tfc-admin `*_team_id` | <fill from pricing page> |
| Two VCS-sourced OPA policy sets | Guardrails and the mandatory `destroy_guard` | tfc-admin `enable_policy_sets` (on by default for `standard` / `premium`) | Standard or Premium |
| Health assessments | Native drift detection | tfc-admin `enable_health_assessments` | <fill> |
| Agent pools | Node.js for Supabase vault secrets | `execution_mode = "agent"` | <fill> |

**Minimum for a production estate: Standard.** Free and Essentials can run the roots with
`enable_policy_sets = false` and `enable_health_assessments = false`, but then no policy
blocks a destructive change and the team separation may not be available; that is not a
supported production setup. Set `org.tfc.plan` so tfc-admin picks the right defaults.

**Cost.** Paid tiers bill per resource under management (RUM) per hour. Count it from a
sandbox apply: `terraform state list | wc -l` in each workspace. Until a sandbox has been
applied the count is unknown ([known gaps](../known-gaps.md)).
```

- [ ] **Step 3: README** after `:47`: `**HCP Terraform tier:** Standard or above for a production estate ([why](docs/guides/QUICK_START.md#hcp-terraform-tier-and-cost)).`

- [ ] **Step 4: known-gaps** entry: "**Resources-under-management count unknown.** Measure it on the first sandbox apply and publish per-root counts in QUICK_START."

- [ ] **Step 5:** `make links count-check`. **Commit:** `docs: state the minimum HCP Terraform tier and how resources under management are billed`

---

## Task 10: Make the scaffolder report what it invented (ADO-14)

**Files:** `scripts/init-landing-zone.sh:490-521`; `scripts/tests/test-init-landing-zone.sh`.

- [ ] **Step 1: Failing test.** In `test-init-landing-zone.sh`, inside the "a gcp-only run" block (after `assert_no_line "${log}" 'example\.com, ou:' ...`), add:

```bash
  assert_line "${log}" 'Derived, not verified' "derived values are reported"
  assert_line "${log}" 'gcp-organization-admins@acme\.com' "derived admin group is listed"
  assert_line "${log}" 'gcp-break-glass@acme\.com' "derived break-glass group is listed"
  assert_line "${log}" 'subnet_name: acme-dev-vpc-private-' "derived subnet name is listed"
```

Run `bash scripts/tests/test-init-landing-zone.sh`: the four new asserts FAIL.

- [ ] **Step 2: Implement.** After the `remaining=...` block in `init-landing-zone.sh`, add:

```bash
# Values the scaffolder derived from --domain / --prefix (group emails, the
# platform team's subnet). They look real but nothing checked that they exist.
derived="$(awk -v gcp="$(has_cloud gcp && echo 1 || echo 0)" -v admin="${GCP_ADMIN_EMAIL}" '
  /^[a-z_]+:/ { section = $1; sub(":", "", section) }
  /^[[:space:]]*#/ { next }
  section == "gcp" && gcp && /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/ && !/@example\.com/ {
    if (admin != "" && index($0, admin) > 0) next
    print NR ":" $0
  }
  section == "gcp" && gcp && /subnet_name:/ { print NR ":" $0 }
' "${OUTPUT}")"
```

and in the "Next steps" output, after the placeholder block:

```bash
if [[ -n "${derived}" ]]; then
  printf '     Derived, not verified (each group must exist in Cloud Identity and each\n'
  printf '     subnet in the environment before the first apply):\n'
  printf '%s\n' "${derived}" | sed 's/^/       line /'
fi
```

- [ ] **Step 3:** `bash scripts/tests/test-init-landing-zone.sh && make scaffold-fixtures-check shellcheck`. **Commit:** `fix(init): list the group emails and subnet names the scaffolder derived as unverified`

---

## Task 11: `make install` installs check-jsonschema; add `make ci-quick` (ADO-15)

**Files:** `scripts/setup.sh`; `Makefile:1,199-214`; `scripts/check-consistency.sh`.

- [ ] **Step 1: Failing check.** Add to `scripts/check-consistency.sh`:

```bash
echo "==> check-jsonschema pin agrees across CI, setup.sh and pre-commit"
cj_ci="$(grep -oE 'check-jsonschema==[0-9.]+' .github/workflows/terraform-plan.yml | head -1 | cut -d= -f3)"
cj_pc="$(awk '/check-jsonschema$/{f=1} f && /rev:/{print $2; exit}' .pre-commit-config.yaml)"
grep -q 'check-jsonschema' scripts/setup.sh || note "scripts/setup.sh does not install check-jsonschema"
[[ -z "${cj_pc}" || "${cj_pc}" == "${cj_ci}" ]] || note "check-jsonschema: CI ${cj_ci}, pre-commit ${cj_pc}"
```

`./scripts/check-consistency.sh` now fails on the setup.sh line.

- [ ] **Step 2: setup.sh.** After the Checkov block add:

```bash
# check-jsonschema (make config-check, pre-commit). Version single-sourced from CI.
REQUIRED_CHECK_JSONSCHEMA_VERSION="$(grep -oE 'check-jsonschema==[0-9.]+' \
  "$(dirname "${_TOOL_VERSIONS_FILE}")/.github/workflows/terraform-plan.yml" | head -1 | cut -d= -f3)"
cj_installed=$(installed_version check-jsonschema)
if [[ -z "$cj_installed" ]]; then
  echo "Installing check-jsonschema ${REQUIRED_CHECK_JSONSCHEMA_VERSION} ..."
  install_pip_package check-jsonschema "${REQUIRED_CHECK_JSONSCHEMA_VERSION}"
elif [[ "$cj_installed" != "$REQUIRED_CHECK_JSONSCHEMA_VERSION" ]]; then
  echo "WARNING: check-jsonschema $cj_installed is installed but $REQUIRED_CHECK_JSONSCHEMA_VERSION is required."
else
  echo "check-jsonschema $cj_installed OK"
fi
```

- [ ] **Step 3: Makefile.** Add `ci-quick` to `.PHONY` and replace `ci` with:

```make
ci-quick: ## Fast offline gates, no terraform init: fmt, consistency, config, scaffold fixtures, counts, links, refs, required checks, shellcheck, script tests, docs
	@$(MAKE) fmt-check
	@$(MAKE) consistency
	@$(MAKE) config-check
	@$(MAKE) scaffold-fixtures-check
	@$(MAKE) count-check
	@$(MAKE) links
	@$(MAKE) examples-refs
	@$(MAKE) required-checks
	@$(MAKE) shellcheck
	@$(MAKE) test-scripts
	@$(MAKE) docs-check

ci: ## Every local gate CI runs: ci-quick, then backend-check, validate-all, lint, test, security
	@$(MAKE) ci-quick
	@$(MAKE) backend-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) security
```

- [ ] **Step 4:** `./scripts/check-consistency.sh && make ci-quick`. **Commit:** `build: install check-jsonschema with make install and add a fast make ci-quick`

---

## Task 12: Complete the tooling checklist and CI secrets in QUICK_START (ADO-16, ADO-19)

**Files:** `docs/guides/QUICK_START.md:49-55,224-229`.

- [ ] **Step 1: Tooling list** (after `:54`) add:

```markdown
- [ ] `aws --version` reports AWS CLI v2 (AWS only: the phase-0 CloudFormation stack, StackSets and the account-quota pre-check)
- [ ] `gh --version` (repository secrets and variables, branch protection, numeric repository IDs)
- [ ] `python3 --version` reports 3.9 or later (repo scripts)
- [ ] `check-jsonschema --version` reports the version CI pins (`make install` installs it; `make config-check` needs it)
- [ ] Optional: `uv` (`make security` then runs the exact Checkov version CI uses)
```

- [ ] **Step 2: Step 6 table** (`:226-229`) becomes:

```markdown
| Name | Type | Value |
|------|------|-------|
| `TFC_ORGANIZATION` | Variable | Your Terraform Cloud org name |
| `TFC_TOKEN` | Secret (environment `tfc-readonly`) | A TFC team token with **Read runs** on the workspaces you tag for release metadata |
| `TFC_TOKEN_DRIFT` | Secret (environment `tfc-drift`) | A TFC team token with **Queue plans** and **Read state versions** on the workspaces drift detection checks. Without it, scheduled drift detection skips and a manual run fails |

Full list, scopes and the environment setup: [CI secrets](CI_SECRETS.md).
```

- [ ] **Step 3:** `make links`. **Commit:** `docs(quick-start): list the aws CLI, gh and check-jsonschema, and the TFC_TOKEN_DRIFT secret`

---

## Task 13: Minimum AWS footprint: `aws.layers` (ADO-17)

Implements Decision 3 (absent = all four optional layers).

**Files**
- Modify: `config/landing-zone.schema.json` (`aws.layers`), `config/landing-zone.example.yaml` (commented example).
- Modify: `envs/tfc-admin/variables.tf` (new `aws_layers`), `envs/tfc-admin/config.tf` (cfg key and effective local), `envs/tfc-admin/main.tf:305-317` (workspace filter).
- Modify: `envs/aws/organization/config.tf:171-182` (bind only present accounts).
- Create: `envs/tfc-admin/tests/fixtures/landing-zone-aws-minimal.yaml`, `envs/aws/organization/tests/fixtures/landing-zone-minimal.yaml`.
- Modify: `docs/architecture/provider-selection.md:65-72`, `docs/runbooks/aws-bootstrap.md` (stand-up order note).

- [ ] **Step 1: Failing tfc-admin test.** Fixture `landing-zone-aws-minimal.yaml`: copy `envs/tfc-admin/tests/fixtures/landing-zone.yaml`, set `aws.layers: []`. Add to `envs/tfc-admin/tests/config.tftest.hcl` (copy the variable nulls of the file's first run):

```hcl
run "aws_layers_empty_creates_only_organization_and_security" {
  command = plan
  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-aws-minimal.yaml"
  }
  assert {
    condition = alltrue([
      for ws in ["aws-network", "aws-identity", "aws-shared-services", "aws-backup"] : !contains(keys(local.workspaces), ws)
    ]) && contains(keys(local.workspaces), "aws-organization") && contains(keys(local.workspaces), "aws-security")
    error_message = "aws.layers: [] must create aws-organization and aws-security only (plus aws-workload-<env>)."
  }
}

run "aws_layers_absent_keeps_every_layer" {
  command = plan
  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  }
  assert {
    condition     = alltrue([for ws in ["aws-network", "aws-identity", "aws-shared-services", "aws-backup"] : contains(keys(local.workspaces), ws)])
    error_message = "Without aws.layers every AWS layer workspace must exist."
  }
}

run "aws_layers_rejects_unknown_layer" {
  command = plan
  variables {
    aws_layers = ["networking"]
  }
  expect_failures = [var.aws_layers]
}
```

Failing aws-organization test: fixture `landing-zone-minimal.yaml` (copy `envs/aws/organization/tests/fixtures/landing-zone.yaml`, keep only `log_archive`, `security_tooling`, `forensics` in `aws.accounts`, add `layers: []`). Add a run in the root's config suite with `command = plan` and that fixture, asserting `!contains(keys(local.tfc_workspace_bindings), "network")`. Run both suites: the tfc-admin runs fail ("Unsupported argument" for `aws_layers`), the aws-organization run fails on the `tfc_workspace_bindings` validation.

- [ ] **Step 2: Schema.** Under `properties.aws.properties` add:

```json
"layers": {
  "type": "array",
  "description": "Optional AWS layer workspaces to create besides aws-organization and aws-security. Absent = all four.",
  "items": {"enum": ["network", "identity", "shared-services", "backup"]},
  "uniqueItems": true
}
```

- [ ] **Step 3: tfc-admin variable.**

```hcl
variable "aws_layers" {
  description = "Optional AWS layer workspaces to create besides aws-organization and aws-security (always created when enable_aws): any of network, identity, shared-services, backup. aws-workload-<env> follows aws.workload_environments; without network, set enable_network_hub = false on those workspaces. Null = aws.layers from config/landing-zone.yaml, else all four."
  type        = list(string)
  default     = null

  validation {
    condition     = var.aws_layers == null || alltrue([for l in coalesce(var.aws_layers, []) : contains(["network", "identity", "shared-services", "backup"], l)])
    error_message = "aws_layers entries must be network, identity, shared-services or backup."
  }
}
```

`config.tf`: in `local.cfg` add `aws_layers = try([for l in local.lz.aws.layers : tostring(l)], null)`; in the effective locals add:

```hcl
  aws_layers = var.aws_layers != null ? var.aws_layers : (
    local.cfg.aws_layers != null ? local.cfg.aws_layers : ["network", "identity", "shared-services", "backup"]
  )
```

`main.tf` `local.workspaces` (first `for` in the `merge`, `:307-309`): change the filter to

```hcl
      if !e.per_environment && local.catalog_cloud_enabled[e.cloud] && (
        e.cloud != "aws" || contains(["aws-organization", "aws-security"], k) || contains(local.aws_layers, trimprefix(k, "aws-"))
      )
```

Run triggers, remote-state consumers and `speculative_disabled_workspaces` already skip names that are not managed (`main.tf:1409`, `:371`, variable description).

- [ ] **Step 4: aws-organization bindings.** In `envs/aws/organization/config.tf:173-182`, filter the derived map to account keys that exist: add `if contains(keys(merge(<effective accounts>, <effective workload_accounts>)), acct)` to the `for acct in distinct(...)` expression, using the root's effective account locals (find them with `grep -n 'accounts *=' envs/aws/organization/config.tf`).

- [ ] **Step 5: Docs.** `provider-selection.md` "Minimum AWS footprint" becomes:

````markdown
### Minimum AWS footprint

The minimum governed, monitored AWS baseline is `aws-organization` + `aws-security`, with
three member accounts (`log_archive`, `security_tooling`, `forensics`) plus the management
account. Ask tfc-admin for only those workspaces:

```yaml
aws:
  layers: []            # any of: network, identity, shared-services, backup (absent = all four)
  accounts:             # keep only the accounts the chosen layers need
    log_archive: {email: ..., ou: Security}
    security_tooling: {email: ..., ou: Security}
    forensics: {email: ..., ou: Security}
```

`network` needs the `network` account, `identity` and `shared-services` need
`shared_services`, `backup` needs `backup`. Workload environments without `network` run a
standalone VPC (`enable_network_hub = false` on `aws-workload-<env>`).
````

In `aws-bootstrap.md` step list (`:268-276`) add to steps 7-10: "(skip if not in `aws.layers`)".

- [ ] **Step 6: Run and pass.** `make test TEST_DIRS="envs/tfc-admin envs/aws/organization" TERRAFORM=$TF && make config-check links`.

- [ ] **Step 7: CHANGELOG** "Added": `aws.layers` / tfc-admin `aws_layers`. **Commit:** `feat(tfc-admin): select optional AWS layer workspaces with aws.layers for a minimum footprint`

---

## Task 14: Presets for VCS-driven runs (ADO-18)

The repo already has the VCS route: `config/tfc-workspaces.yaml`, which tfc-admin writes as workspace variables. Document it per preset instead of writing six more YAML twins and loaders.

**Files:** `examples/presets/README.md:5-13,58-63`.

- [ ] **Step 1: Replace the opening paragraph** (`:3-5`) with:

```markdown
# Presets

Ready-to-use overlays. A local plan takes them with `-var-file`. **VCS-driven HCP Terraform
runs never see a `-var-file`**, so for those, copy the preset's variables into
`config/tfc-workspaces.yaml` under the workspace name; tfc-admin writes them as workspace
variables on its next apply. `prod-gcp-workload` also has a YAML twin that the config file
can name directly (see below).
```

- [ ] **Step 2: Add after the hardening table:**

````markdown
### The same presets in `config/tfc-workspaces.yaml`

```yaml
workspaces:
  gcp-network-hub:            # prod-gcp-network-hub.tfvars
    vpc_sc_enable_dry_run: false
  aws-network:                # nonprod-aws-network.tfvars (a non-production estate)
    az_count: 2
    enable_network_firewall: false
  gcp-bootstrap:              # prod-gcp-bootstrap.tfvars: the local phase-0 apply reads tfvars,
    enable_github_wif: false  # so this entry matters only once gcp-bootstrap runs remotely
    enable_pam: true
    enable_phase0_admin_impersonation: false
```

`gcp_overrides` (gcp-organization) and `aws_overrides` (aws-security) are object variables:
put **all** of your keys in one entry, because the workspace variable replaces the whole
object. tfc-admin rejects entries for the security-only `gcp-guardrails` workspace.
````

- [ ] **Step 3:** `./scripts/check-consistency.sh` (it already checks preset keys and doc references) and `make links`. **Commit:** `docs(presets): show how to apply each preset to VCS-driven runs through config/tfc-workspaces.yaml`

---

## Task 15: Pre-check the AWS account quota (ADO-20)

**Files:** create `scripts/aws-preflight.sh`, `scripts/tests/test-aws-preflight.sh`; modify `docs/runbooks/aws-bootstrap.md` prerequisites (`:26-34`), `docs/runbooks/aws-add-account.md` Step 1, `Makefile` (target `aws-preflight`).

- [ ] **Step 1: Failing test** `scripts/tests/test-aws-preflight.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/aws-preflight.sh (offline: --quota).
#   bash scripts/tests/test-aws-preflight.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/aws-preflight.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

cfg="${workdir}/lz.yaml"
cat >"${cfg}" <<'YAML'
org:
  name: acme
aws:
  enabled: true
  accounts:
    log_archive: {email: a@acme.io, ou: Security}
    security_tooling: {email: b@acme.io, ou: Security}
    network: {email: c@acme.io, ou: Infrastructure}
    shared_services: {email: d@acme.io, ou: Infrastructure}
    backup: {email: e@acme.io, ou: Infrastructure}
    forensics:
      email: f@acme.io
      ou: Security
  workload_accounts:
    workload_dev: {email: g@acme.io, ou: Workloads}
    workload_prod: {email: h@acme.io, ou: Workloads}
YAML

expect() { # expect <label> <rc> <args...>
  local label="$1" want="$2" rc=0; shift 2
  bash "${SCRIPT}" --config "${cfg}" "$@" >"${workdir}/out" 2>&1 || rc=$?
  if [[ "${rc}" -eq "${want}" ]]; then ok "${label}"; else bad "${label} (rc=${rc}, want ${want})"; cat "${workdir}/out" >&2; fi
}
expect "9 accounts fit a quota of 10" 0 --quota 10
grep -q 'headroom 1' "${workdir}/out" && ok "headroom reported" || bad "headroom reported"
expect "9 accounts exceed a quota of 8" 1 --quota 8
expect "no headroom warns but passes" 0 --quota 9
grep -q 'WARNING' "${workdir}/out" && ok "no-headroom warning" || bad "no-headroom warning"

printf 'test-aws-preflight: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

- [ ] **Step 2: Create `scripts/aws-preflight.sh`:**

```bash
#!/usr/bin/env bash
# AWS stand-up pre-flight: the organization's account quota must hold the
# management account plus every account in aws.accounts and aws.workload_accounts.
# A new organization's default quota is small (10 at the time of writing), and
# aws-organization creates every listed account in one apply.
#
#   scripts/aws-preflight.sh [--config FILE] [--quota N]   (make aws-preflight)
#
# Without --quota it asks AWS with management-account credentials. Confirm the
# quota code first with:
#   aws service-quotas list-service-quotas --service-code organizations --region us-east-1
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/config/landing-zone.yaml"
QUOTA=""
QUOTA_CODE="${AWS_ORG_ACCOUNT_QUOTA_CODE:-L-29A0C5DF}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --quota) QUOTA="$2"; shift 2 ;;
    *) echo "usage: $0 [--config FILE] [--quota N]" >&2; exit 2 ;;
  esac
done
[[ -f "${CONFIG}" ]] || { echo "aws-preflight: ${CONFIG} not found" >&2; exit 2; }

# Count account keys (indent 4) under aws.accounts and aws.workload_accounts.
planned="$(awk '
  /^[a-z_]+:/ { sec = $1; sub_ = ""; next }
  sec == "aws:" && /^  [a-z_]+:/ { sub_ = $1; next }
  sec == "aws:" && (sub_ == "accounts:" || sub_ == "workload_accounts:") && /^    [a-z0-9_-]+:/ { n++ }
  END { print n + 0 }
' "${CONFIG}")"
required=$((planned + 1)) # + the management account

if [[ -z "${QUOTA}" ]]; then
  QUOTA="$(aws service-quotas get-service-quota --region us-east-1 --service-code organizations \
    --quota-code "${QUOTA_CODE}" --query 'Quota.Value' --output text 2>/dev/null ||
    aws service-quotas get-aws-default-service-quota --region us-east-1 --service-code organizations \
      --quota-code "${QUOTA_CODE}" --query 'Quota.Value' --output text)"
  QUOTA="${QUOTA%%.*}"
fi

headroom=$((QUOTA - required))
echo "aws-preflight: ${required} accounts needed (management + ${planned} in config), quota ${QUOTA}, headroom ${headroom}"
if (( headroom < 0 )); then
  echo "aws-preflight: FAIL. Request an increase before applying aws-organization:" >&2
  echo "  aws service-quotas request-service-quota-increase --region us-east-1 --service-code organizations --quota-code ${QUOTA_CODE} --desired-value <n>" >&2
  exit 1
fi
if (( headroom == 0 )); then
  echo "aws-preflight: WARNING: no headroom; the next workload account needs a quota increase." >&2
fi
```

`chmod +x`. Makefile: `aws-preflight: ## Check the AWS account quota fits config/landing-zone.yaml (management-account credentials)` with recipe `@./scripts/aws-preflight.sh`.

- [ ] **Step 3: Docs.** Add to the `aws-bootstrap.md` prerequisites:

```markdown
- [ ] **Account quota.** `aws-organization` creates every account in `aws.accounts` and
  `aws.workload_accounts` in one apply, and a new organization's default account quota is
  small. After Step 1, run `make aws-preflight` with management-account credentials; request
  an increase (it can take days) if it fails or warns. For the smallest estate see
  [minimum AWS footprint](../architecture/provider-selection.md#minimum-aws-footprint).
```

and in `aws-add-account.md` Step 1: "Run `make aws-preflight` first: one more account needs one more slot in the quota."

- [ ] **Step 4:** `bash scripts/tests/test-aws-preflight.sh && make shellcheck links`. **Commit:** `feat(scripts): add an AWS account-quota pre-flight and call it from the AWS runbooks`

---

## Task 16: Correct the stale VPN statements (ADO-21)

**Files:** `docs/guides/QUICK_START.md:364` (already replaced by Task 4; check it is gone), `README.md:154`, `docs/architecture/gcp-landing-zone.md:127,174,217`.

- [ ] **Step 1: `README.md:154`** GCP cell becomes: ``[`network/vpn`](modules/gcp/network/vpn/) (HA VPN on the hub; `gcp.network.vpn` + `vpn_shared_secret_wo` on `gcp-network-hub`)``, and the AWS cell becomes ``[`network/vpn`](modules/aws/network/vpn/) (Site-to-Site on the Transit Gateway; `aws.network.vpn`)`` (Task 17's check confirms it is wired, so it loses the library-only mark).

- [ ] **Step 2: `gcp-landing-zone.md:127`** becomes: "- **Hybrid (opt-in, off by default).** HA VPN and Dedicated/Partner Interconnect attach to the **hub** VPC through `gcp-network-hub` (`gcp.network.vpn`, `gcp.network.interconnect`; the pre-shared key is the write-only `vpn_shared_secret_wo`). Packet mirroring and internal load balancers are library modules you compose yourself." At `:174` replace `` `enable_vpn` `` with `` `gcp.network.vpn.enabled` ``; at `:217` replace "HA-VPN (`enable_vpn`)" with "HA VPN (`gcp.network.vpn.enabled`)".

- [ ] **Step 3: Guard.** `grep -rn 'enable_vpn' docs README.md | grep -v aws` must return nothing GCP-related; `grep -rn 'does not pass them through' docs` returns nothing. `make links`. **Commit:** `docs: describe GCP HA VPN as the config-driven hub feature it is`

---

## Task 17: README library-only labels checked against the module graph (ADO-22)

**Files:** `scripts/check-module-usage.py`; `scripts/tests/test-check-module-usage.sh`; `README.md:154,244,282-295`.

- [ ] **Step 1: Failing test.** Append to `scripts/tests/test-check-module-usage.sh` (before the summary):

```bash
# README cross-check: library-only labels must match the module graph.
lib_readme() { # lib_readme <tree> <table rows...>
  {
    printf '<details>\n<summary><strong>Library-only modules</strong></summary>\n\n| Module | Why |\n|---|---|\n'
    shift; for r in "$@"; do printf '%s\n' "$r"; done
    printf '\n</details>\n'
  } >"$1/README.md"
}
t="$(new_tree readme_ok)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
lib_readme "${t}" '| [`orphan`](modules/orphan/) | not wired |'
expect_rc "README listing exactly the unwired modules passes" 0 "${t}"

t="$(new_tree readme_wired)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
lib_readme "${t}" '| [`orphan`](modules/orphan/) | x |' '| [`used`](modules/used/) | wrongly listed |'
expect_rc "README labelling a wired module library-only fails" 1 "${t}"
grep -q 'modules/used' "${workdir}/out" && ok "wired module named" || bad "wired module named"

t="$(new_tree readme_missing)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
lib_readme "${t}"
expect_rc "README missing an unwired module fails" 1 "${t}"
```

Run: the last two report FAIL.

- [ ] **Step 2: Implement** in `scripts/check-module-usage.py`, before the final `if "--check" ...`:

```python
    # README.md cross-check: every module README.md labels "(library-only)" or lists
    # in the "Library-only modules" table must be unwired, and every unwired module
    # must be in that table. Skipped when the tree has no README.md (tests).
    readme = ROOT / "README.md"
    readme_errors: list[str] = []
    if readme.is_file():
        text = readme.read_text(encoding="utf-8", errors="replace")
        link = re.compile(r"\]\((modules/[^)#]+?)/?\)")
        marked: set[str] = set()
        for line in text.splitlines():
            # The module a "*(library-only)*" mark belongs to is the last link before it.
            for segment in line.split("*(library-only)*")[:-1]:
                found = link.findall(segment)
                if found:
                    marked.add(found[-1])
        section = ""
        if "Library-only modules" in text:
            section = text.split("Library-only modules", 1)[1].split("</details>", 1)[0]
        table = {
            path
            for line in section.splitlines() if line.startswith("| [")
            for path in link.findall(line.split("|")[1])
        }
        unwired = {rel(m) for m in modules - wired}
        for m in sorted((marked | table) - unwired):
            readme_errors.append(f"README.md labels {m} library-only, but an envs/** root composes it")
        for m in sorted(unwired - table):
            readme_errors.append(f"{m} is not wired into any root but is missing from README.md's Library-only table")
        for e in readme_errors:
            print(f"check-module-usage: {e}", file=sys.stderr)
```

Declare `readme_errors: list[str] = []` before the `if readme.is_file():` line, and change the final check to `if "--check" in sys.argv[1:] and (unreferenced or readme_errors):` (print the existing FAIL hint only when `unreferenced` is non-empty) and `return 1`.

- [ ] **Step 3: Fix README.** Remove the `gcp/network/app-ingress` row and `aws/network/vpn` row from the Library-only table (`:290,294`); change the alert-policy row (`:288`) to list only `compute-dashboard`; remove the `*(library-only)*` marks at `:154` (AWS vpn, done in Task 16) and `:244` (alert-policy); update the `:244` cell to say "used by `net-hub` / `net-spoke` data-plane alerts".

- [ ] **Step 4:** `bash scripts/tests/test-check-module-usage.sh && make count-check`. **Commit:** `fix(docs): check README library-only labels against the module graph and correct three`

---

## Task 18: GCP root counts that cannot drift (ADO-23)

**Files:** `scripts/check-docs-counts.sh`; `scripts/tests/test-check-docs-counts.sh`; `README.md:92,97,347`; `docs/INDEX.md:14,90,150,151`; `docs/runbooks/bootstrap.md:13,25`; `docs/architecture/gcp-landing-zone.md:7,60`; `docs/architecture/ARCHITECTURE.md:58`; `docs/guides/QUICK_START.md:408`.

- [ ] **Step 1: Failing test.** In `test-check-docs-counts.sh` add:

```bash
t="$(new_tree stalegcp '**Reference landing zone**')"
sed -i.bak 's|envs/gcp/\*<br/>1 roots|envs/gcp/*<br/>5 roots|' "${t}/README.md"
if run "${t}"; then bad "wrong GCP root count fails"; else ok "wrong GCP root count fails"; fi

t="$(new_tree fiveroot '**Reference landing zone**')"
printf 'the five-root layer map\n' >"${t}/docs/x.md"
if run "${t}"; then bad "spelled-out stale count fails"; else ok "spelled-out stale count fails"; fi
```

- [ ] **Step 2: Implement** in `check-docs-counts.sh` after the existing `expect` lines:

```bash
gcp_roots="$(./scripts/terraform-roots.sh envs | grep -c '^envs/gcp/' || true)"
aws_roots="$(./scripts/terraform-roots.sh envs | grep -c '^envs/aws/' || true)"
expect README.md "envs/gcp/*<br/>${gcp_roots} roots" "GCP root count in the architecture diagram"
expect README.md "envs/aws/*<br/>${aws_roots} layered roots" "AWS root count in the architecture diagram"
# Spelled-out GCP root counts drift silently; the numeric ones above are checked.
stale="$(grep -rnE 'five-root|five roots|5 roots|two-root layer map|all five GCP roots|five GCP workspaces' \
  README.md CLAUDE.md docs --include='*.md' 2>/dev/null | grep -v '^docs/audit/' || true)"
if [ -n "$stale" ]; then
  echo "::error::Stale GCP root count (there are ${gcp_roots} GCP roots; write the digit next to a checked figure, or name the roots):"
  printf '%s\n' "$stale"
  fail=1
fi
```

Add `printf 'gcp roots: %s, aws roots: %s\n'` to the `--print` branch.

- [ ] **Step 3: Fix the docs.** `README.md:92` `5 roots` becomes `6 roots`. `README.md:97`: "GCP uses **6** roots (five layered roots plus the security-team `gcp-guardrails`) where the AWS SRA spreads across **7**." `README.md:347`, `INDEX.md:90,150`: "five-root layer map" becomes "layer map". `INDEX.md:151`: "split into five roots/states" becomes "split into separate roots and states". `INDEX.md:14`: "GCP is five layered roots, applied in order:" becomes "GCP is five layered roots plus the security-team `gcp-guardrails`, applied in order:" (no banned phrase). `bootstrap.md:13` is done in Task 8; `bootstrap.md:25` "across the five roots" becomes "across the GCP roots". `gcp-landing-zone.md:7` "GCP uses **five roots**" becomes "GCP uses five layered roots plus the security-team `gcp-guardrails`"; `:60` "Five GCP roots" becomes "The GCP roots". `ARCHITECTURE.md:58` "two-root layer map" becomes "layer map". `QUICK_START.md:408` "all five GCP roots (`bootstrap`, `organization`, `projects`, `network-hub`, `workload`)" becomes "every GCP root (`bootstrap`, `organization`, `guardrails`, `projects`, `network-hub`, `workload`)".

- [ ] **Step 4:** `bash scripts/tests/test-check-docs-counts.sh && make count-check links`. **Commit:** `docs: count six GCP roots and fail CI on a stale spelled-out root count`

---

## Task 19: Fix the null-provider note and the `make ci` descriptions (ADO-24, ADO-25)

Depends on Task 11.

**Files:** `docs/guides/QUICK_START.md:133,425`; `README.md:302`; `CLAUDE.md` (the `make ci` line in "Makefile Quick Reference").

- [ ] **Step 1: `QUICK_START.md:133`** becomes:

```markdown
> **Note on `modules/saas/stages/saas-workload`:** the stage declares the `supabase` and `vercel` providers in `required_providers`. Terraform resolves `required_providers` at init regardless of feature flags, so the calling root must configure **both** even when `enable_vercel = false` ([single-provider mode](../architecture/provider-selection.md#single-provider-mode-in-the-saas-root)). To use Supabase with no Vercel provider at all, call `modules/supabase/environment` directly.
```

- [ ] **Step 2: `make ci` lines.** `CLAUDE.md` Makefile block: replace the `make ci` line with two lines:

```bash
make ci-quick       # fast offline gates (no terraform init): fmt, consistency, config, fixtures, counts, links, refs, required checks, shellcheck, script tests, docs
make ci             # ci-quick + backend-check + validate-all + lint + test + security (every gate CI runs)
```

`README.md:302`: `make ci                    # Every local gate CI runs (make ci-quick for the fast offline subset)`. `QUICK_START.md:425` row: ``| `make ci` | Every local gate CI runs; `make ci-quick` runs the fast offline subset |``.

- [ ] **Step 3: Guard.** Add to `check-docs-counts.sh`: `expect CLAUDE.md "make ci-quick" "CLAUDE.md lists ci-quick"`. Run `./scripts/check-docs-counts.sh && make links`. **Commit:** `docs: correct the saas-workload provider note and the make ci descriptions`

---

## Task 20: Plan targets for every root (ADO-26)

**Files:** `Makefile` (`help` awk, new targets, `.PHONY`); `README.md` Commands block; `docs/guides/QUICK_START.md` section 9.

- [ ] **Step 1: Failing check** (a shell assertion you run, then keep as `scripts/tests/test-make-plan-targets.sh`):

```bash
#!/usr/bin/env bash
# make plan-<cloud>-<root> resolves to a read-only plan of the right root.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }
for r in bootstrap guardrails projects network-hub; do
  make -n "plan-gcp-${r}" | grep -q "chdir=envs/gcp/${r} plan" && ok "plan-gcp-${r}" || bad "plan-gcp-${r}"
done
for r in organization security network identity shared-services backup; do
  make -n "plan-aws-${r}" | grep -q "chdir=envs/aws/${r} plan" && ok "plan-aws-${r}" || bad "plan-aws-${r}"
done
make -n plan-aws-workload APP_ENV=dev | grep -q 'TF_WORKSPACE=aws-workload-dev' && ok "plan-aws-workload" || bad "plan-aws-workload"
if make plan-aws-bogus >/dev/null 2>&1; then bad "unknown root refused"; else ok "unknown root refused"; fi
make help | grep -q 'plan-aws-%' && ok "help lists plan-aws-%" || bad "help lists plan-aws-%"
printf 'test-make-plan-targets: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

- [ ] **Step 2: Makefile.** Add:

```make
GCP_PLAN_ROOTS := bootstrap organization guardrails projects network-hub
AWS_PLAN_ROOTS := organization security network identity shared-services backup

plan-aws-workload: ## Plan aws-workload-<APP_ENV> in HCP Terraform (read-only)
	@TF_WORKSPACE=aws-workload-$(APP_ENV) $(TERRAFORM) -chdir=envs/aws/workload plan

plan-gcp-%: ## Plan a GCP root in HCP Terraform (read-only): make plan-gcp-projects
	@case " $(GCP_PLAN_ROOTS) " in *" $* "*) ;; *) echo "Unknown GCP root '$*': one of $(GCP_PLAN_ROOTS), or plan-gcp-workload"; exit 1 ;; esac
	@$(TERRAFORM) -chdir=envs/gcp/$* plan

plan-aws-%: ## Plan an AWS layer root in HCP Terraform (read-only): make plan-aws-network
	@case " $(AWS_PLAN_ROOTS) " in *" $* "*) ;; *) echo "Unknown AWS root '$*': one of $(AWS_PLAN_ROOTS), or plan-aws-workload"; exit 1 ;; esac
	@$(TERRAFORM) -chdir=envs/aws/$* plan
```

Change the `help` awk pattern from `/^[a-zA-Z0-9_.-]+:.*?##/` to `/^[a-zA-Z0-9_.%-]+:.*?##/`. Keep the explicit `plan-gcp-organization` and `plan-gcp-workload` (explicit rules win over the pattern).

- [ ] **Step 3: Docs.** README Commands block: add `make plan-gcp-<root>` / `make plan-aws-<root>` / `make plan-aws-workload APP_ENV=dev` lines. QUICK_START section 9: one line "Any root: `make plan-gcp-<root>` or `make plan-aws-<root>` (a read-only plan in HCP Terraform)."

- [ ] **Step 4:** `bash scripts/tests/test-make-plan-targets.sh`. **Commit:** `build: add read-only plan targets for every GCP and AWS root`

---

## Task 21: Release metadata for `gcp-guardrails` (ADO-27)

Implements Decision 4, option A.

**Files:** `.github/workflows/terraform-apply.yml:11-19,84-97` and the token step; `envs/tfc-admin/variables.tf`, `envs/tfc-admin/main.tf:736-760,848-850`; `envs/tfc-admin/tests/root.tftest.hcl`; `docs/guides/CI_SECRETS.md`; `README.md:323`.

- [ ] **Step 1: Failing tfc-admin test:**

```hcl
run "guardrails_release_reader_gets_read_runs_only" {
  command = plan
  variables {
    guardrails_release_reader_team_id = "team-guardrelease1"
  }
  assert {
    condition     = local.team_project_access["guardrails/release-reader"].custom.runs == "read" && local.team_project_access["guardrails/release-reader"].custom.state_versions == "none" && local.team_project_access["guardrails/release-reader"].custom.variables == "none"
    error_message = "The guardrails release reader may read runs and nothing else."
  }
}
```

(Use the real local name that holds the map built at `main.tf:820-858`; find it with `grep -n '"guardrails/security"' -B30 envs/tfc-admin/main.tf | grep '= merge('`.)

- [ ] **Step 2: tfc-admin.** Variable:

```hcl
variable "guardrails_release_reader_team_id" {
  description = "TFC team ID (team-...) whose token (GitHub secret TFC_TOKEN_GUARDRAILS) verifies gcp-guardrails runs for release tags: runs = read on the guardrails project, no state or variables. Must differ from every other team input. Null = no grant (gcp-guardrails/v* tags then fail verification)."
  type        = string
  default     = null
  validation {
    condition     = var.guardrails_release_reader_team_id == null || can(regex("^team-[A-Za-z0-9]+$", var.guardrails_release_reader_team_id))
    error_message = "guardrails_release_reader_team_id must be a TFC team ID (team-...)."
  }
}
```

Local `release_reader_custom_access = { runs = "read", variables = "none", state_versions = "none", sentinel_mocks = "none", locking = false }` next to `security_custom_access`, and in the access map after `"guardrails/security"`:

```hcl
    var.guardrails_release_reader_team_id == null || !local.guardrails_project ? {} : {
      "guardrails/release-reader" = { project = "guardrails", team_id = var.guardrails_release_reader_team_id, access = "custom", custom = local.release_reader_custom_access }
    },
```

Add `var.guardrails_release_reader_team_id` to the distinct-team checks at `main.tf:945-960`.

- [ ] **Step 3: Workflow.** Add `- "gcp-guardrails/v*"` to `on.push.tags`; add `|| "$TAG_NAME" == gcp-guardrails/*` to the single-root branch (`:84`); update the error text (`:93`) to `gcp-{bootstrap,organization,guardrails,projects,network-hub}/v*`. In the credential-assert step and every later step that reads `secrets.TFC_TOKEN`, use `${{ startsWith(github.ref_name, 'gcp-guardrails/') && secrets.TFC_TOKEN_GUARDRAILS || secrets.TFC_TOKEN }}`.

- [ ] **Step 4: Docs.** `CI_SECRETS.md` table row: ``| `TFC_TOKEN_GUARDRAILS` | Secret (environment `tfc-readonly`) | `terraform-apply.yml` | Token of the team set as tfc-admin `guardrails_release_reader_team_id`: runs = read on the guardrails project only. Needed only for `gcp-guardrails/v*` tags. |``. README `:323` tag list adds `gcp-guardrails/v*`.

- [ ] **Step 5:** `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`; `actionlint .github/workflows/terraform-apply.yml` if installed, else `pre-commit run check-yaml --files .github/workflows/terraform-apply.yml`; `make required-checks links`. **Commit:** `feat(release): accept gcp-guardrails deployment tags with a guardrails-only read token`

---

## Task 22: A security contact that works (ADO-28)

**Files:** `SECURITY.md:5-15,108-114`; create `scripts/check-security-contact.sh`; `Makefile` (`security-contact-live`); `docs/guides/BRANCH_PROTECTION.md` (operator checklist line).

- [ ] **Step 1: Operator action (repository admin, not an agent).** Settings > Code security > **Private vulnerability reporting: Enable**, or `gh api -X PUT repos/<owner>/<repo>/private-vulnerability-reporting`. Record who did it and when in the PR description.

- [ ] **Step 2: `scripts/check-security-contact.sh`:**

```bash
#!/usr/bin/env bash
# Live check: the reporting channel SECURITY.md names is switched on.
#   scripts/check-security-contact.sh [owner/repo]   (make security-contact-live; needs gh auth)
set -euo pipefail
repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
enabled="$(gh api "repos/${repo}/private-vulnerability-reporting" --jq .enabled)"
if [[ "${enabled}" != "true" ]]; then
  echo "SECURITY.md names GitHub private vulnerability reporting, but it is OFF on ${repo}." >&2
  echo "Enable it: gh api -X PUT repos/${repo}/private-vulnerability-reporting" >&2
  exit 1
fi
echo "check-security-contact: private vulnerability reporting is on for ${repo}"
```

Prove it: before Step 1 it exits 1 on this repo; after Step 1 it exits 0. Makefile: `security-contact-live: ## Fail if GitHub private vulnerability reporting is off (needs gh auth)` with `@./scripts/check-security-contact.sh`.

- [ ] **Step 3: SECURITY.md.** Replace `:5-15` with:

```markdown
**Do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities through the repository's **Security** tab, **Report a vulnerability**
(GitHub private vulnerability reporting). It is the only channel; there is no security
email address. It reaches the maintainers directly and confidentially. We aim to
acknowledge within 48 hours and keep you informed of progress. Maintainers:
`make security-contact-live` checks that the channel is switched on.

**Forks:** private vulnerability reporting is a per-repository setting. Switch it on in your
fork, or replace this section with your own channel.
```

Replace the "Contact" bullets at `:110-114` with: "- Security issues: the **Report a vulnerability** button above. - General questions: open a non-security issue on this repository."

- [ ] **Step 4:** `make links shellcheck`. **Commit:** `docs(security): name only the reporting channel that exists and add a live check for it`

---

## Task 23: Allowlists for `any` inputs generated from one place and checked against the stage types (IAC-4)

**Files**
- Create: `allowed_keys.tf` in `envs/gcp/workload`, `envs/gcp/network-hub`, `envs/aws/network`, `modules/gcp/stages/environment`.
- Modify: the validations of `envs/gcp/workload/variables.tf` (`additional_regions`, `app_services`, `vm_backup_schedules`, `os_patch_deployments`), `modules/gcp/stages/environment/variables.tf` (`app_services`), `envs/aws/network/variables.tf` (`vpn`); add validations to `envs/gcp/network-hub/variables.tf` (`vpn`, `interconnects`, `hub_additional_regions`).
- Create: `scripts/check-any-allowlists.py`, `scripts/any-allowlists.json`, `scripts/tests/test-check-any-allowlists.sh`.
- Modify: `scripts/check-consistency.sh`.

- [ ] **Step 1: Failing test** `scripts/tests/test-check-any-allowlists.sh`:

```bash
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
printf 'variable "things" {\n  type    = any\n  default = null\n}\n' >"${t}/envs/r/variables.tf"
cat >"${t}/scripts/any-allowlists.json" <<'JSON'
{"allowlists": [
  {"owner": "envs/r", "variable": "things", "path": "self", "stage": "modules/s", "stage_variable": "things"},
  {"owner": "envs/r", "variable": "things", "path": "sub", "stage": "modules/s", "stage_variable": "things"}
], "exempt": []}
JSON
write_keys() { printf 'locals {\n  allowed_keys = {\n    things = {\n      self = [%s]\n      sub  = ["x", "y"]\n    }\n  }\n}\n' "$1" >"${t}/envs/r/allowed_keys.tf"; }
check() { python3 -I "${SCRIPT}" "${t}" >"${workdir}/out" 2>&1; }

write_keys '"a", "sub"'
if check; then ok "matching allowlist passes"; else bad "matching allowlist passes"; cat "${workdir}/out" >&2; fi

write_keys '"a", "sub", "typo"'
if check; then bad "allowlist key the stage lacks fails"; else ok "allowlist key the stage lacks fails"; fi
grep -q 'typo' "${workdir}/out" && ok "extra key named" || bad "extra key named"

write_keys '"a"'
if check; then bad "stage attribute missing from allowlist fails"; else ok "stage attribute missing from allowlist fails"; fi

write_keys '"a", "sub"'
printf 'variable "other" {\n  type = any\n}\n' >>"${t}/envs/r/variables.tf"
if check; then bad "uncovered any input fails"; else ok "uncovered any input fails"; fi

if python3 -I "${SCRIPT}" >/dev/null 2>&1; then ok "repo passes"; else bad "repo passes"; fi
printf 'test-check-any-allowlists: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
```

- [ ] **Step 2: Create `scripts/check-any-allowlists.py`:**

```python
#!/usr/bin/env python3
"""Fail when a key allowlist for an untyped (`type = any`) input drifts from the
typed object it is forwarded to, or when an `any` input has no allowlist.

An `any` input keeps a misspelled key visible, and a root validation rejects
keys outside an allowlist. If the allowlist names a key the downstream object
type does not declare, type conversion drops it silently. If the downstream
type gains an attribute the allowlist lacks, nobody can set it.

Allowlists live in <owner>/allowed_keys.tf:
    locals { allowed_keys = { <variable> = { <path> = ["key", ...] } } }
<path> is "self" for the top level or a dotted attribute path. The manifest
(scripts/any-allowlists.json) maps each (owner, variable, path) to the stage
variable whose type must match, and lists exempt `any` inputs with a reason.

Usage: scripts/check-any-allowlists.py [ROOT] [MANIFEST]
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
MANIFEST = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "scripts" / "any-allowlists.json"
SKIP = {".terraform", "tests", "examples", ".git"}
TOKEN = re.compile(r'\s+|#[^\n]*|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_-]*|-?[0-9][0-9.]*|.', re.S)
WRAPPERS = {"map", "list", "set", "optional"}


def tokens(text: str) -> list[str]:
    out = []
    for m in TOKEN.finditer(text):
        t = m.group(0)
        if t.isspace() or t.startswith(("#", "//", "/*")):
            continue
        out.append(t)
    return out


class Parser:
    def __init__(self, toks: list[str]):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self, want=None):
        tok = self.peek()
        if want is not None and tok != want:
            raise SyntaxError(f"expected {want!r}, got {tok!r}")
        self.i += 1
        return tok

    def seq(self, close: str):
        items = []
        while self.peek() != close:
            items.append(self.expr())
            if self.peek() == ",":
                self.take()
        self.take(close)
        return items

    def expr(self):
        tok = self.take()
        if tok == "{":
            obj = {}
            while self.peek() != "}":
                key = self.take().strip('"')
                if self.peek() in ("=", ":"):
                    self.take()
                obj[key] = self.expr()
                if self.peek() == ",":
                    self.take()
            self.take("}")
            return ("obj", obj)
        if tok == "[":
            return ("list", self.seq("]"))
        if self.peek() == "(":
            self.take("(")
            return ("call", tok, self.seq(")"))
        return ("lit", tok[1:-1] if tok.startswith('"') else tok)


def variable_type(path: Path, name: str):
    text = path.read_text(encoding="utf-8")
    m = re.search(r'^variable\s+"%s"\s*\{' % re.escape(name), text, re.M)
    if not m:
        raise LookupError(f"{path}: no variable {name!r}")
    nxt = re.compile(r"^variable\s+\"", re.M).search(text, m.end())
    end = nxt.start() if nxt else len(text)
    t = re.compile(r"^\s*type\s*=", re.M).search(text, m.end(), end)
    if not t:
        raise LookupError(f"{path}: variable {name!r} has no type")
    return Parser(tokens(text[t.end():end])).expr()


def attributes(node):
    while node and node[0] == "call" and node[1] in WRAPPERS and node[2]:
        node = node[2][0]
    if node and node[0] == "call" and node[1] == "object" and node[2] and node[2][0][0] == "obj":
        return node[2][0][1]
    return None


def resolve(node, dotted: str):
    attrs = attributes(node)
    for seg in [s for s in dotted.split(".") if s and s != "self"]:
        if attrs is None or seg not in attrs:
            return None
        attrs = attributes(attrs[seg])
    return attrs


def allowlists(owner: Path) -> dict:
    f = owner / "allowed_keys.tf"
    if not f.is_file():
        return {}
    text = f.read_text(encoding="utf-8")
    m = re.search(r"^\s*allowed_keys\s*=", text, re.M)
    if not m:
        return {}
    node = Parser(tokens(text[m.end():])).expr()
    return {
        var: {p: sorted(item[1] for item in lst[1]) for p, lst in paths[1].items()}
        for var, paths in node[1].items()
    }


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    errors: list[str] = []
    for row in manifest["allowlists"]:
        where = f"{row['owner']}/allowed_keys.tf allowed_keys.{row['variable']}.{row['path']}"
        allowed = allowlists(ROOT / row["owner"]).get(row["variable"], {}).get(row["path"])
        if allowed is None:
            errors.append(f"{where}: missing")
            continue
        node = variable_type(ROOT / row["stage"] / "variables.tf", row["stage_variable"])
        attrs = resolve(node, row.get("stage_path", row["path"]))
        if attrs is None:
            errors.append(f"{where}: {row['stage']} variable {row['stage_variable']} has no object at {row.get('stage_path', row['path'])}")
            continue
        # root_only: keys the owner consumes itself and strips before forwarding
        # (e.g. app_services.service_team picks the project), so the stage never sees them.
        root_only = set(row.get("root_only", []))
        extra = sorted(set(allowed) - set(attrs) - root_only)
        missing = sorted(set(attrs) - set(allowed))
        if extra:
            errors.append(f"{where}: {', '.join(extra)} not in {row['stage']} {row['stage_variable']} (the stage type would drop them silently)")
        if missing:
            errors.append(f"{where}: lacks {', '.join(missing)} that {row['stage']} {row['stage_variable']} accepts")

    covered = {(r["owner"], r["variable"]) for r in manifest["allowlists"]}
    covered |= {(e["owner"], e["variable"]) for e in manifest.get("exempt", [])}
    for base in ("envs", "modules"):
        for vf in sorted((ROOT / base).rglob("variables.tf")):
            if SKIP & set(vf.relative_to(ROOT).parts):
                continue
            text = vf.read_text(encoding="utf-8")
            heads = list(re.finditer(r'^variable\s+"([^"]+)"\s*\{', text, re.M))
            for i, m in enumerate(heads):
                body = text[m.end(): heads[i + 1].start() if i + 1 < len(heads) else len(text)]
                if re.search(r"^\s*type\s*=\s*any\s*$", body, re.M):
                    owner = vf.parent.relative_to(ROOT).as_posix()
                    if (owner, m.group(1)) not in covered:
                        errors.append(f"{owner}: variable {m.group(1)} is `any` with no allowlist row in {MANIFEST.name}")

    for e in errors:
        print(f"check-any-allowlists: {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"check-any-allowlists: {len(manifest['allowlists'])} allowlists match their stage types")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Move each inline list into `allowed_keys.tf`.** For every `contains([...], k)` list in the six existing validations, copy the list verbatim into the owner's `allowed_keys.tf` (`self` for the top level, the attribute name for nested ones, e.g. `subnet_cidrs`, `secondary_ranges`, `artifact_registry`, `database`, `github`, `alerts`, `job`, `slo`, `pubsub`), and replace the literal in the validation with `local.allowed_keys.<variable>.<path>`. Validations may reference locals (the roots already read `local.cfg` in validations).

- [ ] **Step 4: Manifest** `scripts/any-allowlists.json`: one row per list. Stage targets (confirm each with `grep -n 'variable "<name>"' <stage>/variables.tf`):

| Owner | Variable | Stage | Stage variable |
|---|---|---|---|
| `envs/gcp/workload` | `app_services` | `modules/gcp/stages/app-services` | `services` |
| `modules/gcp/stages/environment` | `app_services` | `modules/gcp/stages/app-services` | `services` |
| `envs/gcp/workload` | `additional_regions` | `modules/gcp/stages/net-spoke` | `additional_regions` |
| `envs/gcp/workload` | `vm_backup_schedules` | `modules/gcp/backup/backup-plan` | `schedules` |
| `envs/gcp/workload` | `os_patch_deployments` | `modules/gcp/ops/os-config` | `patch_deployments` |
| `envs/aws/network` | `vpn` | `modules/aws/stages/network-hub` | `vpn` |
| `envs/gcp/network-hub` | `vpn` | `modules/gcp/stages/network-hub` | `vpn` |
| `envs/gcp/network-hub` | `interconnects` | `modules/gcp/stages/network-hub` | `interconnects` |
| `envs/gcp/network-hub` | `hub_additional_regions` | `modules/gcp/stages/network-hub` | `hub_additional_regions` |

The two `app_services` rows (path `self`) carry `"root_only": ["service_team"]`: the environment stage resolves `service_team` to a project and does not forward it, and `modules/gcp/stages/app-services` `services` has no such attribute. The parser was dry-run against the real stage files while writing this plan: it resolves `services` (31 attributes), `services.artifact_registry`, net-spoke `additional_regions` (`subnet_cidrs`, `secondary_ranges`, `nat`), the AWS and GCP `vpn` objects, `interconnects`, backup-plan `schedules` and os-config `patch_deployments`. If the stage variable's object is the value of a map (`map(object)`), path `self` already unwraps it. If a stage types a nested field as `any`, add `"stage_path"` to point at the module that types it, or list the field under `exempt` with a `"reason"`.

- [ ] **Step 5: New validations for network-hub.** In `envs/gcp/network-hub/variables.tf` add to `vpn`:

```hcl
  validation {
    condition     = length([for k in keys(coalesce(var.vpn, {})) : k if !contains(local.allowed_keys.vpn.self, k)]) == 0
    error_message = "vpn has keys the network-hub stage does not accept: ${join(", ", [for k in keys(coalesce(var.vpn, {})) : k if !contains(local.allowed_keys.vpn.self, k)])}."
  }
```

and the map-shaped equivalent for `interconnects` and `hub_additional_regions` (iterate `for name, v in coalesce(var.x, {}) : [for k in keys(v) : "${name}.${k}" if ...]`, plus the nested `subnet_cidrs` / `secondary_ranges` lists as in `envs/gcp/workload`'s `additional_regions`). Also validate the config-file path: the same condition over `jsondecode(coalesce(local.cfg.vpn, "{}"))` (the root reads the config value as JSON text, `config.tf:41`). Add one `expect_failures` run per input to `envs/gcp/network-hub/tests/hybrid.tftest.hcl` with a misspelled key (e.g. `vpn = { enabled = true, tunel_count = 2 }`), and run it red before adding the validation.

- [ ] **Step 6: Wire.** Append to `scripts/check-consistency.sh`:

```bash
echo "==> Allowlists of any-typed inputs match their stage types (scripts/check-any-allowlists.py)"
python3 -I scripts/check-any-allowlists.py >/dev/null || note "an any-typed input's allowlist drifted from its stage type"
```

- [ ] **Step 7: Run and pass.** `bash scripts/tests/test-check-any-allowlists.sh && make test TEST_DIRS="envs/gcp/workload envs/gcp/network-hub envs/aws/network modules/gcp/stages/environment" TERRAFORM=$TF && ./scripts/check-consistency.sh`. If the parity check finds real drift, fix the allowlist (the stage type is the source of truth) and note it in the CHANGELOG.

- [ ] **Step 8: Commit.** `fix: reject unknown keys in network-hub any inputs and check every any allowlist against its stage type`

---

## Task 24: One spelling for deletion protection (IAC-8, deletion protection only)

**Files**
- `modules/gcp/network/tiered-vpc`, `modules/gcp/stages/{dns-anchor,environment,net-spoke,net-hub}`, `modules/gcp/governance/private-ca`, `modules/aws/data/rds-aurora`: `deletion_protection` becomes `enable_deletion_protection`.
- `modules/aws/network/network-firewall`: `delete_protection` becomes `enable_deletion_protection`.
- `modules/aws/stages/app-services`: `alb_enable_deletion_protection` becomes `enable_alb_deletion_protection`.
- `envs/aws/workload`: `app_alb_enable_deletion_protection` becomes `enable_app_alb_deletion_protection`.
- Callers of each (grep), `UPGRADING.md`, `CHANGELOG.md`, generated READMEs.
- Create: `scripts/tests/test-deletion-protection-naming.sh` (or a section in `check-consistency.sh`).

- [ ] **Step 1: Failing guard.** Add to `scripts/check-consistency.sh`:

```bash
echo "==> Deletion protection has one input name: enable_<thing>_deletion_protection"
dp="$(grep -rnE --include='variables.tf' '^variable "(deletion_protection|delete_protection|[a-z_]+_enable_deletion_protection)"' envs modules | grep -v '/\.terraform/' || true)"
dp_new="$(printf '%s\n' "${dp}" | while IFS=: read -r f n _; do
  [[ -n "${f}" ]] && sed -n "${n},/^}/p" "${f}" | grep -q 'deprecated *=' || printf '%s\n' "${f}:${n}"; done || true)"
[[ -z "${dp_new}" ]] || note "deletion-protection input without the enable_ prefix and no deprecated marker: ${dp_new}"
```

It fails on today's 10 variables.

- [ ] **Step 2: Rename with a deprecated alias.** Pattern for each module (example `modules/gcp/network/tiered-vpc/variables.tf:149-153`):

```hcl
variable "enable_deletion_protection" {
  description = "Create a prevent_destroy guard that blocks any plan destroying the VPC and subnet stack, and enable VPC deletion protection. Null = deletion_protection (deprecated), else false."
  type        = bool
  default     = null
}

# tflint-ignore: terraform_unused_declarations # read through local.enable_deletion_protection until v1.0
variable "deletion_protection" {
  description = "Deprecated: use enable_deletion_protection. Removed in v1.0."
  type        = bool
  default     = null
  deprecated  = "Use enable_deletion_protection; deletion_protection is removed in v1.0."
}
```

and in `main.tf` `locals { enable_deletion_protection = coalesce(var.enable_deletion_protection, var.deletion_protection, <old default>) }`, replacing every `var.deletion_protection`. Keep each module's old default (`false` in tiered-vpc; read each). Update every caller to pass the new name (`grep -rn 'deletion_protection *= *var\.\|delete_protection *=\|alb_enable_deletion_protection' envs modules examples`), so no caller triggers the deprecation warning.

- [ ] **Step 3: Tests.** For each renamed module add to its `variables_validation.tftest.hcl` (or `plan_assertions`) one run that sets only the old name and asserts the effective local equals it, and one that sets both and asserts the new name wins. Run red first (local does not exist), then green. Existing tests that set the old name must switch to the new one.

- [ ] **Step 4:** `make docs && make test TEST_DIRS="<each touched module and root>" TERRAFORM=$TF && ./scripts/check-consistency.sh`. Note `envs/aws/workload` is a root: a TFC workspace variable `app_alb_enable_deletion_protection` keeps working through the alias.

- [ ] **Step 5: UPGRADING** entry "Deletion-protection inputs renamed" listing old and new names, "old names warn and are removed in v1.0; no state change". **Commit:** `refactor!: name every deletion-protection input enable_*deletion_protection with deprecated aliases`

---

## Task 25: tfc-admin fails when an upstream contract lacks the credential keys (IAC-9)

**Files:** `envs/tfc-admin/main.tf:994-1004`; `envs/tfc-admin/tests/root.tftest.hcl`.

- [ ] **Step 1: Failing tests.** Copy the run that holds the `override_data` at `root.tftest.hcl:385-412` twice:

```hcl
run "gcp_bootstrap_contract_missing_keys_fails" {
  command = plan
  variables {
    gcp_bootstrap_outputs_from_tfc = true
    workspace_execution_modes      = {}
  }
  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = { nonsensitive_values = { contract = { admin_project_id = "admin-proj" } } }
  }
  # plus every other override_data block the copied run needs
  expect_failures = [data.tfe_outputs.gcp_bootstrap]
}

run "aws_organization_contract_missing_keys_fails" {
  command = plan
  variables {
    aws_organization_outputs_from_tfc = true
  }
  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = { nonsensitive_values = { contract = { tfc_plan_role_arns = {} } } }
  }
  expect_failures = [data.tfe_outputs.aws_organization]
}
```

`make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`: both fail ("expected failure not raised"). The legacy-shape run at `:448-467` must keep passing.

- [ ] **Step 2: Postconditions.**

```hcl
data "tfe_outputs" "gcp_bootstrap" {
  count        = var.gcp_bootstrap_outputs_from_tfc ? 1 : 0
  organization = local.tfc_organization
  workspace    = "gcp-bootstrap"

  lifecycle {
    postcondition {
      condition     = length(setsubtract(["tfc_workload_provider_name", "tfc_plan_service_accounts", "tfc_apply_service_accounts"], keys(try(self.nonsensitive_values.contract, self.nonsensitive_values, {})))) == 0
      error_message = "gcp_bootstrap_outputs_from_tfc = true but the gcp-bootstrap outputs lack ${join(", ", setsubtract(["tfc_workload_provider_name", "tfc_plan_service_accounts", "tfc_apply_service_accounts"], keys(try(self.nonsensitive_values.contract, self.nonsensitive_values, {}))))}. Apply gcp-bootstrap first; if it has applied, its contract output changed (scripts/check-contracts.sh). Without them no gcp-* workspace gets dynamic credentials."
    }
  }
}
```

and the same for `aws_organization` with keys `["tfc_plan_role_arns", "tfc_apply_role_arns", "tfc_workspace_bindings"]` and the message naming aws-organization and `TFC_AWS_*`.

- [ ] **Step 3:** green run of the suite. **Commit:** `fix(tfc-admin): fail the plan when an upstream contract lacks the dynamic-credential keys`

---

## Task 26: Replace the module-level `depends_on` on the CloudTrail modules (IAC-10)

**Files:** `modules/aws/data/log-archive-bucket/outputs.tf`; `modules/aws/data/log-archive-bucket/tests/plan_assertions.tftest.hcl`; `modules/aws/stages/security/main.tf:221,240,269,291` (approximate; the `log_archive_bucket =` and `depends_on` lines in both module blocks).

- [ ] **Step 1: Failing test** in the log-archive-bucket plan suite:

```hcl
run "policy_attached_bucket_name_is_the_bucket" {
  command = plan
  assert {
    condition     = output.policy_attached_bucket_name == var.log_archive_bucket_name
    error_message = "policy_attached_bucket_name must equal the bucket name (and depend on the bucket policy)."
  }
}
```

Red: the output does not exist.

- [ ] **Step 2: Output.**

```hcl
output "policy_attached_bucket_name" {
  description = "The bucket name, taken from the bucket policy resource so a log producer wired to it (CloudTrail, Config) is created after the policy that lets it write. Use it instead of a module-level depends_on, which defers every data source in the calling module to apply time."
  value       = aws_s3_bucket_policy.this.bucket
}
```

- [ ] **Step 3: Stage.** In both `module "cloudtrail"` and `module "cloudtrail_delegated_admin"` blocks, set `log_archive_bucket = module.log_archive_bucket.policy_attached_bucket_name` and delete `depends_on = [module.log_archive_bucket]`.

- [ ] **Step 4:** `make docs && make test TEST_DIRS="modules/aws/data/log-archive-bucket modules/aws/stages/security envs/aws/security" TERRAFORM=$TF`; `grep -n 'depends_on = \[module.log_archive_bucket\]' modules/aws/stages/security/main.tf` returns nothing. **Commit:** `refactor(aws-security): order CloudTrail after the bucket policy by data flow, not module depends_on`

---

## Task 27: Clear the Checkov false positives and rewrite the stale header (IAC-11)

**Files:** `modules/aws/stages/security/examples/basic/main.tf:36`, `modules/gcp/stages/organization/examples/basic/main.tf:19`, `modules/saas/stages/saas-workload/examples/basic/main.tf:31`; `modules/gcp/network/secure-web-proxy/main.tf:115-124`; `modules/aws/network/load-balancer/examples/basic/main.tf` (or `main.tf:63-121`); `.checkov.yaml:1-75,138-143`.

- [ ] **Step 1: Reproduce red.** `uvx --python 3.12 checkov==3.3.17 -d modules --framework terraform --config-file .checkov.yaml --compact -o cli` and the same for `-d envs`. Expected on `modules/`: `Failed checks: 11` (the list in the Findings table).

- [ ] **Step 2: Fix or justify each.**
  - CKV_TF_1 (three tag-pinned examples): inside each `module` block add `# checkov:skip=CKV_TF_1:Examples pin a release tag that release-please bumps (x-release-please-version); a commit hash would go stale on every release.`
  - CKV_GCP_26 and CKV_GCP_74 on `google_compute_subnetwork.psc_nat`: add inside the resource `# checkov:skip=CKV_GCP_26:A PRIVATE_SERVICE_CONNECT NAT subnet carries no VM traffic; flow logs do not apply to this purpose.` and `# checkov:skip=CKV_GCP_74:Private Google Access does not apply to a PRIVATE_SERVICE_CONNECT subnet.` Confirm against the Google subnetwork documentation before committing.
  - CKV2_AWS_20 and CKV_AWS_378 (load-balancer example): if the module supports an HTTPS listener with an HTTP-to-HTTPS redirect, change the example to use it; otherwise add inline skips on `aws_lb.this` / `aws_lb_target_group.this` stating that TLS termination and redirect are caller choices passed through `listeners`.
  - Triage every `envs/` failure the same way; never add a global `skip-check`.

- [ ] **Step 3: Rewrite the `.checkov.yaml` header** (`:1-75`) as:

```yaml
# Checkov configuration (checkov version: .tool-versions; CI runs the same image).
#
# Policy: suppressions are inline `# checkov:skip=<ID>:<reason>` on the exact
# resource whose pattern is intentional. A global skip-check entry is allowed only
# when every instance in the repo is the same false positive; each one below says why.
# List the inline skips with: grep -rn 'checkov:skip=' modules envs
#
# Test fixtures are not scanned (skip-path): *.tftest.hcl values are mocks.
```

and the footer (`:138-143`) as:

```yaml
# Version note: make security runs checkov at the .tool-versions pin through uvx,
# the same version as the CI checkov-action image, and refuses a mismatched local
# binary. When CI and local results differ, the versions have drifted: fix the pin.
```

Delete the "REMOVED" history blocks (they live in git history) except where a global entry below depends on them. Keep each global `skip-check` entry and its rationale; CKV2_GCP_4's rationale is owned by the compliance workstream (CMP-4), so leave its text unchanged here.

- [ ] **Step 4: Green.** Re-run both scans: `Failed checks: 0`. `make security` if Trivy 0.70.0 is installed. **Commit:** `fix(security): resolve the Checkov false positives inline and rewrite the stale .checkov.yaml header`

---

## Task 28: One archive provider constraint (IAC-14)

**Files:** `modules/aws/security/incident-response/examples/basic/versions.tf:11`; `scripts/check-consistency.sh`.

- [ ] **Step 1: Failing guard** in `check-consistency.sh`:

```bash
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
```

google, google-beta, aws and the Terraform version already have their own checks. Before the fix this fails on `modules/aws/security/incident-response/examples/basic`.

- [ ] **Step 2: Fix** `examples/basic/versions.tf:11` to `version = ">= 2.0, < 3.0"`. Re-lock only if `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` changes the file.

- [ ] **Step 3:** `./scripts/check-consistency.sh`. **Commit:** `fix(examples): match the incident-response example's archive constraint to its module`

---

## Final verification (after all tasks)

- [ ] `make ci-quick` passes.
- [ ] `make test TERRAFORM=$TF` for every root and module touched (or the full set).
- [ ] `uvx --python 3.12 checkov==3.3.17 -d modules ...` and `-d envs ...` report 0 failures.
- [ ] `grep -rniE 'production[- ]grade|fully[- ]tested' README.md CLAUDE.md` is empty.
- [ ] `make -n plan-gcp-workload APP_ENV=prod` shows no `-var-file`.
- [ ] `./scripts/check-security-contact.sh` exits 0 (after the operator action in Task 22).
- [ ] UPGRADING.md "Unreleased" has entries for Tasks 5 and 24; CHANGELOG.md "Unreleased" has entries for Tasks 1, 5, 13, 21, 23, 24.
