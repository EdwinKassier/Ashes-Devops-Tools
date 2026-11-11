# WS5 Change management, supply chain and proof: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or build to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every change to `main` reviewed, signed and gated by one green check. Make the GitHub and HCP Terraform guardrails code that is reviewed and drift-detected. Make production receive an exact, attested commit that a second person approved. Then prove the estate works with a funded sandbox that applies two GCP environments and two AWS workload accounts outside `eu-west-2`, and make a green nightly proof a release criterion.

**Architecture:** Four layers, built in order.

1. **CI green on `main`.** Fix the 4 yamllint errors, 4 Trivy findings and 11 Checkov failures that make `main` red today. Then run the 14 meta-lint steps that the yamllint failure masked. Close the `make ci` parity gap so local runs catch the same failures.
2. **Governance as code.** A new root, `envs/github-admin`, uses the `integrations/github` provider to own the repository rulesets (main, release tags, deployment tags, production branch), the 8 GitHub environments and their deployment policies, secret scanning, push protection, Dependabot security updates and the Actions allow-list. HCP Terraform policy sets stop reading `main` and are uploaded as a content-addressed slug by `tfc-admin`, so a policy change needs a tfc-admin apply that the security team must override.
3. **Promotion and provenance.** Production workload workspaces track a `production` branch. Only the release GitHub App can move it, by fast-forward to a release tag, from a `promote.yml` run that a second person approves after seeing the production plan. Releases carry a SLSA build provenance attestation and a CycloneDX SBOM. The apply verifier fails closed.
4. **Proof.** The sandbox estate config grows to two GCP environments and two AWS workload accounts in `us-east-2` / `us-east4`. A nightly `sandbox-estate-probe.yml` checks convergence of every sandbox workspace, then runs real-apply probes from inside each spoke: subnet placement, private DNS resolution and internet egress. A `Release Proof` job blocks every release PR until the probe and the unit e2e suites are green on the exact base commit.

**Tech Stack:** Terraform 1.17.1, `integrations/github` `>= 6.13.0, < 7.0.0`, `hashicorp/tfe` `>= 0.83.0, < 1.0.0`, `hashicorp/google` `~> 8.0`, `hashicorp/aws` `>= 6.46.0, < 7.0.0`, `hashicorp/time`, `hashicorp/archive`, OPA 1.22.2, GitHub Actions (SHA-pinned), `actions/attest-build-provenance` v4.2.2, `actions/attest-sbom` v4.1.0, `anchore/sbom-action` v0.24.3, `actions/create-github-app-token` v3.3.0, `hashicorp/tfc-workflows-github` v1.3.2, zizmor, Renovate.

---

## Evidence gathered for this plan (2026-11-11, read-only)

| Check | Result |
|---|---|
| `gh api repos/EdwinKassier/Ashes-Devops-Tools/branches/main/protection` | 8 classic required contexts, `Validation Summary` absent, `strict: false`, `enforce_admins: false`, no reviews, `required_signatures: false` |
| `gh api .../rulesets` | `[]` (no rulesets) |
| `gh api .../environments` | `docs-bot`, `release`, `tfc-drift` exist, all with `protection_rules: []` and `deployment_branch_policy: null`. `tfc-readonly`, `tfc-state-backup`, `e2e-sandbox` do not exist |
| `security_and_analysis` | secret scanning, push protection, non-provider patterns, validity checks and Dependabot security updates all `disabled`. Vulnerability alerts endpoint returns 404 (off) |
| Actions permissions | `allowed_actions: all`, `sha_pinning_required: false`, default token `read`, cannot approve PRs |
| Owner | `owner.type = User` (personal account), one collaborator (`admin`). GitHub teams cannot exist on a personal repository |
| Tag `v0.1.0` | `object.type = commit`, so it is lightweight |
| Last 100 commits on `main` | 95 unverified, 5 verified (all 5 committed by GitHub merge) |
| PR #599 | Authored and merged by the same account, 0 human reviews, merged with failing `Meta Lint`, `Security / Trivy`, `Security / Checkov`, `Validation Summary` |
| Renovate | 0 PRs ever opened by `app/renovate`. Dependabot is active (PRs #600, #601 open) |
| Run 43066418064 (Terraform Validation, `c08f3c4f`) | Failed: `Meta Lint` (yamllint step; the 14 later steps were **skipped**), `Security / Trivy`, `Security / Checkov`, `Validation Summary` |
| Run 43066418056 (Release) | Failed at `Require RELEASE_PLEASE_TOKEN` |
| Run 43052136400 (Drift Detection) | Failed: `TFC_TOKEN_DRIFT` / `TFC_ORGANIZATION` not configured |
| Run 43008548183 (Sandbox E2E) | Failed at preflight: `E2E_GCP_*` and `E2E_AWS_*` variables unset |

### Exact CI failures on `main` (to fix in Phase 0)

| Gate | File:line | Rule |
|---|---|---|
| yamllint | `examples/app-delivery/gke-autopilot-delivery.example.yml:30` | line-length 167 > 120 |
| yamllint | `envs/gcp/network-hub/tests/fixtures/landing-zone-hybrid.yaml:19` (2 errors) | braces: spaces inside `{ }` |
| yamllint | `envs/aws/organization/tests/fixtures/landing-zone-cloudtrail-da.yaml:1` | line-length 123 > 120 |
| Trivy | `modules/aws/stages/app-services/main.tf:533-546` | AWS-0104 CRITICAL, SG egress `0.0.0.0/0:443` |
| Trivy | `modules/aws/data/ecr/main.tf:70-90` | AWS-0032 HIGH, `Principal = "*"` (Trivy ignores the `aws:PrincipalOrgID` condition) |
| Trivy | `modules/aws/data/log-archive-bucket/main.tf:279-288` (2 call paths) | AWS-0132 HIGH, access-log bucket uses SSE-S3 |
| Checkov | `modules/aws/stages/security/examples/basic/main.tf:36`, `modules/gcp/stages/organization/examples/basic/main.tf:19`, `modules/saas/stages/saas-workload/examples/basic/main.tf:31` | CKV_TF_1, module source pinned to a tag, not a commit |
| Checkov | `modules/gcp/network/secure-web-proxy/main.tf:115-124` (3 call paths in modules, 1 in envs) | CKV_GCP_26 and CKV_GCP_74 on a `PRIVATE_SERVICE_CONNECT` subnet |
| Checkov | `modules/aws/network/load-balancer/main.tf:63-90` and `:96-121` (from `examples/basic`) | CKV2_AWS_20 (HTTP to HTTPS redirect not resolved), CKV_AWS_378 (HTTP target group) |
| Release | `.github/workflows/release.yml:57-71` | `RELEASE_PLEASE_TOKEN` missing |

Checkov also reports 1 parsing error under `modules` and 3 under `envs`. They do not fail the gate, but Task 3 lists them.

---

## Findings covered

| ID | Finding (short) | Status today (verified) | Task(s) |
|---|---|---|---|
| CI red | yamllint, Trivy, Checkov, release token | Verified, see table above | 1, 2, 3, 4, 5 |
| CICD-15 | `make ci` not at parity with CI | Verified: no yamllint, markdownlint, commitizen, OPA or CODEOWNERS step in `make ci` | 6 |
| CICD-1 | No reviews, `enforce_admins: false`, no rulesets, admin merges on red | Verified | 7, 8, 14 |
| CICD-8 | Live required checks omit `Validation Summary` | Verified; `make required-checks-live` reads only classic protection | 8, 14 |
| CICD-3 | Policy sets VCS-sourced from `main`; placeholder CODEOWNERS | Verified (`envs/tfc-admin/main.tf:1273-1330`, `.github/CODEOWNERS`) | 12, 13 |
| CICD-4 | Environments unprotected; 3 missing | Verified (6 named in workflows, 3 exist) | 9, 14 |
| CICD-9 | Secret scanning, push protection, Dependabot security updates off; `allowed_actions: all` | Verified | 10, 14 |
| CICD-5 | Approver can author, merge and confirm; no plan review before merge | Verified by design reading | 16, 17 |
| CICD-6 | Every workspace tracks `main`; no artifact promotion | Verified (`modules/tfc/workspace/variables.tf:84` default `main`, one `local.vcs_repo` for all) | 15, 16 |
| CICD-7 | Lightweight unsigned tag, no SBOM/provenance, no tag ruleset, apply verifier fails open | Verified (`terraform-apply.yml:166-170`) | 8, 18 |
| CICD-16 | `github.base_ref` interpolated in `run:` | Verified (`terraform-plan.yml:377-378`, `391-392`); low severity, see below | 19 |
| CICD-18 | Drift workflow grants `issues: write` at workflow level | Verified (`drift-detection.yml:56-58`) | 19 |
| CICD-12 | harden-runner audit mode on secret-holding jobs | Partly verified: `release.yml` and `drift-detection.yml` already block; `documentation.yml`, `state-backup.yml`, `terraform-apply.yml`, `security-scan.yml` (gitleaks) and the `sandbox-e2e.yml` cloud jobs audit | 20 |
| CICD-13 | Toolchain versions outside update automation | Verified: `renovate.json` enables only `terraform`; `.tool-versions`, `TERRAFORM_VERSION`, `OPA_VERSION`, `SC_VERSION`, `TDOCS_VERSION`, trivy `version:` and pre-commit `rev:` are hand-bumped | 21 |
| IAC-6 | Renovate never ran | Verified (0 Renovate PRs) | 21 |
| CICD-17 | Example delivery deploys by tag, no attestation | Verified (`examples/app-delivery/*.example.yml`) | 22 |
| IAC-3 | No per-module versioning | Verified | 23 |
| ADO-10 | Bus factor 1 | Verified (1 collaborator) | 24, D1, D2 |
| IAC-5 / ADO-10 proof | Never applied; `sandbox-e2e.yml` never succeeded | Verified | 25 to 30 |
| ARC-1/2/3 (proof only) | Data-plane defects mock tests cannot catch | The fixes belong to the architecture workstream. This plan adds the real-apply checks that fail until those fixes land | 25 to 29 |

### Findings judged invalid or overstated

| ID | Verdict | Evidence |
|---|---|---|
| CICD-16 | **Valid but Low, not exploitable by outsiders.** | `github.base_ref` is the name of a branch that already exists in this repository. Only accounts with write access can create one. A fork PR cannot choose an arbitrary base name. It is still worth fixing (Task 19) because zizmor flags it and the fix is 4 lines. |
| CICD-12 | **Overstated.** | Two of the six secret-holding workflows (`release.yml:47`, `drift-detection.yml:82,163`) already use `egress-policy: block`. The finding holds for the other four. |
| CICD-3 (remediation) | **Finding valid; the audit's suggested fix is impossible as written.** | The repository is owned by a personal account (`owner.type = User`). GitHub teams exist only in organizations, so `@your-org/*` cannot be replaced by real teams without moving the repository to an organization (Decision D1). |
| "CI is unfunded" (owner statement) | **Contradicted by evidence for GitHub Actions.** | Actions ran 9 workflows on `c08f3c4f` alone. Public repositories get free hosted-runner minutes. What is unfunded is HCP Terraform, the sandbox clouds and their tokens (the drift and e2e failures are missing configuration, not missing minutes). See D10. |

No other finding in scope was judged invalid. Two findings are *wider* than reported: Trivy also fails on 3 HIGH findings (not only AWS-0104), and the yamllint failure hid 14 later meta-lint steps whose state on `main` is unknown until Task 1 step 6.

---

## Decisions needed

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Repository owner | (a) Transfer `EdwinKassier/Ashes-Devops-Tools` to a free GitHub organization; (b) stay personal and list individual users in CODEOWNERS | **(a).** Teams, team reviewers in rulesets, org-level rulesets and a clean bus-factor story all need an organization. GitHub redirects the old URL. Do it before Task 13. Task 7 to 12 work either way (`owner` is a variable). |
| D2 | Review rule while there is one maintainer | (a) `required_approvals = 1`, `admin_bypass = "pull_request"` (admin can merge own PR; GitHub records each bypass); (b) `admin_bypass = "none"` (no merge until a second maintainer exists); (c) 0 approvals | **(a) for at most 60 days, then (b).** The root defaults to (b). Set `github.admin_bypass: pull_request` in config only as a dated, documented exception in `docs/known-gaps.md`. (c) is never acceptable to an auditor. |
| D3 | Credential for `github-admin` | (a) GitHub App with `Administration`, `Environments`, `Secrets` read and `Contents` read/write on this repository only; (b) fine-grained PAT | **(a).** No long-lived personal token; the key lives only in the HCP workspace as a sensitive env var. |
| D4 | Where GitHub governance lives | (a) New root `envs/github-admin`; (b) inside `envs/tfc-admin` | **(a).** Different provider and credential, different blast radius: a leaked tfc-admin token must not also unprotect `main`. It keeps tfc-admin (already 1,440 lines, ARC-7) from growing. It follows the repo rule that each concern is its own workspace, and tfc-admin still creates its workspace (Task 11). |
| D5 | Release automation identity | (a) One GitHub App "release bot" (contents, pull requests, issues: write) for release-please and production promotion; (b) a PAT in `RELEASE_PLEASE_TOKEN` | **(a).** Tokens are minted per run (1 hour). The App ID becomes the only bypass actor on the release-tag and production rulesets. |
| D6 | Promotion model (CICD-6) | (a) Production workload workspaces track a `production` branch that only `promote.yml` fast-forwards to a release tag; (b) `tags_regex` on production workspaces; (c) keep `main` | **(a).** Smallest change (one optional branch override in tfc-admin). (b) conflicts with `trigger_patterns` in the `tfe` provider, so every tag would plan every production workspace; verify before choosing it. |
| D7 | Four-eyes on production applies (CICD-5) | (a) GitHub side: `production-promotion` environment with a required reviewer and `prevent_self_review`, plus a production plan shown before approval; (b) an HCP pre-apply run task (a small HTTPS service) that rejects a run whose `confirmed-by` user authored or merged the commit; (c) an OPA rule | **(a) now, (b) as a later option.** OPA cannot do it: policies evaluate before confirmation, so the confirmer is unknown, and the input carries no PR author (Task 17 records the real input). (b) needs a hosted service and the Standard tier. |
| D8 | Dependency automation for Terraform (IAC-6) | (a) Install the Renovate GitHub App (config already in repo); (b) Dependabot `terraform` ecosystem | **(a).** `renovate.json` already encodes the grouping and multi-platform `lockFileMaintenance`. Add a heartbeat check so "never ran" cannot recur silently (Task 21). |
| D9 | Module versioning (IAC-3) | (a) Keep one repo-wide SemVer, publish a compatibility policy, and add a CI guard that fails a PR which removes a module input or output without a breaking-change marker; (b) per-module tags through HCP private registry monorepo publishing (`tag_prefix`, `source_directory`) | **(a) now.** (b) means 125 release streams for one maintainer. Revisit after 1.0. |
| D10 | Funding | Question for the owner: "Actions runs on every push and costs nothing on a public repository. Is 'CI unfunded' about HCP Terraform and the sandbox clouds?" | **Fund three things:** (1) HCP Terraform Standard tier for two organizations (policy sets, teams, health assessments; priced per resource under management, confirm the quote); (2) the sandbox estate at about USD 1,000 to 1,300 per month on the `starter` profile with two environments (audit Part 4: about 770 to 1,050 plus one AWS workload account at 60 to 150); (3) the unit e2e sandbox at under USD 5 per month. |
| D11 | Scheduled jobs that fail for missing configuration | (a) Set `REAL_CLOUD_CHECKS_OPT_OUT=true` until D10 is funded; (b) leave nightly red | **(a), time-boxed and listed in `docs/known-gaps.md`.** A permanently red nightly teaches everyone to ignore red. Scheduled runs still post a warning that says "did NOT run". |
| D12 | Signed commits on `main` | (a) `required_signatures` plus squash-only merges (GitHub signs the squash commit); (b) off | **(a).** No contributor needs a signing key, and every new commit on `main` shows as verified. |
| D13 | Sandbox regions | (a) AWS `us-east-2`, GCP `us-east4`; (b) keep `eu-west-2` / `europe-west2` | **(a).** The proof must leave the default region to catch ARC-3. |
| D14 | Release criterion strictness | (a) A green estate probe and green unit e2e on the **exact** base commit of the release PR; (b) any green run in the last 7 days | **(a).** A maintainer can dispatch the probe for the commit if the nightly run is stale. |

---

## Conventions for every task

- Terraform binary for local runs: `TF=/private/tmp/claude-501/-Users-edwinkassier-Desktop-Ashes-Ashes-Devops-Tools--claude-worktrees-enterprise-devops-audit-949b65/50c7eb6b-1026-4421-925b-256b9cc0fb04/scratchpad/tf/terraform`.
- Test one directory: `make test TEST_DIRS=<dir> TERRAFORM=$TF`.
- After any change to variables or outputs: `make docs`. Before any commit: `make fmt-check consistency count-check links`.
- Commits follow Conventional Commits (CI runs `cz check`). A breaking change uses `!:` and adds an `UPGRADING.md` entry in the same PR (CI enforces it). End every commit message with the session's attribution trailer.
- Never run `terraform apply` against any landing-zone root. The only real applies in this plan are the disposable `tests/e2e/**` fixtures in the sandbox, run by CI.
- Category (A) = code an agent can write and test locally. (B) = operator step that needs repo admin, HCP or cloud admin. (C) = funding or people.

---

## Phase 0: Get CI green on `main`

## Task 1: Fix the yamllint errors and surface the masked meta-lint steps (A)

**Files:**
- Modify: `examples/app-delivery/gke-autopilot-delivery.example.yml:30`
- Modify: `envs/gcp/network-hub/tests/fixtures/landing-zone-hybrid.yaml:19`
- Modify: `envs/aws/organization/tests/fixtures/landing-zone-cloudtrail-da.yaml:1`

- [ ] **Step 1: Reproduce.**

```bash
pre-commit run yamllint --all-files
```

Expected: FAIL with exactly the 4 errors in the table above (warnings do not fail).

- [ ] **Step 2: Wrap the long comment in the GKE example.** Replace line 30:

```yaml
#         principalSet://iam.googleapis.com/projects/<host-number>/locations/global/workloadIdentityPools/apps-<env>/attribute.repo_ref/<repository_id>/refs/heads/main
```

with:

```yaml
#         principalSet://iam.googleapis.com/projects/<host-number>/locations/global/
#           workloadIdentityPools/apps-<env>/attribute.repo_ref/<repository_id>/refs/heads/main
#         (one string: join the two lines above with no space)
```

- [ ] **Step 3: Remove the brace padding in the hybrid fixture.** Line 19 becomes:

```yaml
        - {range: 10.0.0.0/16, description: hub VPC}
```

- [ ] **Step 4: Split the long header comment in the CloudTrail fixture.** Line 1 becomes:

```yaml
# Test fixture: org trail managed by the CloudTrail delegated admin,
# adopting an existing registration (config.tftest.hcl).
```

- [ ] **Step 5: Verify.**

```bash
pre-commit run yamllint --all-files
make test TEST_DIRS="envs/gcp/network-hub envs/aws/organization" TERRAFORM=$TF
```

Expected: yamllint PASS; both suites PASS (the fixtures still parse to the same values).

- [ ] **Step 6: Run every meta-lint step the yamllint failure skipped**, in CI order, and fix what fails before committing. These ran on no commit since the yamllint error landed.

```bash
pre-commit run markdownlint --all-files && git diff --exit-code   # the hook runs --fix; a diff means a lint failure
git fetch origin main && cz check --rev-range "$(git merge-base origin/main HEAD)..HEAD"
make consistency config-check count-check links examples-refs required-checks test-scripts
bash scripts/scaffold-fixtures.sh --check 2>/dev/null || echo "see terraform-plan.yml meta-lint for the exact scaffold command"
python3 scripts/check-module-usage.py --check
```

Expected: all PASS. On 2026-11-11 `consistency`, `config-check`, `links` and `required-checks` already pass locally. If markdownlint changes files, commit those fixes in this task.

- [ ] **Step 7: Commit.**

```bash
git add examples/app-delivery/gke-autopilot-delivery.example.yml envs/gcp/network-hub/tests/fixtures/landing-zone-hybrid.yaml envs/aws/organization/tests/fixtures/landing-zone-cloudtrail-da.yaml
git commit -m "fix(ci): clear the yamllint errors that turned main red"
```

---

## Task 2: Resolve the 4 Trivy findings (A)

Each finding is a false positive or an intentional pattern. Suppress at the resource, with the reason, the same way `tests/e2e/aws/main.tf:83` already does. Do not lower the severity floor.

**Files:**
- Modify: `modules/aws/stages/app-services/main.tf:533`
- Modify: `modules/aws/data/ecr/main.tf:70`
- Modify: `modules/aws/data/log-archive-bucket/main.tf:279`
- Modify: `modules/aws/stages/app-services/tests/plan_assertions.tftest.hcl` (or the existing behaviour suite)

- [ ] **Step 1: Reproduce.** `make security` (needs trivy 0.70.0 and checkov 3.3.17 from `.tool-versions`). Expected: Trivy exits 1 with AWS-0104, AWS-0032, AWS-0132.

- [ ] **Step 2: Write a failing test that pins the reason for the AWS-0104 suppression.** The suppression is safe only because the spoke sends `0.0.0.0/0` to the transit gateway (central inspection), never to an internet gateway. Add to the app-services behaviour suite:

```hcl
run "service_https_egress_is_port_443_only" {
  command = plan

  assert {
    condition = alltrue([
      for r in aws_vpc_security_group_egress_rule.service_https :
      r.from_port == 443 && r.to_port == 443 && r.ip_protocol == "tcp"
    ])
    error_message = "service_https may only open TCP 443; anything wider voids the AVD-AWS-0104 suppression."
  }
}
```

Run `make test TEST_DIRS=modules/aws/stages/app-services TERRAFORM=$TF`. Expected: PASS already (the test documents the invariant; it fails if someone widens the rule later).

- [ ] **Step 3: Add the suppressions.**

`modules/aws/stages/app-services/main.tf`, directly above `resource "aws_vpc_security_group_egress_rule" "service_https" {`:

```hcl
#trivy:ignore:AVD-AWS-0104 TCP 443 only. Spoke default route is the TGW, so this traffic is inspected and domain-filtered by the central egress VPC (aws-network); there is no IGW in the spoke. Pinned by run "service_https_egress_is_port_443_only".
```

`modules/aws/data/ecr/main.tf`, directly above `policy = jsonencode({` inside `aws_ecr_repository_policy.org`:

```hcl
  #trivy:ignore:AVD-AWS-0032 Principal "*" is bounded by the aws:PrincipalOrgID condition below, so only principals in this AWS organization can pull. Trivy does not evaluate conditions.
```

`modules/aws/data/log-archive-bucket/main.tf`, directly above `resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {`:

```hcl
#trivy:ignore:AVD-AWS-0132 S3 server access logging cannot deliver to an SSE-KMS bucket (AWS limitation, also stated in the Trivy rule text). This is the access-log destination, so SSE-S3 is required.
```

- [ ] **Step 4: Verify.** `make security`. Expected: the Trivy stage exits 0 (Checkov may still fail until Task 3).

- [ ] **Step 5: Commit.**

```bash
git commit -am "fix(security): document the three Trivy false positives at the resource"
```

---

## Task 3: Resolve the 11 Checkov failures (A)

**Files:**
- Modify: `modules/aws/stages/security/examples/basic/main.tf`, `modules/gcp/stages/organization/examples/basic/main.tf`, `modules/saas/stages/saas-workload/examples/basic/main.tf`
- Modify: `modules/gcp/network/secure-web-proxy/main.tf:115`
- Modify: `modules/aws/network/load-balancer/main.tf:63`, `modules/aws/network/load-balancer/examples/basic/main.tf`
- Modify: `modules/aws/network/load-balancer/tests/plan_assertions.tftest.hcl`

- [ ] **Step 1: Reproduce.**

```bash
checkov -d modules --quiet --compact --framework terraform --config-file .checkov.yaml
checkov -d envs --quiet --compact --framework terraform --config-file .checkov.yaml
```

Expected: 11 failed checks under `modules`, 2 under `envs`.

- [ ] **Step 2: CKV_TF_1 on the three tag-pinned examples.** release-please bumps the `?ref=vX.Y.Z` marker, so a commit SHA would break the release flow. Add as the first line inside each `module` block:

```hcl
  # checkov:skip=CKV_TF_1:Published example pinned to the release tag that release-please bumps (x-release-please-version); the tag ruleset (envs/github-admin) makes release tags immutable.
```

- [ ] **Step 3: CKV_GCP_26 and CKV_GCP_74 on the PSC NAT subnet.** Add inside `resource "google_compute_subnetwork" "psc_nat"`:

```hcl
  # checkov:skip=CKV_GCP_26:purpose = PRIVATE_SERVICE_CONNECT subnets carry no VM traffic and do not support VPC flow logs.
  # checkov:skip=CKV_GCP_74:purpose = PRIVATE_SERVICE_CONNECT subnets do not support private_ip_google_access.
```

- [ ] **Step 4: Load balancer.** Fix the example instead of skipping CKV_AWS_378: change the `web` target group in `examples/basic/main.tf` from `protocol = "HTTP"` to `protocol = "HTTPS"` (and its health check protocol to `HTTPS`). For CKV2_AWS_20, Checkov cannot follow the `for_each` listener map. Add inside `resource "aws_lb" "this"`:

```hcl
  # checkov:skip=CKV2_AWS_20:HTTP listeners are caller-supplied through var.listeners (for_each); the HTTP-to-HTTPS redirect is asserted by run "http_listener_redirects_to_https" in tests/plan_assertions.tftest.hcl.
```

Add that run to the module's plan suite (write it first and run it; it must pass against the example-shaped input):

```hcl
run "http_listener_redirects_to_https" {
  command = plan

  variables {
    listeners = {
      http = {
        port           = 80
        protocol       = "HTTP"
        default_action = { type = "redirect", redirect = { protocol = "HTTPS", port = "443", status_code = "HTTP_301" } }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["http"].default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "An HTTP listener must redirect to HTTPS."
  }
}
```

Adjust the `listeners` shape to the module's real variable type (read `variables.tf` first).

- [ ] **Step 5: List the parsing errors** so they are tracked, not hidden:

```bash
checkov -d modules --framework terraform --config-file .checkov.yaml -o json | jq -r '.. | .parsing_errors? // empty | .[]'
checkov -d envs --framework terraform --config-file .checkov.yaml -o json | jq -r '.. | .parsing_errors? // empty | .[]'
```

Fix any that are real HCL issues. Record the rest (Checkov parser limits) in `docs/known-gaps.md` under a "Scanner coverage" heading.

- [ ] **Step 6: Verify.** `make security` exits 0. `make test TEST_DIRS="modules/aws/network/load-balancer" TERRAFORM=$TF` passes. `make docs-check` passes.

- [ ] **Step 7: Commit.** `git commit -am "fix(security): clear the Checkov failures on main"`

---

## Task 4: Replace `RELEASE_PLEASE_TOKEN` with a release GitHub App (A + B)

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `docs/guides/CI_SECRETS.md` (section `release_please_token` becomes `release_app`)

- [ ] **Step 1 (A): Mint a per-run token.** Replace the "Require RELEASE_PLEASE_TOKEN" step and the `token:` input with:

```yaml
      # The release bot GitHub App (contents, pull requests, issues: write on
      # this repository only). Its token lasts one hour and is minted per run,
      # so no long-lived PAT exists. The App ID is the only bypass actor on the
      # release-tags ruleset (envs/github-admin).
      - name: Require the release App
        env:
          APP_ID: ${{ vars.RELEASE_APP_ID }}
          HAS_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY != '' }}
        run: |
          if [ -z "${APP_ID}" ] || [ "${HAS_KEY}" != "true" ]; then
            echo "::error title=Release App missing::Set variable RELEASE_APP_ID and secret RELEASE_APP_PRIVATE_KEY in the release environment (docs/guides/CI_SECRETS.md#release_app)."
            exit 1
          fi

      - name: Mint release token
        id: app-token
        uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510  # v3.3.0
        with:
          app-id: ${{ vars.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - name: Run release-please
        id: release
        uses: googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7  # v5.0.0
        with:
          token: ${{ steps.app-token.outputs.token }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

Also add job outputs for Task 18:

```yaml
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
      tag_name: ${{ steps.release.outputs.tag_name }}
```

The existing `harden-runner` block list (`api.github.com:443`, `github.com:443`) covers token minting.

- [ ] **Step 2 (A): Verify locally.** `pre-commit run yamllint --files .github/workflows/release.yml` and `actionlint .github/workflows/release.yml` if installed. Expected: PASS.

- [ ] **Step 3 (A): Commit.** `git commit -am "ci(release): mint release-please tokens from a GitHub App"`

- [ ] **Step 4 (B): Operator creates the App** (GitHub UI, Settings > Developer settings > GitHub Apps > New):
  - Name: `ashes-release-bot`. Webhook: off. Permissions (repository): Contents read/write, Pull requests read/write, Issues read/write, Metadata read. Install only on this repository.
  - Generate a private key. Then:

```bash
gh variable set RELEASE_APP_ID --env release --body "<app id>"
gh secret set RELEASE_APP_PRIVATE_KEY --env release < ashes-release-bot.private-key.pem
shred -u ashes-release-bot.private-key.pem   # or rm -P on macOS
gh workflow run release.yml
```

- Expected: the Release run passes and opens (or updates) the release PR, which receives `Validation Summary`.

---

## Task 5: Stop red-by-configuration nightly runs until funded (B)

Depends on D11.

- [ ] **Step 1:** `gh variable set REAL_CLOUD_CHECKS_OPT_OUT --body true`
- [ ] **Step 2:** Add a dated entry to `docs/known-gaps.md` (A): "Drift detection and sandbox e2e are opted out until the sandbox is funded (D10). Scheduled runs show a 'did NOT run' warning." Commit: `docs(known-gaps): record the real-cloud opt-out and its exit condition`.
- [ ] **Step 3:** Confirm the next scheduled `Drift Detection` and `Sandbox E2E` runs end `success` with the warning annotation. Remove the variable in Task 30.

---

## Task 6: Bring `make ci` to parity with CI (A) (CICD-15)

**Files:**
- Modify: `Makefile`
- Create: `scripts/tests/test-make-ci-parity.sh`

- [ ] **Step 1: Write the failing parity test.** It fails when a CI gate has no `make` equivalent.

```bash
#!/usr/bin/env bash
# Every gate in terraform-plan.yml must have a make target that make ci runs.
#   bash scripts/tests/test-make-ci-parity.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ci_block="$(awk '/^ci:/{f=1;next} f&&/^[^\t]/{f=0} f' "${REPO_ROOT}/Makefile")"
failures=0
for target in yamllint markdownlint-check commit-check opa-test codeowners-check zizmor; do
  if grep -q "\$(MAKE) ${target}\$" <<<"${ci_block}"; then
    printf '  ok   make ci runs %s\n' "${target}"
  else
    printf '  FAIL make ci does not run %s\n' "${target}" >&2
    failures=$((failures + 1))
  fi
done
exit "${failures}"
```

Run `bash scripts/tests/test-make-ci-parity.sh`. Expected: FAIL (6 missing).

- [ ] **Step 2: Add the targets.** In `Makefile` (add each name to `.PHONY`):

```make
OPA_VERSION ?= 1.22.2

yamllint: ## yamllint exactly as CI (the pre-commit hook config)
	@$(PRE_COMMIT) run yamllint --all-files

markdownlint-check: ## markdownlint as CI; the hook runs --fix, so any diff is a failure
	@$(PRE_COMMIT) run markdownlint --all-files || true
	@git diff --exit-code -- '*.md' || { echo "markdownlint changed files: review and commit the fixes"; exit 1; }

commit-check: ## Conventional-commit check on this branch's commits (CI: meta-lint)
	@base="$$(git merge-base origin/main HEAD)"; cz check --rev-range "$$base..HEAD"

opa-test: ## opa check --strict + opa test on both policy sets (CI: opa)
	@v="$$(opa version 2>/dev/null | awk '/^Version:/{print $$2}')"; \
	[ "$$v" = "$(OPA_VERSION)" ] || { echo "opa $$v != CI-pinned $(OPA_VERSION)"; exit 1; }
	@opa check --strict policies/opa policies/opa-destructive
	@opa test policies/opa policies/opa-destructive

codeowners-check: ## Fail on placeholder CODEOWNERS when CODEOWNERS_ENFORCE=true (CI: codeowners)
	@if [ "$${CODEOWNERS_ENFORCE:-false}" = "true" ] && grep -q '@your-org/' .github/CODEOWNERS; then \
		echo "CODEOWNERS still has @your-org placeholders"; exit 1; fi

zizmor: ## GitHub Actions static analysis (CI: meta-lint), see Task 19
	@zizmor --min-severity medium .github/workflows
```

Add to the `ci:` recipe, after `@$(MAKE) consistency`:

```make
	@$(MAKE) yamllint
	@$(MAKE) markdownlint-check
	@$(MAKE) commit-check
	@$(MAKE) codeowners-check
	@$(MAKE) zizmor
```

and after `@$(MAKE) test`: `@$(MAKE) opa-test`. Add `opa 1.22.2` to `.tool-versions` and make `terraform-plan.yml` read it (Task 21 brings all versions under one source). Until Task 19 lands, the `zizmor` target can fail; land Task 6 and Task 19 in the same PR if needed.

- [ ] **Step 3: Verify.** `bash scripts/tests/test-make-ci-parity.sh` PASS; `make opa-test yamllint` PASS.
- [ ] **Step 4: Commit.** `git commit -am "build(make): run every CI gate from make ci"`

---

## Phase 1: Codified GitHub governance (CICD-1, CICD-3, CICD-4, CICD-8, CICD-9)

## Task 7: Scaffold `envs/github-admin` with failing tests (A)

**Files:**
- Create: `envs/github-admin/{versions.tf,backend.tf,providers.tf,config.tf,variables.tf,main.tf,outputs.tf,README.md}`
- Create: `envs/github-admin/tests/{root.tftest.hcl,variables_validation.tftest.hcl,config.tftest.hcl}`
- Create: `envs/github-admin/tests/fixtures/landing-zone-github.yaml`

- [ ] **Step 1: Write the failing root test** `envs/github-admin/tests/root.tftest.hcl`:

```hcl
# Plan assertions for the GitHub governance root. No credentials: the github
# provider is mocked. Every protection an auditor asks about is pinned here.

mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      id = "37066413"
    }
  }
}

variables {
  landing_zone_config_path  = ""
  owner                     = "acme"
  repository                = "landing-zone"
  maintainers               = ["alice", "bob"]
  adopt_existing_repository = false
}

run "main_ruleset_requires_review_signatures_and_summary" {
  command = plan

  assert {
    condition     = github_repository_ruleset.main.enforcement == "active" && github_repository_ruleset.main.target == "branch"
    error_message = "The main ruleset must be an active branch ruleset."
  }
  assert {
    condition     = github_repository_ruleset.main.conditions[0].ref_name[0].include == ["~DEFAULT_BRANCH"]
    error_message = "The main ruleset must target the default branch."
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].required_approving_review_count == 1
    error_message = "One approving review is the default."
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].require_last_push_approval && github_repository_ruleset.main.rules[0].pull_request[0].dismiss_stale_reviews_on_push
    error_message = "The last push must be approved by someone else, and stale approvals dismissed."
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].allowed_merge_methods == ["squash"]
    error_message = "Squash-only merges keep main linear and GitHub-signed."
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].required_signatures && github_repository_ruleset.main.rules[0].non_fast_forward && github_repository_ruleset.main.rules[0].deletion
    error_message = "main must require signatures and block force-push and deletion."
  }
  assert {
    condition     = [for c in github_repository_ruleset.main.rules[0].required_status_checks[0].required_check : c.context] == ["Validation Summary"]
    error_message = "Exactly one required context: Validation Summary."
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].required_status_checks[0].strict_required_status_checks_policy
    error_message = "PRs must be tested against the latest main."
  }
  assert {
    condition     = length(github_repository_ruleset.main.bypass_actors) == 0
    error_message = "The default is no bypass at all (enforce_admins)."
  }
}

run "admin_bypass_is_pull_request_only_when_opted_in" {
  command = plan
  variables {
    admin_bypass = "pull_request"
  }
  assert {
    condition     = length(github_repository_ruleset.main.bypass_actors) == 1 && github_repository_ruleset.main.bypass_actors[0].actor_type == "RepositoryRole" && github_repository_ruleset.main.bypass_actors[0].actor_id == 5 && github_repository_ruleset.main.bypass_actors[0].bypass_mode == "pull_request"
    error_message = "The interim bypass is the admin role, pull-request mode only."
  }
  expect_failures = [check.no_standing_bypass]
}

run "every_workflow_environment_exists_and_is_scoped" {
  command = plan
  assert {
    condition = alltrue([for e in ["docs-bot", "release", "tfc-drift", "tfc-readonly", "tfc-state-backup", "e2e-sandbox", "estate-probe", "production-promotion"] : contains(keys(github_repository_environment.this), e)])
    error_message = "Every environment a workflow names must be declared, so GitHub never auto-creates an unprotected one."
  }
  assert {
    condition     = alltrue([for k, e in github_repository_environment.this : e.can_admins_bypass == false])
    error_message = "Admins must not bypass environment protection."
  }
  assert {
    condition     = github_repository_environment_deployment_policy.branch["release:branch:main"].branch_pattern == "main"
    error_message = "release deploys from main only."
  }
  assert {
    condition     = github_repository_environment_deployment_policy.tag["tfc-readonly:tag:*/v*"].tag_pattern == "*/v*" && !contains(keys(github_repository_environment_deployment_policy.branch), "tfc-readonly:branch:main")
    error_message = "tfc-readonly is used by terraform-apply.yml on deployment tags only."
  }
  assert {
    condition     = length(github_repository_environment.this["e2e-sandbox"].deployment_branch_policy) == 0
    error_message = "e2e-sandbox stays unrestricted: label-gated PR runs deploy from refs/pull/*."
  }
}

run "reviewed_environments_enforce_four_eyes_with_two_maintainers" {
  command = plan
  assert {
    condition     = github_repository_environment.this["production-promotion"].prevent_self_review && github_repository_environment.this["e2e-sandbox"].prevent_self_review
    error_message = "With two maintainers, the person who starts a reviewed job cannot approve it."
  }
  assert {
    condition     = length(github_repository_environment.this["production-promotion"].reviewers[0].users) == 2
    error_message = "Every maintainer is a reviewer."
  }
}

run "single_maintainer_is_flagged" {
  command = plan
  variables {
    maintainers = ["alice"]
  }
  assert {
    condition     = github_repository_environment.this["production-promotion"].prevent_self_review == false
    error_message = "With one maintainer, prevent_self_review would block every run."
  }
  expect_failures = [check.four_eyes]
}

run "security_settings_and_actions_allow_list" {
  command = plan
  variables {
    adopt_existing_repository = true
  }
  assert {
    condition     = github_repository.this["landing-zone"].security_and_analysis[0].secret_scanning[0].status == "enabled" && github_repository.this["landing-zone"].security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled"
    error_message = "Secret scanning and push protection must be on."
  }
  assert {
    condition     = github_repository.this["landing-zone"].allow_merge_commit == false && github_repository.this["landing-zone"].allow_rebase_merge == false && github_repository.this["landing-zone"].allow_squash_merge
    error_message = "Squash is the only merge method."
  }
  assert {
    condition     = github_repository_vulnerability_alerts.this.enabled && github_repository_dependabot_security_updates.this.enabled
    error_message = "Dependabot alerts and security updates must be on."
  }
  assert {
    condition     = github_actions_repository_permissions.this.allowed_actions == "selected" && github_actions_repository_permissions.this.sha_pinning_required && github_actions_repository_permissions.this.allowed_actions_config[0].verified_allowed == false
    error_message = "Actions must be an explicit, SHA-pinned allow-list."
  }
}

run "release_tags_only_the_release_app_creates" {
  command = plan
  variables {
    release_app_id = 123456
  }
  assert {
    condition     = github_repository_ruleset.release_tags.rules[0].creation && github_repository_ruleset.release_tags.rules[0].update && github_repository_ruleset.release_tags.rules[0].deletion
    error_message = "Release tags are create-restricted and immutable."
  }
  assert {
    condition     = github_repository_ruleset.release_tags.bypass_actors[0].actor_type == "Integration" && github_repository_ruleset.release_tags.bypass_actors[0].actor_id == 123456
    error_message = "Only the release App may create release tags."
  }
  assert {
    condition     = github_repository_ruleset.deployment_tags.rules[0].update && github_repository_ruleset.deployment_tags.rules[0].deletion
    error_message = "Deployment tags (<root>/vX) are immutable once pushed."
  }
}

run "production_branch_moves_only_through_the_release_app" {
  command = plan
  variables {
    release_app_id    = 123456
    production_branch = "production"
  }
  assert {
    condition     = github_repository_ruleset.production[0].conditions[0].ref_name[0].include == ["refs/heads/production"]
    error_message = "The production ruleset must target refs/heads/production."
  }
  assert {
    condition     = github_repository_ruleset.production[0].rules[0].update && github_repository_ruleset.production[0].rules[0].non_fast_forward && github_repository_ruleset.production[0].bypass_actors[0].actor_id == 123456
    error_message = "Only the release App may update production, and only by fast-forward."
  }
}
```

Note: the `adopt_existing_repository = true` run exercises the import block under `mock_provider`. If Terraform 1.17.1 mock providers reject the import, set the variable to `false` in that run and move the import check to Task 14 step 3.

- [ ] **Step 2: Write the failing validation suite** `envs/github-admin/tests/variables_validation.tftest.hcl`:

```hcl
mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      id = "1"
    }
  }
}

variables {
  landing_zone_config_path  = ""
  owner                     = "acme"
  repository                = "landing-zone"
  maintainers               = ["alice", "bob"]
  adopt_existing_repository = false
}

run "zero_approvals_rejected" {
  command = plan
  variables {
    required_approvals = 0
  }
  expect_failures = [var.required_approvals]
}

run "seven_approvals_rejected" {
  command = plan
  variables {
    required_approvals = 7
  }
  expect_failures = [var.required_approvals]
}

run "always_bypass_rejected" {
  command = plan
  variables {
    admin_bypass = "always"
  }
  expect_failures = [var.admin_bypass]
}

run "bad_username_rejected" {
  command = plan
  variables {
    maintainers = ["not a user"]
  }
  expect_failures = [var.maintainers]
}

run "bad_production_branch_rejected" {
  command = plan
  variables {
    production_branch = "prod branch"
  }
  expect_failures = [var.production_branch]
}

run "unknown_auth_mode_rejected" {
  command = plan
  variables {
    github_auth_mode = "password"
  }
  expect_failures = [var.github_auth_mode]
}
```

- [ ] **Step 3: Write the failing config-fallback suite** `envs/github-admin/tests/config.tftest.hcl` and its fixture:

```hcl
mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      id = "1"
    }
  }
}

variables {
  landing_zone_config_path  = "tests/fixtures/landing-zone-github.yaml"
  adopt_existing_repository = false
}

run "owner_and_repository_from_vcs_identifier" {
  command = plan
  assert {
    condition     = github_repository_ruleset.main.repository == "landing-zone"
    error_message = "repository falls back to the repo part of org.tfc.vcs_repo.identifier."
  }
  assert {
    condition     = output.owner == "acme"
    error_message = "owner falls back to the owner part of org.tfc.vcs_repo.identifier."
  }
}

run "maintainers_and_bypass_from_config" {
  command = plan
  assert {
    condition     = length(github_repository_environment.this["production-promotion"].reviewers[0].users) == 2
    error_message = "github.maintainers feeds the environment reviewers."
  }
  assert {
    condition     = github_repository_ruleset.main.bypass_actors[0].bypass_mode == "pull_request"
    error_message = "github.admin_bypass feeds the ruleset bypass."
  }
  expect_failures = [check.no_standing_bypass]
}
```

`envs/github-admin/tests/fixtures/landing-zone-github.yaml`:

```yaml
version: 1
org:
  name: acme
  tfc:
    organization: acme
    vcs_repo:
      identifier: acme/landing-zone
      branch: main
      github_app_installation_id: ghain-test
github:
  enabled: true
  maintainers: [alice, bob]
  admin_bypass: pull_request
```

- [ ] **Step 4: Run, expect failure.** `make test TEST_DIRS=envs/github-admin TERRAFORM=$TF`. Expected: FAIL (no configuration files).

- [ ] **Step 5: Create the root scaffolding.**

`envs/github-admin/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    github = {
      source = "integrations/github"
      # Floor = the version the lockfile pins and the tests exercise
      # (repository_ruleset allowed_merge_methods, sha_pinning_required,
      # repository_vulnerability_alerts). Majors are a deliberate upgrade.
      version = ">= 6.13.0, < 7.0.0"
    }
  }
}
```

`envs/github-admin/backend.tf`:

```hcl
terraform {
  # HCP Terraform. export TF_CLOUD_ORGANIZATION=<your-tfc-org>
  cloud {
    workspaces {
      name = "github-admin"
    }
  }
}
```

`envs/github-admin/providers.tf`:

```hcl
# Authenticates as the github-admin GitHub App installation (D3): the HCP
# workspace holds GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID and
# GITHUB_APP_PEM_FILE (sensitive) as env vars. github_auth_mode = "token" uses
# GITHUB_TOKEN instead, for a local read-only plan by an admin.
provider "github" {
  owner = local.owner

  dynamic "app_auth" {
    for_each = var.github_auth_mode == "app" ? [1] : []
    content {}
  }
}
```

`envs/github-admin/config.tf`:

```hcl
# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Precedence: explicit variable > config file > built-in default.
# local.cfg holds ONLY config-file values (it references no variable except
# landing_zone_config_path: the variable validations read it).
locals {
  landing_zone_config_file = var.landing_zone_config_path == "" ? null : (
    var.landing_zone_config_path == null ? "${path.root}/../../config/landing-zone.yaml" : (
      startswith(var.landing_zone_config_path, "/") ? var.landing_zone_config_path : "${path.root}/${var.landing_zone_config_path}"
    )
  )
  lz_documents = [
    for f in compact([local.landing_zone_config_file != null && fileexists(coalesce(local.landing_zone_config_file, "/nonexistent")) ? local.landing_zone_config_file : ""]) :
    yamldecode(file(f))
  ]
  lz = try(local.lz_documents[0], {})

  # owner/repository default to the TFC VCS connection, so the repo is named once.
  lz_vcs_identifier = try(tostring(local.lz.org.tfc.vcs_repo.identifier), null)

  cfg = {
    owner              = try(tostring(local.lz.github.owner), split("/", local.lz_vcs_identifier)[0], null)
    repository         = try(tostring(local.lz.github.repository), split("/", local.lz_vcs_identifier)[1], null)
    maintainers        = try([for u in local.lz.github.maintainers : tostring(u)], null)
    required_approvals = try(tonumber(local.lz.github.required_approvals), null)
    admin_bypass       = try(tostring(local.lz.github.admin_bypass), null)
    release_app_id     = try(tonumber(local.lz.github.release_app_id), null)
    # Shared with tfc-admin (Task 15): one key decides which branch production
    # workload workspaces track and which branch this root protects.
    production_branch = try(tostring(local.lz.org.tfc.vcs_repo.production_branch), null)
  }
}
```

`envs/github-admin/variables.tf`:

```hcl
variable "landing_zone_config_path" {
  description = "Path to the single-source config, relative to this root or absolute. Null reads ../../config/landing-zone.yaml; \"\" disables the file (tests)."
  type        = string
  default     = null
}

variable "github_auth_mode" {
  description = "github provider authentication: app (GitHub App env vars, the HCP default) or token (GITHUB_TOKEN, for a local read-only plan)."
  type        = string
  default     = "app"
  validation {
    condition     = contains(["app", "token"], var.github_auth_mode)
    error_message = "github_auth_mode must be app or token."
  }
}

variable "owner" {
  description = "GitHub user or organization that owns the repository. Null = github.owner, else the owner part of org.tfc.vcs_repo.identifier."
  type        = string
  default     = null
}

variable "repository" {
  description = "Repository name. Null = github.repository, else the repo part of org.tfc.vcs_repo.identifier."
  type        = string
  default     = null
}

variable "maintainers" {
  description = "GitHub usernames who review protected environment jobs (e2e-sandbox, production-promotion). Null = github.maintainers. Two or more turn on prevent_self_review."
  type        = list(string)
  default     = null
  validation {
    condition = var.maintainers == null || (
      length(coalesce(var.maintainers, [])) <= 6 &&
      alltrue([for u in coalesce(var.maintainers, []) : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", u))])
    )
    error_message = "maintainers must be at most 6 valid GitHub usernames (github.maintainers)."
  }
}

variable "required_approvals" {
  description = "Approving reviews required on main. Null = github.required_approvals, else 1."
  type        = number
  default     = null
  validation {
    condition     = var.required_approvals == null || (coalesce(var.required_approvals, 1) >= 1 && coalesce(var.required_approvals, 1) <= 6)
    error_message = "required_approvals (github.required_approvals) must be between 1 and 6."
  }
}

variable "admin_bypass" {
  description = "Who may bypass the main ruleset: none (enforce for admins, the default) or pull_request (the admin role may merge a PR that fails a rule; each bypass is logged). Null = github.admin_bypass."
  type        = string
  default     = null
  validation {
    condition     = contains(["none", "pull_request"], coalesce(var.admin_bypass, local.cfg.admin_bypass, "none"))
    error_message = "admin_bypass (github.admin_bypass) must be none or pull_request; always would let an admin push to main."
  }
}

variable "release_app_id" {
  description = "App ID of the release GitHub App (D5). It alone may create vX.Y.Z tags and move the production branch. Null = github.release_app_id; null disables tag creation for everyone."
  type        = number
  default     = null
}

variable "production_branch" {
  description = "Branch the production workload workspaces track (Task 15). Null = org.tfc.vcs_repo.production_branch; null = no production branch ruleset."
  type        = string
  default     = null
  validation {
    condition     = var.production_branch == null || can(regex("^[A-Za-z0-9._/-]+$", coalesce(var.production_branch, "x")))
    error_message = "production_branch must be a plain branch name."
  }
}

variable "status_check_context" {
  description = "The single required status check (the fail-closed aggregator in terraform-plan.yml)."
  type        = string
  default     = "Validation Summary"
}

variable "actions_integration_id" {
  description = "GitHub App ID the required check must come from. 15368 is GitHub Actions."
  type        = number
  default     = 15368
}

variable "adopt_existing_repository" {
  description = "Import the existing repository into state on the first plan (import block). Tests set false."
  type        = bool
  default     = true
}
```

`envs/github-admin/main.tf`:

```hcl
locals {
  owner              = var.owner != null ? var.owner : local.cfg.owner
  repository         = var.repository != null ? var.repository : local.cfg.repository
  maintainers        = var.maintainers != null ? var.maintainers : (local.cfg.maintainers != null ? local.cfg.maintainers : [])
  required_approvals = coalesce(var.required_approvals, local.cfg.required_approvals, 1)
  admin_bypass       = coalesce(var.admin_bypass, local.cfg.admin_bypass, "none")
  release_app_id     = var.release_app_id != null ? var.release_app_id : local.cfg.release_app_id
  production_branch  = var.production_branch != null ? var.production_branch : local.cfg.production_branch
  four_eyes          = length(local.maintainers) >= 2
}

check "four_eyes" {
  assert {
    condition     = local.four_eyes
    error_message = "Only ${length(local.maintainers)} maintainer(s): reviewed environments cannot prevent self-review, so one person can approve their own production promotion. Add a second maintainer (github.maintainers)."
  }
}

check "no_standing_bypass" {
  assert {
    condition     = local.admin_bypass == "none"
    error_message = "github.admin_bypass = ${local.admin_bypass}: the admin role can merge without review. Keep this only as a dated exception in docs/known-gaps.md."
  }
}
```

`envs/github-admin/outputs.tf`:

```hcl
output "owner" {
  description = "Effective repository owner."
  value       = local.owner
}

output "repository" {
  description = "Effective repository name."
  value       = local.repository
}
```

Add `README.md` with a short purpose paragraph and the `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers, then `make docs`.

- [ ] **Step 6: Lock the provider for three platforms.**

```bash
$TF -chdir=envs/github-admin init -backend=false
$TF -chdir=envs/github-admin providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

- [ ] **Step 7: Run.** `make test TEST_DIRS=envs/github-admin TERRAFORM=$TF`. Expected: `variables_validation` PASS; `root` and `config` still FAIL (resources missing). That is the hand-off to Task 8 to 10.

- [ ] **Step 8: Commit.** `git commit -m "feat(github-admin): scaffold the GitHub governance root and its tests"` (add the new files).

---

## Task 8: Rulesets for `main`, tags and `production` (A) (CICD-1, CICD-7, CICD-8)

**Files:**
- Create: `envs/github-admin/rulesets.tf`
- Modify: `envs/github-admin/outputs.tf`

- [ ] **Step 1: Write `rulesets.tf`.**

```hcl
# ── main: every change reviewed, signed, green ─────────────────────────────
resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = local.repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # Default: nobody bypasses (enforce_admins). pull_request mode is a dated
  # one-maintainer exception (D2); GitHub logs every bypass in rule insights.
  dynamic "bypass_actors" {
    for_each = local.admin_bypass == "none" ? [] : [local.admin_bypass]
    content {
      actor_id    = 5 # RepositoryRole: admin
      actor_type  = "RepositoryRole"
      bypass_mode = bypass_actors.value
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    # Squash merges are committed and signed by GitHub, so no contributor
    # needs a signing key and every new commit on main is verified (D12).
    required_signatures = true

    pull_request {
      allowed_merge_methods             = ["squash"]
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = true
      require_last_push_approval        = true
      required_approving_review_count   = local.required_approvals
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true
      required_check {
        context        = var.status_check_context
        integration_id = var.actions_integration_id
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.owner != null && local.repository != null
      error_message = "Set github.owner and github.repository, or org.tfc.vcs_repo.identifier (owner/repo), in config/landing-zone.yaml."
    }
  }
}

# ── vX.Y.Z release tags: only the release App creates; nobody moves or deletes
resource "github_repository_ruleset" "release_tags" {
  name        = "release-tags"
  repository  = local.repository
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
  }

  dynamic "bypass_actors" {
    for_each = local.release_app_id == null ? [] : [local.release_app_id]
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }

  rules {
    creation = true
    update   = true
    deletion = true
  }
}

# ── <root>/vX and <root>/<env>/vX deployment tags (terraform-apply.yml):
# maintainers may create them; nobody may move or delete one.
resource "github_repository_ruleset" "deployment_tags" {
  name        = "deployment-tags"
  repository  = local.repository
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/*/v*", "refs/tags/*/*/v*"]
      exclude = []
    }
  }

  rules {
    update   = true
    deletion = true
  }
}

# ── production: moved only by promote.yml (release App), fast-forward only.
resource "github_repository_ruleset" "production" {
  count = local.production_branch == null ? 0 : 1

  name        = "production"
  repository  = local.repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/heads/${local.production_branch}"]
      exclude = []
    }
  }

  dynamic "bypass_actors" {
    for_each = local.release_app_id == null ? [] : [local.release_app_id]
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }

  rules {
    creation         = true
    update           = true
    deletion         = true
    non_fast_forward = true
  }

  lifecycle {
    precondition {
      condition     = local.release_app_id != null
      error_message = "A production branch needs github.release_app_id: otherwise nothing may ever promote to it."
    }
  }
}
```

Append to `outputs.tf`:

```hcl
output "ruleset_ids" {
  description = "Ruleset IDs, for gh api repos/<owner>/<repo>/rulesets/<id>."
  value = {
    main            = github_repository_ruleset.main.ruleset_id
    release_tags    = github_repository_ruleset.release_tags.ruleset_id
    deployment_tags = github_repository_ruleset.deployment_tags.ruleset_id
    production      = try(github_repository_ruleset.production[0].ruleset_id, null)
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=envs/github-admin TERRAFORM=$TF`. Expected: the ruleset runs PASS; environment and settings runs still FAIL.

- [ ] **Step 3: Update `scripts/check-required-checks.sh --live`** to read the effective rules (rulesets) and to fail while classic protection still exists. Replace lines 65-83 with:

```bash
  if ! rules=$(gh api "repos/${repo}/rules/branches/${branch}" 2>&1); then
    echo "ERROR: cannot read rules for ${repo}@${branch}: ${rules}" >&2
    exit 1
  fi
  want=$(printf '%s\n' "$contexts_line" | sed -E 's/^"contexts":\[//; s/\]$//' | tr ',' '\n' | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' | sort -u)
  have=$(jq -r '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' <<<"$rules" | sort -u)
  if [ "$want" != "$have" ]; then
    echo "ERROR: live required contexts on ${repo}@${branch} differ from $doc" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$have") | sed 's/^</  doc only: /; s/^>/  live only:/' | grep -E 'only' >&2 || true
    fail=1
  fi
  approvals=$(jq -r '[.[] | select(.type=="pull_request") | .parameters.required_approving_review_count] | max // 0' <<<"$rules")
  [ "$approvals" -ge 1 ] || { echo "ERROR: ${repo}@${branch} requires ${approvals} approvals" >&2; fail=1; }
  jq -e '.[] | select(.type=="required_signatures")' <<<"$rules" >/dev/null || { echo "ERROR: ${repo}@${branch} does not require signatures" >&2; fail=1; }
  if gh api "repos/${repo}/branches/${branch}/protection" >/dev/null 2>&1; then
    echo "ERROR: classic branch protection still exists on ${repo}@${branch}; the ruleset (envs/github-admin) replaces it (docs/guides/BRANCH_PROTECTION.md)" >&2
    fail=1
  fi
```

Rewrite `docs/guides/BRANCH_PROTECTION.md` so it says the rules are codified in `envs/github-admin/rulesets.tf`, keeps the `"contexts":["Validation Summary"]` line that the offline check parses, and keeps the manual `gh api` commands only as the break-glass path.

- [ ] **Step 4: Verify.** `make required-checks` PASS (offline mode unchanged). `bash -n scripts/check-required-checks.sh`. `make shellcheck`.

- [ ] **Step 5: Commit.** `git commit -am "feat(github-admin): codify the main, tag and production rulesets"`

---

## Task 9: Environments and deployment policies (A) (CICD-4)

**Files:**
- Create: `envs/github-admin/environments.tf`
- Create: `scripts/check-github-governance.sh`, `scripts/tests/test-check-github-governance.sh`

- [ ] **Step 1: Write the failing parity test** `scripts/tests/test-check-github-governance.sh`. It builds a temp repo with one workflow naming `environment: ghost` and expects the checker to fail with `ghost`; then a workflow naming `release` and expects a pass. Use the `expect_fail` / `expect_pass` pattern of `scripts/tests/test-check-contracts.sh`. Run it: FAIL (script missing).

- [ ] **Step 2: Write `environments.tf`.**

```hcl
# Every environment a workflow names (scripts/check-github-governance.sh keeps
# this list and .github/workflows in step). Declaring them all means GitHub
# never auto-creates an unprotected one on first use.
#   branches/tags = deployment policy patterns (fnmatch: * does not match /)
#   branches = null  -> unrestricted (label-gated PR runs deploy from refs/pull/*)
#   reviewed         -> a maintainer must approve each job
locals {
  environments = {
    "docs-bot"             = { branches = ["main"], tags = [], reviewed = false }
    "release"              = { branches = ["main"], tags = [], reviewed = false }
    "tfc-drift"            = { branches = ["main"], tags = [], reviewed = false }
    "tfc-state-backup"     = { branches = ["main"], tags = [], reviewed = false }
    "tfc-readonly"         = { branches = [], tags = ["*/v*", "*/*/v*"], reviewed = false }
    "e2e-sandbox"          = { branches = null, tags = [], reviewed = true }
    "estate-probe"         = { branches = ["main"], tags = [], reviewed = false }
    "tfc-promotion-plan"   = { branches = ["main"], tags = [], reviewed = false }
    "production-promotion" = { branches = ["main"], tags = [], reviewed = true }
  }

  environment_policies = merge(
    { for p in flatten([
      for e, v in local.environments : [for b in(v.branches == null ? [] : v.branches) : { key = "${e}:branch:${b}", env = e, pattern = b }]
    ]) : p.key => p },
    { for p in flatten([
      for e, v in local.environments : [for t in v.tags : { key = "${e}:tag:${t}", env = e, pattern = t }]
    ]) : p.key => p },
  )
}

data "github_user" "maintainer" {
  for_each = toset(local.maintainers)
  username = each.key
}

resource "github_repository_environment" "this" {
  for_each = local.environments

  repository          = local.repository
  environment         = each.key
  can_admins_bypass   = false
  prevent_self_review = each.value.reviewed && local.four_eyes

  dynamic "reviewers" {
    for_each = each.value.reviewed ? [1] : []
    content {
      users = [for u in local.maintainers : tonumber(data.github_user.maintainer[u].id)]
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = each.value.branches == null ? [] : [1]
    content {
      protected_branches     = false
      custom_branch_policies = true
    }
  }

  lifecycle {
    precondition {
      condition     = !each.value.reviewed || length(local.maintainers) > 0
      error_message = "Environment ${each.key} needs a reviewer: set github.maintainers in config/landing-zone.yaml."
    }
  }
}

resource "github_repository_environment_deployment_policy" "branch" {
  for_each = { for k, p in local.environment_policies : k => p if strcontains(k, ":branch:") }

  repository     = local.repository
  environment    = github_repository_environment.this[each.value.env].environment
  branch_pattern = each.value.pattern
}

resource "github_repository_environment_deployment_policy" "tag" {
  for_each = { for k, p in local.environment_policies : k => p if strcontains(k, ":tag:") }

  repository  = local.repository
  environment = github_repository_environment.this[each.value.env].environment
  tag_pattern = each.value.pattern
}
```

- [ ] **Step 3: Write `scripts/check-github-governance.sh`.**

```bash
#!/usr/bin/env bash
# The GitHub settings in envs/github-admin must match what the workflows use:
#   1. every `environment:` a workflow names is declared in environments.tf;
#   2. every third-party `uses:` owner/repo is in actions.tf allowed patterns.
# Usage: check-github-governance.sh [repo-root]   (CI: meta-lint, make consistency)
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
wf="${root}/.github/workflows"
envs_tf="${root}/envs/github-admin/environments.tf"
actions_tf="${root}/envs/github-admin/actions.tf"
fail=0

declared_envs=$(sed -nE 's/^[[:space:]]*"([a-z0-9-]+)"[[:space:]]*=[[:space:]]*\{[[:space:]]*branches.*/\1/p' "$envs_tf" | sort -u)
used_envs=$(grep -hE '^[[:space:]]+environment:[[:space:]]*[a-z0-9-]+[[:space:]]*$' "$wf"/*.yml | awk '{print $2}' | sort -u)
for e in $(comm -13 <(printf '%s\n' "$declared_envs") <(printf '%s\n' "$used_envs")); do
  echo "FAIL: workflow environment '${e}' is not declared in envs/github-admin/environments.tf" >&2
  fail=1
done

if [ -f "$actions_tf" ]; then
  allowed=$(sed -nE 's/^[[:space:]]*"([^"@]+)@\*",?$/\1/p' "$actions_tf" | sort -u)
  used=$(grep -rhoE 'uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@' "$wf" | sed -E 's/uses:[[:space:]]+//; s/@$//' | grep -vE '^(actions|github)/' | sort -u)
  for a in $(comm -13 <(printf '%s\n' "$allowed") <(printf '%s\n' "$used")); do
    echo "FAIL: action '${a}' is used by a workflow but not allowed in envs/github-admin/actions.tf" >&2
    fail=1
  done
fi
[ "$fail" -eq 0 ] && echo "check-github-governance: environments and actions match the workflows"
exit "$fail"
```

Call it from `scripts/check-consistency.sh` (one `echo "==> ..."` section that runs it and sets `fail=1` on error).

- [ ] **Step 4: Run.** `bash scripts/tests/test-check-github-governance.sh` PASS; `make test TEST_DIRS=envs/github-admin TERRAFORM=$TF`: environment runs PASS.
- [ ] **Step 5: Commit.** `git commit -am "feat(github-admin): declare every workflow environment with deployment policies"`

---

## Task 10: Repository security settings and the Actions allow-list (A) (CICD-9)

**Files:**
- Create: `envs/github-admin/repository.tf`, `envs/github-admin/actions.tf`

- [ ] **Step 1: Write `repository.tf`.** Values mirror the live settings read on 2026-11-11, so adoption changes only the security and merge settings.

```hcl
# Adopt the existing repository on the first plan (never recreate it).
import {
  for_each = var.adopt_existing_repository ? toset([local.repository]) : toset([])
  to       = github_repository.this[each.key]
  id       = each.value
}

resource "github_repository" "this" {
  for_each = toset([local.repository])

  name       = each.key
  visibility = "public"

  has_issues      = true
  has_projects    = true
  has_wiki        = true
  has_discussions = false
  has_downloads   = false

  # Squash only (D12): GitHub signs the squash commit. Titles stay
  # COMMIT_OR_PR_TITLE / COMMIT_MESSAGES so release-please still reads
  # Conventional Commit subjects.
  allow_merge_commit          = false
  allow_rebase_merge          = false
  allow_squash_merge          = true
  squash_merge_commit_title   = "COMMIT_OR_PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"
  allow_auto_merge            = false
  allow_update_branch         = true
  delete_branch_on_merge      = true

  archive_on_destroy = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
    secret_scanning_non_provider_patterns {
      status = "enabled"
    }
  }

  lifecycle {
    prevent_destroy = true
    # Presentation fields stay owned by the UI.
    ignore_changes = [description, homepage_url, topics, pages, template]
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this[local.repository].name
  enabled    = true
}

resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this[local.repository].name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
}
```

Read `docs/resources/repository_vulnerability_alerts.md` at provider tag `v6.13.0` before writing the resource; adjust argument names if they differ.

- [ ] **Step 2: Write `actions.tf`.** The patterns are every third-party action the workflows use today, plus the ones Tasks 18 and 16 add, plus the actions those composite actions call.

```hcl
# Actions may run only if GitHub-owned or listed here, and only when pinned to
# a full SHA. scripts/check-github-governance.sh fails CI when a workflow uses
# an action that is not listed. One "<owner>/<repo>@*" entry per line.
locals {
  allowed_action_patterns = [
    "anchore/sbom-action@*",
    "anchore/sbom-action/download-syft@*",
    "aquasecurity/setup-trivy@*",
    "aquasecurity/trivy-action@*",
    "aws-actions/configure-aws-credentials@*",
    "bridgecrewio/checkov-action@*",
    "gitleaks/gitleaks-action@*",
    "google-github-actions/auth@*",
    "googleapis/release-please-action@*",
    "hashicorp/setup-terraform@*",
    "hashicorp/tfc-workflows-github/actions/create-run@*",
    "hashicorp/tfc-workflows-github/actions/upload-configuration@*",
    "peter-evans/create-pull-request@*",
    "pre-commit/action@*",
    "softprops/action-gh-release@*",
    "step-security/harden-runner@*",
    "terraform-linters/setup-tflint@*",
  ]
}

resource "github_actions_repository_permissions" "this" {
  repository           = github_repository.this[local.repository].name
  enabled              = true
  allowed_actions      = "selected"
  sha_pinning_required = true

  allowed_actions_config {
    github_owned_allowed = true
    verified_allowed     = false
    patterns_allowed     = local.allowed_action_patterns
  }
}
```

The governance script's `sed` reads `"<owner>/<repo>@*"` lines; keep one entry per line. For sub-path actions (`hashicorp/tfc-workflows-github/actions/create-run`) the script compares the full path, which matches.

- [ ] **Step 3: Run.** `make test TEST_DIRS=envs/github-admin TERRAFORM=$TF`. Expected: all runs in all three suites PASS. `bash scripts/check-github-governance.sh` PASS.
- [ ] **Step 4: Commit.** `git commit -am "feat(github-admin): turn on secret scanning, Dependabot and a SHA-pinned actions allow-list"`

---

## Task 11: Register the new root everywhere the repo expects (A)

**Files:**
- Modify: `config/landing-zone.schema.json`, `config/landing-zone.example.yaml`
- Modify: `envs/tfc-admin/{config.tf,variables.tf,main.tf}`, `envs/tfc-admin/tests/catalog.tftest.hcl`
- Modify: `.github/CODEOWNERS`, `CLAUDE.md`, `README.md`, `envs/README.md`, `docs/architecture/provider-selection.md`
- Modify: `.github/workflows/drift-detection.yml` (default workspace list)

- [ ] **Step 1: Write the failing tfc-admin test.** Append to `envs/tfc-admin/tests/catalog.tftest.hcl`:

```hcl
run "github_admin_workspace_only_when_enabled" {
  command = plan

  assert {
    condition     = !contains(keys(module.workspace), "github-admin")
    error_message = "github-admin is off by default."
  }
}

run "github_admin_workspace_is_control_plane" {
  command = plan

  variables {
    enable_github_admin = true
  }

  assert {
    condition     = module.workspace["github-admin"].working_directory == "envs/github-admin"
    error_message = "github-admin runs from envs/github-admin."
  }
  assert {
    condition     = module.workspace["github-admin"].speculative_enabled == false && module.workspace["github-admin"].auto_apply == false
    error_message = "github-admin is control plane: no speculative PR plans, never auto-apply."
  }
  assert {
    condition     = contains(module.workspace["github-admin"].tag_names, "layer:control-plane")
    error_message = "The control-plane tag puts github-admin under tfc_admin_guard's no-auto-apply rule."
  }
}
```

Run `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`: FAIL (unknown variable).

- [ ] **Step 2: tfc-admin changes.**

`variables.tf`:

```hcl
variable "enable_github_admin" {
  description = "Create the github-admin workspace (envs/github-admin: rulesets, environments, security settings). Null = github.enabled in config/landing-zone.yaml, else false."
  type        = bool
  default     = null
}
```

`config.tf`, inside `cfg`: `enable_github_admin = try(tobool(local.lz.github.enabled), null)`; and in the effective locals: `enable_github_admin = coalesce(var.enable_github_admin, local.cfg.enable_github_admin, false)`.

`main.tf`, in `root_trigger_dirs` (the consistency check needs at least one listed path per catalog root):

```hcl
    "envs/github-admin" = [
      ".github/workflows",
    ]
```

and replace `catalog_platform` / `catalog_cloud_enabled.platform`:

```hcl
  catalog_platform = merge(
    var.manage_tfc_admin_workspace ? {
      (var.tfc_admin_workspace_name) = {
        dir = "envs/tfc-admin", cloud = "platform", desc = "TFC workspace layer (this root)", tags = ["cloud:tfc", "layer:control-plane"]
      }
    } : {},
    local.enable_github_admin ? {
      "github-admin" = {
        dir = "envs/github-admin", cloud = "platform", desc = "GitHub repository governance (rulesets, environments, security settings)", tags = ["cloud:github", "layer:control-plane"]
      }
    } : {},
  )
```

```hcl
    platform = var.manage_tfc_admin_workspace || local.enable_github_admin
```

and `never_auto_apply_workspaces = concat(local.guardrails_workspaces, [var.tfc_admin_workspace_name], local.enable_github_admin ? ["github-admin"] : [])`.

- [ ] **Step 3: Config schema.** Add a `github` property to `config/landing-zone.schema.json` (top level has `additionalProperties: false`):

```json
"github": {
  "type": "object",
  "additionalProperties": false,
  "description": "GitHub governance for the repository (envs/github-admin). No secrets.",
  "properties": {
    "enabled": {"type": "boolean"},
    "owner": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"},
    "repository": {"type": "string", "pattern": "^[A-Za-z0-9._-]+$"},
    "maintainers": {"type": "array", "maxItems": 6, "items": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"}},
    "required_approvals": {"type": "integer", "minimum": 1, "maximum": 6},
    "admin_bypass": {"enum": ["none", "pull_request"]},
    "release_app_id": {"type": "integer", "minimum": 1}
  }
}
```

and under `org.tfc.vcs_repo` add `"production_branch": {"type": "string", "pattern": "^[A-Za-z0-9._/-]+$"}`. Add the commented `github:` block and `production_branch` to `config/landing-zone.example.yaml`. Run `make config-check` (it also runs `check-config-schema-coverage.sh`, which fails until every `local.lz.github.*` read resolves in the schema).

- [ ] **Step 4: Docs and counts.** `CLAUDE.md`: add `github-admin/` to the repo layout and change "15 deployable roots" to 16. `README.md`: roots count and the test-suites badge (`make count` prints the numbers). `envs/README.md` and `docs/architecture/provider-selection.md`: add a `github-admin` row (provider `integrations/github`, credential: GitHub App env vars, reads no state). `.github/CODEOWNERS`: add `/envs/github-admin/` with platform and security owners next to `/envs/tfc-admin/`. `drift-detection.yml`: add `github-admin` to the default workspace list.

- [ ] **Step 5: Verify.**

```bash
make test TEST_DIRS="envs/tfc-admin envs/github-admin" TERRAFORM=$TF
make consistency config-check count-check links docs-check backend-check
```

Expected: all PASS. `backend-check` prints `ok envs/github-admin`. CI picks up the new root automatically (`scripts/terraform-roots.sh` discovers `envs/*` dirs with `.tf` files; the fixed 10 validate shards and 6 test shards re-slice).

- [ ] **Step 6: Commit.** `git commit -am "feat(tfc-admin): create the github-admin workspace when github.enabled"`

---

## Task 12: Policy sets from an uploaded slug, and a guard on policy content (A) (CICD-3)

Today `tfe_policy_set.opa` and `.destructive` read `policies/**` from `main` through VCS. A merged PR that deletes `destroy_guard.rego` takes effect at once. After this task the policy content is uploaded by a tfc-admin apply. tfc-admin needs a control-plane approver to confirm, and a new rule makes any content change a mandatory security-team override.

**Files:**
- Modify: `envs/tfc-admin/main.tf:1229-1330`, `envs/tfc-admin/variables.tf`
- Modify: `policies/opa-destructive/tfc_admin_guard.rego`, `policies/opa-destructive/tfc_admin_guard_test.rego`
- Modify: `envs/tfc-admin/tests/root.tftest.hcl`, `UPGRADING.md`

- [ ] **Step 1: Write the failing OPA tests.** Append to `tfc_admin_guard_test.rego`:

```rego
# ── Policy content (slug-sourced sets) ──────────────────────────────────────
slug_set(id) := object.union(
	object.remove(policy_set(["ws-1"]), ["vcs_repo", "policies_path"]),
	{"slug": {"id": id, "source_path": "../../policies/opa"}},
)

test_policy_content_change_denied if denied(change("tfe_policy_set", ["update"], slug_set("sha-a"), slug_set("sha-b")))

test_policy_content_unchanged_allowed if allowed(change("tfe_policy_set", ["update"], slug_set("sha-a"), object.union(slug_set("sha-a"), {"description": "reworded"})))

test_vcs_to_slug_migration_denied if denied(change("tfe_policy_set", ["update"], policy_set(["ws-1"]), slug_set("sha-a")))
```

Run `opa test policies/opa-destructive -r tfc_admin_guard`: `test_policy_content_change_denied` FAILS.

- [ ] **Step 2: Add the rule** in `tfc_admin_guard.rego` after the policy-source rule:

```rego
# Slug-sourced sets: the slug id is the content checksum of the uploaded
# policy directory. Any change to it changes what judges every run.
deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_policy_set"
	updates(rc)
	not lib.unknown(rc, "slug")
	object.get(before_obj(rc), "slug", null) != null
	object.get(before_obj(rc), "slug", null) != object.get(after_obj(rc), "slug", null)
	msg := sprintf("%s: plan changes the policy content (slug checksum); the security team must override this run if it is intended", [rc.address])
}
```

`test_vcs_to_slug_migration_denied` already passes through the existing policy-source rule (vcs_repo changes from one entry to none). Run `make opa-test`: PASS.

- [ ] **Step 3: Write the failing Terraform test.** Append to `envs/tfc-admin/tests/root.tftest.hcl`, reusing that file's variables for an estate with policy sets on (`vcs_repo` set and `tfc_plan = "standard"`):

```hcl
run "policy_sets_are_uploaded_not_vcs_tracked" {
  command = plan

  variables {
    vcs_repo = {
      identifier                 = "acme/lz"
      github_app_installation_id = "ghain-1"
    }
    tfc_plan                         = "standard"
    enable_unguarded_destroy_warning = true
  }

  assert {
    condition     = length(tfe_policy_set.opa[0].vcs_repo) == 0 && length(tfe_policy_set.destructive[0].vcs_repo) == 0
    error_message = "Policy sets must not track a branch: a merge would change them with no apply."
  }
  assert {
    condition     = tfe_policy_set.opa[0].policies_path == null
    error_message = "A slug-sourced policy set has no policies_path."
  }
}
```

Run: FAIL.

- [ ] **Step 4: Implement.** `variables.tf`:

```hcl
variable "policy_set_source" {
  description = "Where the OPA policy sets come from: slug (default; tfc-admin uploads policies/opa and policies/opa-destructive on apply, so a policy change needs a confirmed tfc-admin run and a security-team override) or vcs (the sets track org.tfc.vcs_repo.branch, so a merge changes them at once)."
  type        = string
  default     = "slug"
  validation {
    condition     = contains(["slug", "vcs"], var.policy_set_source)
    error_message = "policy_set_source must be slug or vcs."
  }
}
```

`main.tf` (add the data source; change both policy sets the same way):

```hcl
data "tfe_slug" "policies" {
  for_each    = local.enable_policy_sets && var.policy_set_source == "slug" ? local.policy_sets : {}
  source_path = "${path.module}/../../${each.value.path}"
}

resource "tfe_policy_set" "opa" {
  count = local.enable_policy_sets ? 1 : 0

  organization        = local.tfc_organization
  name                = local.policy_sets.opa.name
  description         = local.policy_sets.opa.description
  kind                = "opa"
  overridable         = local.policy_sets.opa.overridable
  policy_tool_version = var.opa_version
  workspace_ids       = local.policy_set_workspace_ids

  policies_path = var.policy_set_source == "vcs" ? local.policy_sets.opa.path : null
  slug          = var.policy_set_source == "slug" ? data.tfe_slug.policies["opa"] : null

  dynamic "vcs_repo" {
    for_each = var.policy_set_source == "vcs" && local.vcs_repo != null ? [local.vcs_repo] : []
    content {
      identifier                 = vcs_repo.value.identifier
      branch                     = vcs_repo.value.branch
      oauth_token_id             = vcs_repo.value.oauth_token_id
      github_app_installation_id = vcs_repo.value.github_app_installation_id
    }
  }

  lifecycle {
    precondition {
      condition     = var.policy_set_source == "slug" || local.vcs_repo != null
      error_message = "policy_set_source = vcs requires vcs_repo (or org.tfc.vcs_repo in config/landing-zone.yaml)."
    }
  }
}
```

Add `"policies/opa"` and `"policies/opa-destructive"` to `root_trigger_dirs["envs/tfc-admin"]` so a policy edit queues a tfc-admin plan that shows the new checksum.

- [ ] **Step 5: Run.** `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF` PASS; `make opa-test consistency` PASS.

- [ ] **Step 6: UPGRADING entry** (the commit is breaking): "tfc-admin now uploads the OPA policy sets (`policy_set_source = slug`). The first apply after upgrading changes each set's source, which `tfc_admin_guard` denies on purpose: the security team overrides that one run. To keep VCS sourcing, set `policy_set_source = \"vcs\"`."

- [ ] **Step 7: Commit.** `git commit -am "feat(tfc-admin)!: upload OPA policy sets instead of tracking main"`

---

## Task 13: Real CODEOWNERS (A, after D1) (CICD-3)

**Files:** `.github/CODEOWNERS`, `docs/guides/CI_SECRETS.md`

- [ ] **Step 1:** After the transfer (D1) and the team creation (Task 14 step 1), replace every `@your-org/platform-team`, `@your-org/security-team`, `@your-org/app-platform-team` and `@your-org/docs-team` with the real `@<org>/<team>`. If D1 is declined, replace them with `@EdwinKassier` and the second maintainer's handle, and record in `docs/known-gaps.md` that per-path security review needs an organization.
- [ ] **Step 2:** Remove the placeholder banner. Run `CODEOWNERS_ENFORCE=true make codeowners-check`: PASS.
- [ ] **Step 3:** Commit: `chore(codeowners): name the real owning teams`.
- [ ] **Step 4 (B):** `gh variable set CODEOWNERS_ENFORCE --body true`.

---

## Task 14: First apply of `github-admin` (B)

- [ ] **Step 1 (D1, operator):** Create the organization (free plan), transfer the repository (Settings > General > Transfer), create teams `platform-team`, `security-team`, `app-platform-team`, `docs-team`, add members. Update `org.tfc.vcs_repo.identifier` in `config/landing-zone.yaml` and reconnect the HCP VCS provider if it points at the old owner.
- [ ] **Step 2 (D3):** Create a GitHub App `ashes-github-admin`: Repository permissions Administration read/write, Environments read/write, Contents read/write (the provider needs it to read merge settings), Metadata read, Secret scanning alerts read, Dependabot alerts read/write; Organization Members read (for `data "github_user"`). Install it on this repository only. In the HCP `github-admin` workspace (created by tfc-admin once `github.enabled: true` is merged), add env vars `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_APP_PEM_FILE` (sensitive, the PEM contents).
- [ ] **Step 3:** Set the config keys in `config/landing-zone.yaml` (PR): `github: {enabled: true, maintainers: [...], admin_bypass: <D2 choice>, release_app_id: <Task 4 App ID>}` and, when Task 15 lands, `org.tfc.vcs_repo.production_branch: production`. Apply `tfc-admin` (creates the workspace), then queue `github-admin`. Expected plan: 1 import, 4 rulesets, 9 environments, about 11 deployment policies, 3 security resources, 1 actions permission. Confirm.
- [ ] **Step 4:** Remove classic protection only after the ruleset is active:

```bash
gh api repos/<owner>/Ashes-Devops-Tools/rulesets --jq '.[] | {name, enforcement}'
gh api -X DELETE repos/<owner>/Ashes-Devops-Tools/branches/main/protection
make required-checks-live
```

Expected: `required-checks-live` prints that live rules match the doc and no classic protection exists (CICD-8 closed).

- [ ] **Step 5:** Verify the security settings: `gh api repos/<owner>/Ashes-Devops-Tools --jq .security_and_analysis` shows `enabled` for the three secret-scanning keys; `gh api repos/<owner>/Ashes-Devops-Tools/actions/permissions` shows `selected` and `sha_pinning_required: true`.
- [ ] **Step 6:** Open a test PR from a branch, confirm it cannot merge without an approval and a green `Validation Summary`. Push an unsigned commit directly to `main` and confirm it is rejected.

---

## Phase 2: Promotion, four-eyes and provenance (CICD-5, CICD-6, CICD-7)

## Task 15: Production workload workspaces track a `production` branch (A) (CICD-6)

**Files:**
- Modify: `modules/tfc/workspace/outputs.tf` (+ README via `make docs`), `modules/tfc/workspace/tests/plan_assertions.tftest.hcl`
- Modify: `envs/tfc-admin/{config.tf,variables.tf,main.tf}`, `envs/tfc-admin/tests/catalog.tftest.hcl`

- [ ] **Step 1: Failing module test.** In the workspace module's plan suite:

```hcl
run "vcs_branch_is_exposed" {
  command = plan
  variables {
    vcs_repo = {
      identifier                 = "acme/lz"
      branch                     = "production"
      github_app_installation_id = "ghain-1"
    }
  }
  assert {
    condition     = output.vcs_branch == "production"
    error_message = "vcs_branch reports the tracked branch."
  }
}
```

Run: FAIL. Add the output:

```hcl
output "vcs_branch" {
  description = "Branch the workspace tracks; null when the workspace is not VCS-driven."
  value       = var.vcs_repo == null ? null : var.vcs_repo.branch
}
```

Run: PASS. `make docs`.

- [ ] **Step 2: Failing tfc-admin test.** Append to `catalog.tftest.hcl`:

```hcl
run "production_workloads_track_the_production_branch" {
  command = plan

  variables {
    vcs_repo = {
      identifier                 = "acme/lz"
      github_app_installation_id = "ghain-1"
    }
    production_branch = "production"
  }

  assert {
    condition     = module.workspace["gcp-workload-prod"].vcs_branch == "production" && module.workspace["aws-workload-prod"].vcs_branch == "production"
    error_message = "Production workloads track the production branch."
  }
  assert {
    condition     = module.workspace["gcp-workload-dev"].vcs_branch == "main" && module.workspace["gcp-organization"].vcs_branch == "main"
    error_message = "Every other workspace keeps tracking main."
  }
}

run "no_production_branch_keeps_main_everywhere" {
  command = plan
  variables {
    vcs_repo = {
      identifier                 = "acme/lz"
      github_app_installation_id = "ghain-1"
    }
  }
  assert {
    condition     = alltrue([for k, w in module.workspace : w.vcs_branch == "main"])
    error_message = "production_branch is opt-in."
  }
}
```

Run: FAIL.

- [ ] **Step 3: Implement.** `variables.tf`:

```hcl
variable "production_branch" {
  description = "Branch the production workload workspaces (is_production, or keys prod/production) track instead of vcs_repo.branch. promote.yml fast-forwards it to a release tag, so production receives an exact, reviewed commit. Null = org.tfc.vcs_repo.production_branch; null keeps every workspace on vcs_repo.branch."
  type        = string
  default     = null
  validation {
    condition     = var.production_branch == null || can(regex("^[A-Za-z0-9._/-]+$", coalesce(var.production_branch, "x")))
    error_message = "production_branch must be a plain branch name."
  }
}
```

`config.tf`: `production_branch = try(tostring(local.lz.org.tfc.vcs_repo.production_branch), null)` in `cfg`, and the effective `production_branch = var.production_branch != null ? var.production_branch : local.cfg.production_branch`.

`main.tf`, in `module "workspace"`:

```hcl
  # Production workloads track the promotion branch (CICD-6); everything else
  # tracks vcs_repo.branch. A module change reaches dev on merge and prod only
  # when promote.yml moves the production branch to a release tag.
  vcs_repo = local.vcs_repo == null ? null : merge(local.vcs_repo, {
    branch = contains(local.managed_production_workloads, each.key) && local.production_branch != null ? local.production_branch : local.vcs_repo.branch
  })
```

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/tfc/workspace envs/tfc-admin" TERRAFORM=$TF`: PASS; the `*_names_unchanged` runs are untouched (no key changes).
- [ ] **Step 5: Docs.** In `envs/tfc-admin/README.md` and `docs/runbooks/` (the add-environment runbook), explain: shared control-plane roots (organization, network hubs) still apply from `main` because they serve every environment; workload code reaches production only by promotion.
- [ ] **Step 6: Commit.** `git commit -am "feat(tfc-admin): let production workloads track a promotion branch"`

---

## Task 16: `promote.yml`: exact-commit promotion with a plan and a second approver (A + B) (CICD-5, CICD-6)

**Files:**
- Create: `.github/workflows/promote.yml`
- Create: `scripts/require-release-proof.sh`, `scripts/tests/test-require-release-proof.sh`
- Create: `docs/runbooks/promote-to-production.md`

- [ ] **Step 1: Failing script test** `scripts/tests/test-require-release-proof.sh`: stub `gh` with a function on `PATH` that prints a fixture JSON (`{"total_count":0}` then `{"total_count":1}`) and assert the script fails then passes. Run: FAIL.

- [ ] **Step 2: Write `scripts/require-release-proof.sh`.**

```bash
#!/usr/bin/env bash
# Fail unless the release proof workflows succeeded on exactly this commit.
# Usage: require-release-proof.sh <owner/repo> <sha>
# Proof = sandbox-estate-probe.yml AND sandbox-e2e.yml, conclusion success,
# head_sha == <sha> (D14: exact commit, no time window).
set -euo pipefail
repo="$1"
sha="$2"
fail=0
for wf in sandbox-estate-probe.yml sandbox-e2e.yml; do
  n=$(gh api "repos/${repo}/actions/workflows/${wf}/runs?head_sha=${sha}&status=success&per_page=1" --jq '.total_count')
  if [ "${n}" -ge 1 ]; then
    echo "ok    ${wf} succeeded on ${sha}"
  else
    echo "::error title=No release proof::${wf} has no successful run on ${sha}. Dispatch it on this commit (gh workflow run ${wf} --ref main) and retry." >&2
    fail=1
  fi
done
exit "${fail}"
```

Run the test: PASS. `make shellcheck`.

- [ ] **Step 3: Write `.github/workflows/promote.yml`.**

```yaml
name: Promote to production

# Exact-commit promotion (CICD-6) with four-eyes (CICD-5).
#   1. verify: the tag is vX.Y.Z on main, production fast-forwards to it, the
#      release proof is green on that exact commit, and the release tarball's
#      provenance attestation verifies.
#   2. plan: a speculative plan of that commit on every production workspace,
#      linked in the job summary, so the approver sees the change before it is
#      promoted.
#   3. promote: waits on the production-promotion environment. With two
#      maintainers prevent_self_review is on, so whoever dispatched this run
#      cannot approve it. Then the release App fast-forwards production; the
#      production ruleset lets nobody else move it.

on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Release tag to promote (vX.Y.Z)"
        required: true
        type: string

permissions: {}

concurrency:
  group: promote-production
  cancel-in-progress: false

env:
  PRODUCTION_BRANCH: ${{ vars.PRODUCTION_BRANCH || 'production' }}

jobs:
  verify:
    name: Verify release
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
      actions: read
    outputs:
      sha: ${{ steps.resolve.outputs.sha }}
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
            objects.githubusercontent.com:443
            release-assets.githubusercontent.com:443
            tuf-repo-cdn.sigstore.dev:443

      - name: Checkout code
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Resolve the tag and check ancestry
        id: resolve
        env:
          TAG: ${{ inputs.tag }}
        run: |
          [[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::tag must be vX.Y.Z"; exit 1; }
          git fetch --no-tags origin "+refs/tags/${TAG}:refs/tags/${TAG}"
          sha="$(git rev-list -n1 "refs/tags/${TAG}")"
          git merge-base --is-ancestor "${sha}" origin/main || { echo "::error::${TAG} is not on main"; exit 1; }
          if git ls-remote --exit-code --heads origin "${PRODUCTION_BRANCH}" >/dev/null; then
            git fetch --no-tags origin "+refs/heads/${PRODUCTION_BRANCH}:refs/remotes/origin/${PRODUCTION_BRANCH}"
            git merge-base --is-ancestor "origin/${PRODUCTION_BRANCH}" "${sha}" \
              || { echo "::error::${PRODUCTION_BRANCH} is not an ancestor of ${TAG}; promotion only fast-forwards"; exit 1; }
          fi
          echo "sha=${sha}" >> "$GITHUB_OUTPUT"

      - name: Require the release proof on this commit
        env:
          GH_TOKEN: ${{ github.token }}
          SHA: ${{ steps.resolve.outputs.sha }}
        run: ./scripts/require-release-proof.sh "${GITHUB_REPOSITORY}" "${SHA}"

      - name: Verify the release provenance attestation
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ inputs.tag }}
        run: |
          gh release download "${TAG}" --pattern 'ashes-devops-tools-*.tar.gz' --dir "${RUNNER_TEMP}/rel"
          gh attestation verify "${RUNNER_TEMP}"/rel/ashes-devops-tools-*.tar.gz \
            --repo "${GITHUB_REPOSITORY}" \
            --signer-workflow "${GITHUB_REPOSITORY}/.github/workflows/release.yml"

  plan:
    name: Production plan (${{ matrix.workspace }})
    needs: verify
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: tfc-promotion-plan
    permissions:
      contents: read
    strategy:
      fail-fast: false
      matrix:
        workspace: ${{ fromJSON(vars.PRODUCTION_WORKSPACES) }}
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: audit  # switch to block with the endpoint list from the first run (Task 20)

      - name: Checkout the tagged commit
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          ref: ${{ needs.verify.outputs.sha }}
          persist-credentials: false

      - name: Upload configuration (speculative)
        id: upload
        uses: hashicorp/tfc-workflows-github/actions/upload-configuration@8e08d1ba957673f5fbf971a22b3219639dc45661  # v1.3.2
        with:
          token: ${{ secrets.TFC_TOKEN_PROMOTION_PLAN }}
          organization: ${{ vars.TFC_ORGANIZATION }}
          workspace: ${{ matrix.workspace }}
          directory: ./
          speculative: true

      - name: Plan
        id: run
        uses: hashicorp/tfc-workflows-github/actions/create-run@8e08d1ba957673f5fbf971a22b3219639dc45661  # v1.3.2
        with:
          token: ${{ secrets.TFC_TOKEN_PROMOTION_PLAN }}
          organization: ${{ vars.TFC_ORGANIZATION }}
          workspace: ${{ matrix.workspace }}
          configuration_version: ${{ steps.upload.outputs.configuration_version_id }}
          plan_only: true
          message: "Promotion plan for ${{ inputs.tag }}"

      - name: Link the plan for the approver
        env:
          LINK: ${{ steps.run.outputs.run_link }}
          STATUS: ${{ steps.run.outputs.plan_status }}
          WS: ${{ matrix.workspace }}
        run: echo "| ${WS} | ${STATUS} | ${LINK} |" >> "$GITHUB_STEP_SUMMARY"

  promote:
    name: Fast-forward production
    needs: [verify, plan]
    runs-on: ubuntu-latest
    timeout-minutes: 10
    environment: production-promotion
    permissions: {}
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443

      - name: Mint release token
        id: app-token
        uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510  # v3.3.0
        with:
          app-id: ${{ vars.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - name: Move production to the tagged commit (fast-forward only)
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          SHA: ${{ needs.verify.outputs.sha }}
        run: |
          if gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/${PRODUCTION_BRANCH}" >/dev/null 2>&1; then
            gh api -X PATCH "repos/${GITHUB_REPOSITORY}/git/refs/heads/${PRODUCTION_BRANCH}" -f sha="${SHA}" -F force=false
          else
            gh api -X POST "repos/${GITHUB_REPOSITORY}/git/refs" -f ref="refs/heads/${PRODUCTION_BRANCH}" -f sha="${SHA}"
          fi
          echo "Promoted ${SHA} to ${PRODUCTION_BRANCH}" >> "$GITHUB_STEP_SUMMARY"
```

Add `promote` to the `RELEASE_APP_*` setup in `docs/guides/CI_SECRETS.md`: the App variable and key must also exist in the `production-promotion` environment.

- [ ] **Step 4: Verify.** `pre-commit run yamllint --files .github/workflows/promote.yml`; `make zizmor` (after Task 19); `bash scripts/check-github-governance.sh` (both new environments are declared in Task 9; both new actions are allowed in Task 10).

- [ ] **Step 5: Runbook** `docs/runbooks/promote-to-production.md`: when to promote, `gh workflow run promote.yml -f tag=vX.Y.Z`, what the approver checks (plan links in the run summary, release notes, `UPGRADING.md`), then confirm the HCP production runs (the control-plane approvers team). Name the three gates: PR review on `main`, the second-person approval of the promotion, and the HCP confirm.

- [ ] **Step 6: Commit.** `git commit -am "ci(promote): exact-commit production promotion with plan review and a second approver"`

- [ ] **Step 7 (B):** Create the HCP team `promotion-planner` with "Plan" (queue plans, read runs) on the production workload workspaces only. Create its team token and store it: `gh secret set TFC_TOKEN_PROMOTION_PLAN --env tfc-promotion-plan`. Set `gh variable set TFC_ORGANIZATION --env tfc-promotion-plan --body <org>`, `gh variable set PRODUCTION_WORKSPACES --body '["gcp-workload-prod","aws-workload-prod"]'`. Copy `RELEASE_APP_ID` / `RELEASE_APP_PRIVATE_KEY` into the `production-promotion` environment.

---

## Task 17: Record what OPA actually receives, and document four-eyes (A + B) (CICD-5)

**Files:**
- Create: `policies/opa-probe/run_input_probe.rego`, `policies/opa-probe/policies.hcl`
- Create: `docs/architecture/change-control.md`

- [ ] **Step 1 (A): Write an advisory probe policy** that prints the run metadata without the variables (which may hold sensitive values):

```rego
# Advisory probe, attached ONLY in the sandbox HCP organization: it always
# reports one message containing input.run (minus variables), so we can read
# which run fields HCP Terraform really passes to OPA. Never attach in
# production.
package terraform.policies.run_input_probe

import rego.v1

deny contains msg if {
	run := object.remove(object.get(input, "run", {}), ["variables"])
	msg := sprintf("run input: %s", [json.marshal(run)])
}
```

`policies.hcl`:

```hcl
policy "run_input_probe" {
  query             = "data.terraform.policies.run_input_probe.deny"
  enforcement_level = "advisory"
}
```

`make opa-test` must still pass (add `policies/opa-probe` to the `opa check` paths in the Makefile and CI).

- [ ] **Step 2 (B):** In the sandbox HCP organization only, create an advisory policy set from `policies/opa-probe` attached to one workspace. Queue one VCS run and one CLI speculative run. Copy the advisory message text from both runs.
- [ ] **Step 3 (A):** Write `docs/architecture/change-control.md` with the recorded field list (expected: `id`, `created_at`, `created_by`, `message`, `commit_sha`, `is_destroy`, `refresh`, `refresh_only`, `replace_addrs`, `speculative`, `target_addrs`, `project`, `organization`, `workspace`; confirm against the probe). State the conclusion: policies run before confirmation, so the confirmer is never in the input, and the PR author is not in the input either. Four-eyes is therefore enforced by GitHub (review on `main`, `prevent_self_review` on `production-promotion`) plus the HCP approvers team. List option D7(b), the pre-apply run task that reads `relationships.confirmed-by` from the runs API, as future work.
- [ ] **Step 4:** Commit: `docs(architecture): record the OPA run input and the four-eyes model`.

---

## Task 18: Release provenance, SBOM, and a fail-closed apply verifier (A) (CICD-7)

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `scripts/verify-run-commit.sh`, `scripts/tests/test-verify-run-commit.sh`
- Modify: `.github/workflows/terraform-apply.yml:160-170`

- [ ] **Step 1: Failing test for the verifier.** `scripts/tests/test-verify-run-commit.sh` feeds three fixture JSON responses (ingress commit equal to the tag commit, different, absent) to the script on stdin and asserts: equal exits 0 and prints `commit_match=true`; different exits 0 and prints `commit_match=false`; **absent exits 1** with "has no source commit". Run: FAIL.

- [ ] **Step 2: Extract and fix the logic** into `scripts/verify-run-commit.sh`:

```bash
#!/usr/bin/env bash
# Read a TFC runs API response (include=configuration_version.ingress_attributes)
# on stdin and compare the latest run's source commit with $TAG_COMMIT.
# A run with no source commit (CLI or API run) FAILS: a release must point at a
# VCS run of the tagged commit (CICD-7: no fail-open path).
set -euo pipefail
: "${TAG_COMMIT:?TAG_COMMIT must be set}"
response="$(cat)"
run_commit=$(jq -r '([.included[]? | select(.type=="ingress-attributes") | .attributes["commit-sha"]] | .[0]) // ""' <<<"${response}")
if [ -z "${run_commit}" ] || [ "${run_commit}" = "null" ]; then
  echo "::error::The latest run has no source commit (CLI or API run); a release must point at a VCS run of ${TAG_COMMIT}." >&2
  exit 1
fi
if [ "${run_commit}" = "${TAG_COMMIT}" ]; then
  echo "commit_match=true"
else
  echo "commit_match=false"
  echo "::warning::Run commit ${run_commit} != tag commit ${TAG_COMMIT}; release held." >&2
fi
```

In `terraform-apply.yml`, replace the inline block (lines 160-170) with:

```yaml
          ./scripts/verify-run-commit.sh <<<"$response" >> "$GITHUB_OUTPUT"
```

(add `TAG_COMMIT` to that step's `env:` if it is not already there, and add `actions/checkout` with `persist-credentials: false` to the job if it has none). Run the test: PASS.

- [ ] **Step 3: Provenance and SBOM job** in `release.yml`:

```yaml
  provenance:
    name: Provenance and SBOM
    needs: release-please
    if: needs.release-please.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    environment: release
    permissions:
      contents: write      # upload release assets
      id-token: write      # Sigstore signing for the attestations
      attestations: write  # store the attestations on the repository
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
            uploads.github.com:443
            objects.githubusercontent.com:443
            release-assets.githubusercontent.com:443
            raw.githubusercontent.com:443
            fulcio.sigstore.dev:443
            rekor.sigstore.dev:443
            tuf-repo-cdn.sigstore.dev:443
            toolbox-data.anchore.io:443

      - name: Checkout the release tag
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          ref: ${{ needs.release-please.outputs.tag_name }}
          persist-credentials: false

      - name: Build the source archive
        env:
          TAG: ${{ needs.release-please.outputs.tag_name }}
        run: |
          mkdir -p dist
          git archive --format=tar.gz --prefix="ashes-devops-tools-${TAG}/" \
            -o "dist/ashes-devops-tools-${TAG}.tar.gz" HEAD
          sha256sum dist/*.tar.gz > dist/SHA256SUMS

      - name: SBOM (CycloneDX; includes providers from every .terraform.lock.hcl)
        uses: anchore/sbom-action@66cbf4bc1f1c0d2edc94016e65bc221b6bb0ad6c  # v0.24.3
        with:
          path: .
          format: cyclonedx-json
          output-file: dist/sbom.cdx.json
          upload-artifact: false
          upload-release-assets: false

      - name: Build provenance attestation
        uses: actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8  # v4.2.2
        with:
          subject-path: dist/ashes-devops-tools-*.tar.gz

      - name: SBOM attestation
        uses: actions/attest-sbom@c604332985a26aa8cf1bdc465b92731239ec6b9e  # v4.1.0
        with:
          subject-path: dist/ashes-devops-tools-*.tar.gz
          sbom-path: dist/sbom.cdx.json

      - name: Upload release assets
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ needs.release-please.outputs.tag_name }}
        run: gh release upload "${TAG}" dist/* --clobber
```

The harden-runner list is a first estimate. Run once in audit mode on a test release if the block list breaks the job, then pin the list from the StepSecurity insights link in the log.

- [ ] **Step 4: Document verification** in `SECURITY.md` ("Verifying a release"): `gh attestation verify ashes-devops-tools-vX.Y.Z.tar.gz --repo <owner>/Ashes-Devops-Tools` and `gh attestation verify ... --predicate-type https://cyclonedx.org/bom`.

- [ ] **Step 5: Verify.** `make test-scripts shellcheck yamllint`. `bash scripts/check-github-governance.sh`.

- [ ] **Step 6: Commit.** `git commit -am "ci(release): attest build provenance and an SBOM; fail closed on unverifiable runs"`

Tag immutability and creation control come from Task 8 (`release-tags`, `deployment-tags`). Commit signing on `main` comes from Task 8 `required_signatures` with squash-only merges.

---

## Phase 3: The remaining delivery findings

## Task 19: zizmor in CI; fix `base_ref` interpolation and drift permissions (A) (CICD-16, CICD-18)

**Files:**
- Create: `.github/requirements/zizmor.in`, `.github/requirements/zizmor.txt`, `.github/zizmor.yml`
- Modify: `.github/workflows/terraform-plan.yml` (meta-lint), `.github/workflows/drift-detection.yml`

- [ ] **Step 1: Reproduce.** `pip install zizmor && zizmor --min-severity medium .github/workflows`. Expected: at least `template-injection` on `terraform-plan.yml` lines 377-378 and 391-392, and `excessive-permissions` on `drift-detection.yml`.

- [ ] **Step 2: Fix the injection.** In both meta-lint steps, move the expression to `env:`:

```yaml
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_REF: ${{ github.base_ref }}
        run: |
          python -m pip install --no-deps --require-hashes -r .github/requirements/commitizen.txt
          if [ "${EVENT_NAME}" = "pull_request" ]; then
            git fetch --no-tags origin "${BASE_REF}"
            base_sha="$(git merge-base "origin/${BASE_REF}" HEAD)"
            cz check --rev-range "${base_sha}..HEAD"
          else
            cz check --rev-range "HEAD~1..HEAD"
          fi
```

and the same `BASE_REF` change in "Breaking-change commits must update UPGRADING.md".

- [ ] **Step 3: Least privilege in drift detection.** Change the workflow-level block to `permissions: {}` and give `contents: read` to each job, plus `issues: write` only to the job that opens or updates the drift issue (the one using `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` near line 356).

- [ ] **Step 4: Add zizmor to meta-lint**, hash-locked like commitizen. `.github/requirements/zizmor.in` contains `zizmor`; generate the lock with `uv pip compile --generate-hashes --universal --python-version 3.12 .github/requirements/zizmor.in -o .github/requirements/zizmor.txt`. Step:

```yaml
      - name: GitHub Actions static analysis (zizmor)
        run: |
          python -m pip install --no-deps --require-hashes -r .github/requirements/zizmor.txt
          zizmor --min-severity medium --format github .github/workflows
```

Triage the remaining findings: fix each, or ignore it in `.github/zizmor.yml` with a one-line reason. Dependabot's `pip` entry for `/.github/requirements` already covers the new lock.

- [ ] **Step 5: Verify.** `make zizmor yamllint` PASS. Commit: `ci: add zizmor and remove template injection and broad drift permissions`.

---

## Task 20: harden-runner block mode on secret-holding jobs (A) (CICD-12)

**Files:** `.github/workflows/{documentation.yml,state-backup.yml,terraform-apply.yml,security-scan.yml,sandbox-e2e.yml}`

- [ ] **Step 1:** For each audit-mode job that holds a secret or an OIDC token, open the "View security insights" link printed by harden-runner in the latest run log (StepSecurity records every endpoint the job reached). Write that list into `allowed-endpoints` and set `egress-policy: block`. Starting lists:

| Job | Endpoints |
|---|---|
| `terraform-apply.yml` verify-run | `api.github.com:443`, `github.com:443`, `app.terraform.io:443` |
| `state-backup.yml` | `app.terraform.io:443`, `archivist.terraform.io:443`, `api.github.com:443`, `github.com:443`, plus the backup bucket endpoint (`storage.googleapis.com:443` or `s3.<region>.amazonaws.com:443`) |
| `documentation.yml` | `api.github.com:443`, `github.com:443`, `objects.githubusercontent.com:443`, `release-assets.githubusercontent.com:443` |
| `security-scan.yml` gitleaks | `api.github.com:443`, `github.com:443`, `objects.githubusercontent.com:443` |
| `sandbox-e2e.yml` gcp / aws | `registry.terraform.io:443`, `releases.hashicorp.com:443`, `github.com:443`, `api.github.com:443`, `*.googleapis.com:443`, `sts.amazonaws.com:443`, `*.amazonaws.com:443` |

- [ ] **Step 2:** Run each workflow once with `workflow_dispatch` (the e2e ones after Task 30). A block that breaks a job shows the denied host in the insights page; add it and re-run.
- [ ] **Step 3:** Add a guard to `scripts/check-github-governance.sh`: any job that references `secrets.` (other than `GITHUB_TOKEN`) or has `id-token: write` must use `egress-policy: block`; list exceptions explicitly in the script with a reason. Add a test case to `scripts/tests/test-check-github-governance.sh`.
- [ ] **Step 4:** Commit: `ci: block egress on every job that holds a secret or an OIDC token`.

---

## Task 21: Renovate for Terraform and the toolchain; a heartbeat (A + B) (CICD-13, IAC-6)

**Files:**
- Modify: `renovate.json`, `.github/dependabot.yml` (comment only), `.tool-versions`
- Create: `.github/workflows/dependency-heartbeat.yml`, `scripts/tool-checksums.sh`

- [ ] **Step 1 (A): Extend `renovate.json`.**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "enabledManagers": ["terraform", "asdf", "pre-commit", "custom.regex"],
  "pre-commit": {"enabled": true},
  "dependencyDashboard": true,
  "lockFileMaintenance": {
    "enabled": true,
    "schedule": ["before 6am on monday"],
    "commitMessageAction": "Refresh",
    "commitMessageTopic": "provider lockfiles"
  },
  "commitMessagePrefix": "fix(deps):",
  "labels": ["dependencies"],
  "prConcurrentLimit": 5,
  "customManagers": [
    {
      "customType": "regex",
      "description": "Tool versions pinned in workflows and tfc-admin, kept equal to .tool-versions",
      "managerFilePatterns": ["/^\\.github/workflows/.+\\.ya?ml$/", "/^envs/tfc-admin/variables\\.tf$/"],
      "matchStrings": [
        "TERRAFORM_VERSION: \"(?<currentValue>\\d+\\.\\d+\\.\\d+)\"",
        "variable \"terraform_version\"[\\s\\S]*?default\\s*=\\s*\"(?<currentValue>\\d+\\.\\d+\\.\\d+)\""
      ],
      "depNameTemplate": "hashicorp/terraform",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.*)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^\\.github/workflows/.+\\.ya?ml$/", "/^\\.tool-versions$/"],
      "matchStrings": ["OPA_VERSION: \"(?<currentValue>[\\d.]+)\"", "^opa (?<currentValue>[\\d.]+)$"],
      "depNameTemplate": "open-policy-agent/opa",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.*)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^\\.github/workflows/.+\\.ya?ml$/"],
      "matchStrings": ["TDOCS_VERSION=(?<currentValue>[\\d.]+)"],
      "depNameTemplate": "terraform-docs/terraform-docs",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.*)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^\\.github/workflows/.+\\.ya?ml$/"],
      "matchStrings": ["SC_VERSION: \"(?<currentValue>[\\d.]+)\""],
      "depNameTemplate": "koalaman/shellcheck",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.*)$"
    },
    {
      "customType": "regex",
      "managerFilePatterns": ["/^\\.github/workflows/reusable-security\\.yml$/"],
      "matchStrings": ["version: v(?<currentValue>[\\d.]+)"],
      "depNameTemplate": "aquasecurity/trivy",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.*)$"
    }
  ],
  "packageRules": [
    {
      "description": "One reviewed PR for all hashicorp/* provider updates within their current major",
      "matchManagers": ["terraform"],
      "matchDepTypes": ["required_provider"],
      "matchPackageNames": ["hashicorp/**"],
      "groupName": "hashicorp providers"
    },
    {
      "description": "Provider majors are deliberate, never proposed automatically",
      "matchManagers": ["terraform"],
      "matchDepTypes": ["required_provider"],
      "matchUpdateTypes": ["major"],
      "enabled": false
    },
    {
      "description": "One toolchain PR: every copy of a tool version moves together; checksums are refreshed with scripts/tool-checksums.sh",
      "matchManagers": ["asdf", "custom.regex"],
      "groupName": "toolchain",
      "commitMessagePrefix": "build(deps):"
    },
    {
      "matchManagers": ["pre-commit"],
      "groupName": "pre-commit hooks",
      "commitMessagePrefix": "build(deps):"
    }
  ]
}
```

- [ ] **Step 2 (A): Validate.** `npx --yes --package renovate renovate-config-validator renovate.json` PASS. Then a local dry run that lists every dependency Renovate finds:

```bash
LOG_LEVEL=debug npx --yes renovate --platform=local --dry-run=lookup 2>&1 | grep -E '"depName"' | sort -u
```

Expected: terraform, tflint, trivy, shellcheck, terraform-docs, checkov, opa, every pre-commit hook and every provider. If `asdf` does not support one tool (checkov is the likely gap), add a regex manager for `^checkov (?<currentValue>[\d.]+)$` with `datasourceTemplate: pypi`.

- [ ] **Step 3 (A): Checksums helper** `scripts/tool-checksums.sh <tool> <version>` prints the SHA-256 lines for the CI downloads that carry a checksum (OPA binary today), so a reviewer updates the hash in the same Renovate PR.

- [ ] **Step 4 (A): Heartbeat** `.github/workflows/dependency-heartbeat.yml`:

```yaml
name: Dependency heartbeat

# Fails when Renovate has not touched its Dependency Dashboard issue for 8 days:
# "Renovate never ran" (IAC-6) must show as a red check, not as silence.
on:
  schedule:
    - cron: "41 6 * * 2"
  workflow_dispatch:

permissions: {}

jobs:
  heartbeat:
    name: Renovate heartbeat
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      issues: read
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443

      - name: Check the Dependency Dashboard
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          updated=$(gh api "repos/${GITHUB_REPOSITORY}/issues?state=open&creator=renovate%5Bbot%5D&per_page=100" \
            --jq '[.[] | select(.title=="Dependency Dashboard") | .updated_at] | first // empty')
          if [ -z "${updated}" ]; then
            echo "::error::No Renovate Dependency Dashboard issue: the Renovate app is not installed or not running."
            exit 1
          fi
          age_days=$(( ( $(date -u +%s) - $(date -u -d "${updated}" +%s) ) / 86400 ))
          echo "Dependency Dashboard last updated ${updated} (${age_days} days ago)"
          [ "${age_days}" -le 8 ] || { echo "::error::Renovate has not run for ${age_days} days."; exit 1; }
```

- [ ] **Step 5 (A):** Commit: `build(deps): bring the toolchain and pre-commit hooks under Renovate, with a heartbeat`.
- [ ] **Step 6 (B, D8):** Install the Renovate GitHub App (github.com/apps/renovate) on this repository only. Merge the onboarding PR if Renovate opens one. Within a week, expect the Dependency Dashboard issue, a lockfile-maintenance PR and a toolchain PR. `gh workflow run dependency-heartbeat.yml` must pass.

---

## Task 22: Delivery examples deploy by digest and attest the image (A) (CICD-17)

**Files:** `examples/app-delivery/{cloud-run,ecs-fargate,gke-autopilot}-delivery.example.yml`, `docs/guides/deploying-a-service.md`

- [ ] **Step 1:** Rewrite `cloud-run-delivery.example.yml` (this also clears its yamllint warnings):

```yaml
name: Deploy service (Cloud Run)

"on":
  push:
    branches: [main]  # must match app_services.<svc>.github.ref when set

permissions: {}

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    # environment: dev  # set when app_services.<svc>.github.environment is set
    permissions:
      contents: read
      id-token: write      # keyless WIF auth and Sigstore signing
      attestations: write  # store the image provenance attestation
    env:
      REPO: ${{ vars.IMAGE_REPOSITORY }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false

      - name: Build image
        run: docker build -t "${REPO}:${GITHUB_SHA}" .

      - name: Scan image (block on CRITICAL/HIGH, matching the IaC gate)
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25  # v0.36.0
        with:
          image-ref: ${{ vars.IMAGE_REPOSITORY }}:${{ github.sha }}
          severity: "CRITICAL,HIGH"
          exit-code: "1"

      - name: Authenticate to Google Cloud (keyless WIF)
        uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093  # v3.0.0
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_DEPLOY_SA }}

      - name: Push image and resolve its digest
        id: push
        env:
          REGION: ${{ vars.GCP_REGION }}
        run: |
          gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
          docker push "${REPO}:${GITHUB_SHA}"
          digest="$(docker inspect --format='{{index .RepoDigests 0}}' "${REPO}:${GITHUB_SHA}" | cut -d@ -f2)"
          echo "digest=${digest}" >> "$GITHUB_OUTPUT"

      - name: Attest image provenance
        uses: actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8  # v4.2.2
        with:
          subject-name: ${{ vars.IMAGE_REPOSITORY }}
          subject-digest: ${{ steps.push.outputs.digest }}
          push-to-registry: true

      # Deploy the immutable digest, never the tag: what was scanned and
      # attested is exactly what runs.
      - name: Deploy to Cloud Run
        env:
          SERVICE: ${{ vars.CLOUD_RUN_SERVICE }}
          PROJECT: ${{ vars.GCP_PROJECT_ID }}
          REGION: ${{ vars.GCP_REGION }}
          DIGEST: ${{ steps.push.outputs.digest }}
        run: |
          gcloud run deploy "${SERVICE}" --project "${PROJECT}" --region "${REGION}" \
            --image "${REPO}@${DIGEST}" --quiet
```

- [ ] **Step 2:** Apply the same pattern to the ECS example (register the task definition with `image: <repo>@<digest>`) and the GKE example (`kubectl set image deployment/<name> <container>=<repo>@<digest>`). Move every `${{ vars.* }}` used inside `run:` into `env:`.
- [ ] **Step 3:** In `docs/guides/deploying-a-service.md`, document verification (`gh attestation verify oci://<repo>@<digest> --repo <owner>/<app-repo>`) and name enforcement at admission (GKE Binary Authorization, ECS image signing) as the next step, not in scope.
- [ ] **Step 4:** `pre-commit run yamllint --files examples/app-delivery/*.yml` shows no warnings. Commit: `docs(examples): deploy by digest and attest image provenance`.

---

## Task 23: Module API guard and a versioning policy (A) (IAC-3, D9)

**Files:**
- Create: `scripts/check-module-api.sh`, `scripts/tests/test-check-module-api.sh`
- Create: `docs/policies/versioning-and-compatibility.md`
- Modify: `.github/workflows/terraform-plan.yml` (meta-lint, PR only)

- [ ] **Step 1: Failing test.** In a temp git repo: commit a module with `variable "a"` and `output "x"`; on a branch remove `variable "a"` with commit `feat: drop a`; expect the checker to fail with `modules/m: removed variable a`. Then amend the commit to `feat!: drop a` and expect a pass. Run: FAIL.

- [ ] **Step 2: Write `scripts/check-module-api.sh`.**

```bash
#!/usr/bin/env bash
# A PR that removes or renames a module input or output is a breaking change:
# it must carry a `!:` or BREAKING CHANGE commit (which in turn requires an
# UPGRADING.md entry, enforced by meta-lint). Adding inputs or outputs is fine.
# Usage: check-module-api.sh <base-ref>
set -euo pipefail
base="$(git merge-base "${1:?base ref}" HEAD)"
names() { git show "$1:$2" 2>/dev/null | sed -nE "s/^$3[[:space:]]+\"([^\"]+)\".*/\\1/p" | sort -u; }
removed=()
for f in $(git diff --name-only "${base}..HEAD" -- 'modules/**/variables.tf' 'modules/**/outputs.tf'); do
  kind=variable; [[ "$f" == */outputs.tf ]] && kind=output
  while IFS= read -r n; do
    [ -n "$n" ] && removed+=("$(dirname "$f"): removed ${kind} ${n}")
  done < <(comm -23 <(names "${base}" "$f" "${kind}") <(names HEAD "$f" "${kind}"))
done
[ "${#removed[@]}" -eq 0 ] && { echo "check-module-api: no module input or output removed"; exit 0; }
if git log --format=%B "${base}..HEAD" | grep -Eq '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE'; then
  printf 'check-module-api: breaking change declared for:\n'; printf '  %s\n' "${removed[@]}"; exit 0
fi
printf '::error::Module API removed without a breaking-change commit:\n' >&2
printf '  %s\n' "${removed[@]}" >&2
exit 1
```

Run the test: PASS. Add a meta-lint step for PRs: `./scripts/check-module-api.sh "origin/${BASE_REF}"` (with `BASE_REF` in `env:`).

- [ ] **Step 3: Policy doc** `docs/policies/versioning-and-compatibility.md`: one SemVer for the whole module set (the public API is every module's inputs and outputs plus every root's config keys); pre-1.0 minor bumps may break, each with an `UPGRADING.md` entry; post-1.0 breaking changes only in majors; support window (latest minor gets fixes; security fixes for the previous minor for 90 days); provider floor policy (the pins in `CLAUDE.md`); how consumers pin (`?ref=vX.Y.Z`). State the rejected option (per-module registry tags) and when to revisit it.

- [ ] **Step 4:** Commit: `ci: fail module API removals that are not marked breaking; publish the versioning policy`.

---

## Task 24: Governance artefacts and second-maintainer onboarding (A; people step is C)

**Files:** Create `MAINTAINERS.md`, `GOVERNANCE.md`, `SUPPORT.md`, `docs/guides/maintainer-onboarding.md`; modify `CONTRIBUTING.md`, `README.md` (links).

- [ ] **Step 1:** `MAINTAINERS.md`: table of name, GitHub handle, role (maintainer, security reviewer), areas (CODEOWNERS paths), time zone, since. Today one row. A line: "Target: at least two maintainers with merge rights and one independent security reviewer (see GOVERNANCE.md)."
- [ ] **Step 2:** `GOVERNANCE.md`: decision making (lazy consensus on PRs; security-sensitive paths need the security reviewer, enforced by CODEOWNERS and the `main` ruleset); how a contributor becomes a maintainer (sustained reviews over 3 months, nomination, approval by existing maintainers); emergency changes (break-glass: an admin may bypass only through the logged ruleset bypass, followed by a post-incident PR within 2 working days); release authority (release PR review plus Release Proof, Task 29); production promotion (Task 16); succession (if the only maintainer is unavailable for 30 days, the org owner appoints one).
- [ ] **Step 3:** `SUPPORT.md`: where to ask, response targets (best effort, security reports per `SECURITY.md`), supported versions table linking to `docs/policies/versioning-and-compatibility.md`.
- [ ] **Step 4:** `docs/guides/maintainer-onboarding.md`: checklist for maintainer two: org membership and team, signing not required (squash), HCP teams (control-plane approvers, not the same person as the PR author for a given change), sandbox access, the three gates of change control, the runbooks to read, a first-week shadow review list.
- [ ] **Step 5:** `make links` PASS. Commit: `docs(governance): add maintainers, governance, support and onboarding`.
- [ ] **Step 6 (C, owner only):** Recruit and onboard a second maintainer and an independent security reviewer. Add them to `github.maintainers`, the teams, and the HCP approvers team. Then switch `github.admin_bypass` to `none` (D2) and apply `github-admin`. This step is the only way to close ADO-10 and CICD-5 fully; no code replaces it.

---

## Phase 4 (WS6): Proof in a real sandbox

The estate probe below fails until the architecture workstream fixes ARC-1, ARC-2, ARC-3 and ARC-10. That is the purpose: it is the first check that can see those defects. Land the probe first, watch it fail for the right reasons, then use it to verify those fixes.

## What the sandbox is

| Piece | Where | Purpose |
|---|---|---|
| Unit e2e sandbox (exists in code) | 1 dedicated GCP project + 1 dedicated AWS account | `tests/e2e/{gcp,aws}`, single modules, under USD 1 per run |
| Sandbox estate (exists in code, Task 25 widens it) | Second HCP org, second GCP org (separate Cloud Identity domain), second AWS org | Full landing zone applied on every merge to `main`, N-1 to N upgrade test |
| Estate probe (new, Tasks 26 to 28) | Runs against the sandbox estate | Convergence, subnet placement, DNS from a spoke, egress, in a non-default region |

## Task 25: Widen the sandbox estate config (A) (D13)

**Files:** `config/sandbox/landing-zone.yaml`, `config/sandbox/tfc-workspaces.yaml`, `envs/tfc-admin/tests/sandbox.tftest.hcl`, `docs/guides/sandbox-estate.md`

- [ ] **Step 1: Failing test.** Extend the `sandbox_config_files_plan` run in `envs/tfc-admin/tests/sandbox.tftest.hcl`:

```hcl
  assert {
    condition = alltrue([for w in ["gcp-workload-dev", "gcp-workload-prod", "aws-workload-dev", "aws-workload-prod"] : contains(keys(module.workspace), w)])
    error_message = "The sandbox estate must run two GCP environments and two AWS workload accounts."
  }
  assert {
    condition     = contains(module.workspace["gcp-workload-prod"].tag_names, "tier:production")
    error_message = "The second environment is production, so the production paths (VPC-SC precondition, admin containment, approvals) are exercised."
  }
```

Run `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`: FAIL.

- [ ] **Step 2: Config changes** in `config/sandbox/landing-zone.yaml`:

```yaml
org:
  monthly_budget_usd: 1300        # starter, two environments (audit Part 4 + one AWS workload account)
  regions:
    gcp: us-east4                 # D13: not the default region
    aws: us-east-2                # D13: catches ARC-3 (eu-west-2 AZ defaults)
gcp:
  allowed_regions: [us-east4]
  environments:
    dev:
      display_name: Sandbox Development
      cidr_block: 10.10.0.0/16
      budget_monthly_limit: 100
      is_production: false
      labels: {tier: sandbox}
      iam_group_role_bindings: {}
    prod:
      display_name: Sandbox Production
      cidr_block: 10.11.0.0/16
      budget_monthly_limit: 100
      is_production: true
      labels: {tier: sandbox}
      iam_group_role_bindings: {}
aws:
  allowed_regions: [us-east-2]
  enabled_regions: [us-east-2]
  workload_accounts:
    workload_dev: {email: aws+sbx-workload-dev@example.com, ou: Workloads}
    workload_prod: {email: aws+sbx-workload-prod@example.com, ou: Workloads}
  workload_environments:
    dev:
      account_key: workload_dev
      vpc_cidr: 10.72.0.0/16
      is_production: false
    prod:
      account_key: workload_prod
      vpc_cidr: 10.73.0.0/16
      is_production: true
```

Keep every other key. Keep `org.tfc.vcs_repo` without `production_branch` in the sandbox: the sandbox applies every merge, including to its production workspaces. Update `config/sandbox/tfc-workspaces.yaml` if it lists workspaces by name.

- [ ] **Step 3:** `make config-check` and `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`: PASS.
- [ ] **Step 4:** Update `docs/guides/sandbox-estate.md`: two environments, regions, budget, account quota (management + 6 shared + 2 workload = 9 accounts; ask AWS for 15 before stand-up).
- [ ] **Step 5:** Commit: `feat(sandbox): run two environments and two AWS workload accounts outside eu-west-2`.

## Task 26: GCP estate probe root (A)

**Files:** Create `tests/e2e/estate-gcp/{versions.tf,providers.tf,variables.tf,main.tf,outputs.tf,probe.sh,e2e.tftest.hcl,.terraform.lock.hcl}`

Depth 2 under `tests/e2e`, so `scripts/terraform-roots.sh` puts it in the validate set and keeps it out of `make test`.

- [ ] **Step 1: Write the probe script** `probe.sh` (runs on the VM as its startup script) and lint it first: `shellcheck tests/e2e/estate-gcp/probe.sh` must pass.

```bash
#!/bin/bash
# Estate probe, run as a GCE startup script inside a spoke subnet. Writes each
# result to guest attributes (namespace "probe"), read back by Terraform.
set -u
md="http://metadata.google.internal/computeMetadata/v1/instance"
attr() { curl -s -X PUT --data "$2" -H "Metadata-Flavor: Google" "${md}/guest-attributes/probe/$1"; }
name="$(curl -s -H 'Metadata-Flavor: Google' "${md}/attributes/probe-name")"
egress_url="$(curl -s -H 'Metadata-Flavor: Google' "${md}/attributes/probe-egress-url")"
for _ in $(seq 1 30); do
  ip="$(getent hosts "${name}" | awk '{print $1}')"
  [ -n "${ip}" ] && break
  sleep 5
done
attr dns "${ip:-NXDOMAIN}"
code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "${egress_url}" || true)"
attr egress "${code:-000}"
attr done "1"
```

- [ ] **Step 2: Root files.** `versions.tf`: `google ~> 8.0`, `hashicorp/time ~> 0.13`, Terraform `>= 1.17, < 2.0`. `providers.tf`: `provider "google" { default_labels = { "e2e-run-id" = var.run_id } }`. `variables.tf`: `run_id`, `run_attempt`, `region`, `host_project_id`, `subnet_self_link` (from `gcp-workload-<env>` output `subnets`), `dns_project_id`, `dns_zone_name`, `internal_domain` (from the `gcp-network-hub` `contract` output), `egress_url` (default `https://www.google.com/generate_204`). `main.tf`:

```hcl
locals {
  name       = "e2e-${var.run_id}-${var.run_attempt}"
  probe_fqdn = "${local.name}.${trimsuffix(var.internal_domain, ".")}."
}

# A record in the organization's internal root zone (the zone every spoke
# must resolve, ARC-2). 192.0.2.10 is TEST-NET-1: never routed.
resource "google_dns_record_set" "probe" {
  project      = var.dns_project_id
  managed_zone = var.dns_zone_name
  name         = local.probe_fqdn
  type         = "A"
  ttl          = 30
  rrdatas      = ["192.0.2.10"]
}

data "google_compute_zones" "available" {
  project = var.host_project_id
  region  = var.region
}

# No external IP, no service account, Shielded VM: the probe can only reach
# what the spoke's routing and firewall allow.
resource "google_compute_instance" "probe" {
  project      = var.host_project_id
  name         = local.name
  zone         = data.google_compute_zones.available.names[0]
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-guest-attributes = "TRUE"
    enable-oslogin          = "TRUE"
    probe-name              = trimsuffix(local.probe_fqdn, ".")
    probe-egress-url        = var.egress_url
    startup-script          = file("${path.module}/probe.sh")
  }

  depends_on = [google_dns_record_set.probe]
}

resource "time_sleep" "probe_runs" {
  depends_on      = [google_compute_instance.probe]
  create_duration = "240s"
}

data "google_compute_instance_guest_attributes" "probe" {
  project      = var.host_project_id
  zone         = google_compute_instance.probe.zone
  name         = google_compute_instance.probe.name
  query_path   = "probe/"
  depends_on   = [time_sleep.probe_runs]
}

locals {
  results = { for kv in data.google_compute_instance_guest_attributes.probe.query_value : kv.key => kv.value }
}
```

Check the data source's attribute names (`query_value`, `key`, `value`) against the google provider 8.x docs before writing `locals.results`.

`e2e.tftest.hcl`:

```hcl
# REAL-APPLY probe: no mock_provider. Runs only in sandbox-estate-probe.yml.
run "spoke_resolves_internal_zone_and_reaches_the_internet" {
  command = apply

  assert {
    condition     = lookup(local.results, "done", "") == "1"
    error_message = "The probe VM did not finish its startup script (boot, org policy or image problem)."
  }
  assert {
    condition     = lookup(local.results, "dns", "") == "192.0.2.10"
    error_message = "ARC-2: a VM in the spoke cannot resolve ${local.probe_fqdn} in the internal root zone (got ${lookup(local.results, "dns", "nothing")})."
  }
  assert {
    condition     = contains(["200", "204"], lookup(local.results, "egress", ""))
    error_message = "ARC-10: no internet egress from the spoke (HTTP ${lookup(local.results, "egress", "none")} from ${var.egress_url})."
  }
}
```

- [ ] **Step 3: Lock and validate.**

```bash
$TF -chdir=tests/e2e/estate-gcp init -backend=false
$TF -chdir=tests/e2e/estate-gcp providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
$TF -chdir=tests/e2e/estate-gcp validate
make shellcheck consistency
```

Expected: validate PASS (no credentials needed). Add `tests/e2e/estate-gcp/probe.sh` to the `shellcheck` target's file list.

- [ ] **Step 4:** Extend `tests/e2e/scripts/cleanup-gcp.sh` (or add `cleanup-estate-gcp.sh`) to delete instances and record sets named `e2e-<run_id>-*` in the given projects. Commit: `test(e2e): probe DNS and egress from inside a GCP spoke`.

## Task 27: AWS estate probe root (A)

**Files:** Create `tests/e2e/estate-aws/{versions.tf,providers.tf,variables.tf,main.tf,e2e.tftest.hcl,.terraform.lock.hcl}`, `tests/e2e/estate-aws/probe/{handler.py,test_handler.py}`, `templates/aws/bootstrap/e2e-probe-role.yaml`

- [ ] **Step 1: Failing unit test** `probe/test_handler.py` (stdlib only):

```python
import json
import unittest
from unittest import mock

import handler


class ProbeTest(unittest.TestCase):
    @mock.patch("handler.socket.getaddrinfo")
    @mock.patch("handler.urllib.request.urlopen")
    def test_reports_dns_and_egress(self, urlopen, getaddrinfo):
        getaddrinfo.return_value = [(2, 1, 6, "", ("10.80.1.10", 443))]
        urlopen.return_value.__enter__.return_value.status = 200
        out = handler.handler({"names": ["sts.us-east-2.amazonaws.com"], "allowed_url": "https://github.com", "denied_url": ""}, None)
        self.assertEqual(out["dns"]["sts.us-east-2.amazonaws.com"], ["10.80.1.10"])
        self.assertEqual(out["allowed_status"], 200)
        self.assertIsNone(out["denied_status"])

    @mock.patch("handler.socket.getaddrinfo", side_effect=OSError("NXDOMAIN"))
    def test_dns_failure_is_reported_not_raised(self, _):
        out = handler.handler({"names": ["nope.internal"], "allowed_url": "", "denied_url": ""}, None)
        self.assertEqual(out["dns"]["nope.internal"], [])


if __name__ == "__main__":
    unittest.main()
```

Run `python3 -I -m unittest discover -s tests/e2e/estate-aws/probe`: FAIL (no handler).

- [ ] **Step 2: Write `probe/handler.py`.**

```python
"""Estate probe Lambda, run inside a workload spoke's private subnets.

Resolves names through the VPC resolver and makes HTTPS requests through the
spoke's routing (TGW -> central egress). Never raises: every result is
returned so Terraform can assert on it.
"""
import socket
import urllib.request


def _resolve(name):
    try:
        return sorted({info[4][0] for info in socket.getaddrinfo(name, 443, proto=socket.IPPROTO_TCP)})
    except OSError:
        return []


def _get(url):
    if not url:
        return None
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:  # noqa: S310 (fixed https URLs from Terraform)
            return resp.status
    except Exception:  # noqa: BLE001
        return 0


def handler(event, _context):
    return {
        "dns": {name: _resolve(name) for name in event.get("names", [])},
        "allowed_status": _get(event.get("allowed_url", "")),
        "denied_status": _get(event.get("denied_url", "")),
    }
```

Run the unit test: PASS. Add `python3 -I -m unittest discover -s tests/e2e/estate-aws/probe` to `make test-scripts`.

- [ ] **Step 3: Root files.** `versions.tf`: aws `>= 6.46.0, < 7.0.0`, `hashicorp/archive ~> 2.7`. `providers.tf`: same `default_tags` pattern as `tests/e2e/aws/providers.tf`. `variables.tf`: `run_id`, `run_attempt`, `region`, `vpc_id` (from `aws-workload-<env>` output `vpc_id`), `probe_role_arn` (pre-created by the CloudFormation template, so the run needs no `iam:CreateRole`), `expect_private_endpoints` (bool), `expect_egress_filtering` (bool, false on `starter` which has no Network Firewall), `allowed_url` (default `https://github.com`), `denied_url` (default `https://example.org`). `main.tf`:

```hcl
locals {
  name = "e2e-${var.run_id}-${var.run_attempt}"
}

data "aws_vpc" "spoke" {
  id = var.vpc_id
}

data "aws_subnets" "spoke" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "spoke" {
  for_each = toset(data.aws_subnets.spoke.ids)
  id       = each.value
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

data "archive_file" "probe" {
  type        = "zip"
  source_file = "${path.module}/probe/handler.py"
  output_path = "${path.root}/.terraform/probe-${local.name}.zip"
}

resource "aws_security_group" "probe" {
  name        = local.name
  description = "Estate probe: HTTPS and DNS out only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.probe.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0" #trivy:ignore:AVD-AWS-0104 probe measures the spoke's real egress path
}

resource "aws_lambda_function" "probe" {
  function_name    = local.name
  role             = var.probe_role_arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.probe.output_path
  source_code_hash = data.archive_file.probe.output_base64sha256
  timeout          = 60

  vpc_config {
    subnet_ids         = slice(data.aws_subnets.private.ids, 0, min(2, length(data.aws_subnets.private.ids)))
    security_group_ids = [aws_security_group.probe.id]
  }
}

resource "aws_lambda_invocation" "probe" {
  function_name = aws_lambda_function.probe.function_name
  input = jsonencode({
    names       = ["sts.${var.region}.amazonaws.com", "ssm.${var.region}.amazonaws.com"]
    allowed_url = var.allowed_url
    denied_url  = var.expect_egress_filtering ? var.denied_url : ""
  })
}

locals {
  result = jsondecode(aws_lambda_invocation.probe.result)
}
```

`e2e.tftest.hcl`:

```hcl
# REAL-APPLY probe: no mock_provider. Runs only in sandbox-estate-probe.yml.
run "spoke_subnets_dns_and_egress" {
  command = apply

  assert {
    # Subnet s lies in VPC block c when s is no wider than c and s's first
    # address, masked to c's prefix length, is c's network address.
    condition = length(data.aws_subnets.spoke.ids) > 0 && alltrue([
      for s in data.aws_subnet.spoke : anytrue([
        for c in data.aws_vpc.spoke.cidr_block_associations :
        tonumber(split("/", s.cidr_block)[1]) >= tonumber(split("/", c.cidr_block)[1]) &&
        cidrhost("${cidrhost(s.cidr_block, 0)}/${split("/", c.cidr_block)[1]}", 0) == cidrhost(c.cidr_block, 0)
      ])
    ])
    error_message = "ARC-1: a spoke subnet lies outside its VPC's CIDR blocks, or the spoke has no subnets."
  }
  assert {
    condition     = length(distinct([for s in data.aws_subnet.spoke : s.availability_zone_id])) >= 2
    error_message = "ARC-3: the spoke does not span two availability zones in ${var.region}."
  }
  assert {
    condition     = alltrue([for n, ips in local.result.dns : length(ips) > 0])
    error_message = "DNS from the spoke failed for: ${join(", ", [for n, ips in local.result.dns : n if length(ips) == 0])}."
  }
  assert {
    condition     = !var.expect_private_endpoints || alltrue([for n, ips in local.result.dns : alltrue([for ip in ips : cidrhost("${ip}/8", 0) == "10.0.0.0"])])
    error_message = "ARC-6: AWS API names resolve to public IPs from the spoke; the shared interface endpoints do not serve it."
  }
  assert {
    condition     = local.result.allowed_status >= 200 && local.result.allowed_status < 400
    error_message = "ARC-10: no HTTPS egress from the spoke to ${var.allowed_url} (status ${local.result.allowed_status})."
  }
  assert {
    condition     = !var.expect_egress_filtering || local.result.denied_status == 0
    error_message = "Egress filtering: ${var.denied_url} is reachable although it is not on the allowlist."
  }
}
```

Terraform core has no CIDR-containment function, so the assertions mask addresses with `cidrhost`. Check both expressions in `terraform console` with a sample VPC and subnet before the first real run. The private-endpoint check assumes the sandbox uses `10.0.0.0/8`, as `config/sandbox/landing-zone.yaml` does.

- [ ] **Step 4: Probe role template** `templates/aws/bootstrap/e2e-probe-role.yaml` (CloudFormation, deployed to each sandbox workload account by StackSet): an OIDC-trusted role `e2e-probe` (subject `repo:<owner>/<repo>:environment:estate-probe`) with Lambda, security-group and describe permissions on names `e2e-*`, plus the pre-created Lambda execution role `e2e-probe-exec` (`AWSLambdaVPCAccessExecutionRole`). `make cfn-lint` PASS.

- [ ] **Step 5:** Lock (3 platforms) and `terraform validate`. Commit: `test(e2e): probe subnets, DNS and egress from inside an AWS spoke`.

## Task 28: `sandbox-estate-probe.yml` and the convergence check (A)

**Files:**
- Create: `scripts/estate-convergence.sh`, `scripts/tests/test-estate-convergence.sh`, `scripts/tests/fixtures/estate-convergence/*.json`
- Create: `.github/workflows/sandbox-estate-probe.yml`

- [ ] **Step 1: Failing convergence test.** Fixtures: a workspaces list with three workspaces and their current runs in `applied`, `planned_and_finished`, `errored`. The test expects exit 1 and the errored workspace named; with all three healthy, exit 0. Run: FAIL.

- [ ] **Step 2: Write `scripts/estate-convergence.sh`.**

```bash
#!/usr/bin/env bash
# Every workspace in the sandbox HCP organization must have converged: its
# latest run is applied or planned_and_finished (no changes), and no run has
# been pending for over 2 hours. ESTATE_FIXTURE_DIR replaces the API (tests).
# Env: TFC_TOKEN, TFC_ORGANIZATION, [TFC_HOSTNAME]
set -euo pipefail
host="${TFC_HOSTNAME:-app.terraform.io}"
api() {
  if [ -n "${ESTATE_FIXTURE_DIR:-}" ]; then cat "${ESTATE_FIXTURE_DIR}/$(echo "$1" | tr '/?=&' '____').json"; return; fi
  curl -sSf -H "Authorization: Bearer ${TFC_TOKEN}" -H "Content-Type: application/vnd.api+json" "https://${host}/api/v2/$1"
}
fail=0
now=$(date -u +%s)
while IFS=$'\t' read -r id name; do
  run=$(api "workspaces/${id}/runs?page%5Bsize%5D=1")
  status=$(jq -r '.data[0].attributes.status // "none"' <<<"${run}")
  created=$(jq -r '.data[0].attributes["created-at"] // empty' <<<"${run}")
  case "${status}" in
    applied|planned_and_finished) echo "ok    ${name}: ${status}" ;;
    pending|plan_queued|planning|planned|cost_estimated|policy_checked|apply_queued|applying|confirmed|post_plan_completed)
      age=$(( (now - $(date -u -d "${created}" +%s)) / 3600 ))
      if [ "${age}" -ge 2 ]; then echo "FAIL  ${name}: ${status} for ${age}h"; fail=1; else echo "wait  ${name}: ${status}"; fi ;;
    *) echo "FAIL  ${name}: ${status}"; fail=1 ;;
  esac
done < <(api "organizations/${TFC_ORGANIZATION}/workspaces?page%5Bsize%5D=100" | jq -r '.data[] | [.id, .attributes.name] | @tsv')
exit "${fail}"
```

Run the test: PASS. `make shellcheck`.

- [ ] **Step 3: Write the workflow.**

```yaml
name: Sandbox estate probe

# Proof that the landing zone works as a system (IAC-5, ARC-1/2/3/10):
#   convergence: every sandbox HCP workspace has applied the current main;
#   gcp/aws:     real-apply probes from inside each spoke (dev and prod).
# A green run on a commit is half of the Release Proof (scripts/require-release-proof.sh).
on:
  schedule:
    - cron: "17 6 * * *"   # after the 03:17 unit e2e and the overnight merges converge
  workflow_dispatch:

permissions: {}

concurrency:
  group: sandbox-estate-probe
  cancel-in-progress: false

env:
  TERRAFORM_VERSION: "1.17.1"
  TF_IN_AUTOMATION: "true"
  TF_INPUT: "false"

jobs:
  convergence:
    name: Estate convergence
    runs-on: ubuntu-latest
    timeout-minutes: 10
    environment: estate-probe
    permissions:
      contents: read
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: block
          allowed-endpoints: >
            github.com:443
            api.github.com:443
            app.terraform.io:443
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - name: Every sandbox workspace converged
        env:
          TFC_TOKEN: ${{ secrets.SANDBOX_TFC_TOKEN_READ }}
          TFC_ORGANIZATION: ${{ vars.SANDBOX_TFC_ORGANIZATION }}
        run: ./scripts/estate-convergence.sh

  gcp:
    name: Estate probe GCP (${{ matrix.env }})
    needs: convergence
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: estate-probe
    permissions:
      contents: read
      id-token: write
    strategy:
      fail-fast: false
      matrix:
        env: [dev, prod]
    env:
      TF_VAR_run_id: ${{ github.run_id }}
      TF_VAR_run_attempt: ${{ github.run_attempt }}
      TF_VAR_region: ${{ vars.SANDBOX_GCP_REGION }}
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: audit  # block after the first green run (Task 20)
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - uses: hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e  # v4.0.1
        with:
          terraform_version: ${{ env.TERRAFORM_VERSION }}
          terraform_wrapper: false
      - name: Read the spoke's outputs from the sandbox estate
        env:
          TFC_TOKEN: ${{ secrets.SANDBOX_TFC_TOKEN_READ }}
          TFC_ORGANIZATION: ${{ vars.SANDBOX_TFC_ORGANIZATION }}
          ENV: ${{ matrix.env }}
        run: ./scripts/estate-outputs.sh gcp "${ENV}" >> "$GITHUB_ENV"
      - name: Authenticate to the sandbox GCP organization
        id: auth
        uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093  # v3.0.0
        with:
          workload_identity_provider: ${{ vars.SANDBOX_GCP_PROBE_WIF_PROVIDER }}
          service_account: ${{ vars.SANDBOX_GCP_PROBE_SA }}
      - name: Probe (real apply + destroy)
        run: |
          terraform -chdir=tests/e2e/estate-gcp init -input=false -lockfile=readonly
          terraform -chdir=tests/e2e/estate-gcp test -junit-xml="${RUNNER_TEMP}/estate-gcp-${{ matrix.env }}.xml"
      - name: Safety-net cleanup
        if: always() && steps.auth.outcome == 'success'
        run: ./tests/e2e/scripts/cleanup-estate-gcp.sh "${TF_VAR_host_project_id}" "${TF_VAR_dns_project_id}" "${TF_VAR_run_id}"

  aws:
    name: Estate probe AWS (${{ matrix.env }})
    needs: convergence
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: estate-probe
    permissions:
      contents: read
      id-token: write
    strategy:
      fail-fast: false
      matrix:
        env: [dev, prod]
    env:
      TF_VAR_run_id: ${{ github.run_id }}
      TF_VAR_run_attempt: ${{ github.run_attempt }}
      TF_VAR_region: ${{ vars.SANDBOX_AWS_REGION }}
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: audit
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - uses: hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e  # v4.0.1
        with:
          terraform_version: ${{ env.TERRAFORM_VERSION }}
          terraform_wrapper: false
      - name: Read the spoke's outputs from the sandbox estate
        env:
          TFC_TOKEN: ${{ secrets.SANDBOX_TFC_TOKEN_READ }}
          TFC_ORGANIZATION: ${{ vars.SANDBOX_TFC_ORGANIZATION }}
          ENV: ${{ matrix.env }}
        run: ./scripts/estate-outputs.sh aws "${ENV}" >> "$GITHUB_ENV"
      - name: Authenticate to the workload account (GitHub OIDC)
        id: auth
        uses: aws-actions/configure-aws-credentials@e1253824e5c10ff9df46874f81ed3ec929e19cfd  # v6.3.0
        with:
          role-to-assume: ${{ fromJSON(vars.SANDBOX_AWS_PROBE_ROLES)[matrix.env] }}
          aws-region: ${{ vars.SANDBOX_AWS_REGION }}
          role-session-name: estate-probe-${{ github.run_id }}
      - name: Probe (real apply + destroy)
        run: |
          terraform -chdir=tests/e2e/estate-aws init -input=false -lockfile=readonly
          terraform -chdir=tests/e2e/estate-aws test -junit-xml="${RUNNER_TEMP}/estate-aws-${{ matrix.env }}.xml"
      - name: Safety-net cleanup
        if: always() && steps.auth.outcome == 'success'
        run: ./tests/e2e/scripts/cleanup-aws.sh "${TF_VAR_region}" "${TF_VAR_run_id}"

  summary:
    name: Estate Proof
    needs: [convergence, gcp, aws]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions: {}
    steps:
      - name: Fail unless every probe passed
        env:
          RESULTS: ${{ join(needs.*.result, ' ') }}
        run: |
          echo "results: ${RESULTS}"
          for r in ${RESULTS}; do [ "$r" = "success" ] || exit 1; done
```

Write `scripts/estate-outputs.sh <cloud> <env>` (with a fixture-driven test like Step 1) that reads `current-state-version-outputs` of `gcp-workload-<env>` and `gcp-network-hub` (or `aws-workload-<env>`) and prints `TF_VAR_<name>=<value>` lines. Use the output names in `envs/gcp/workload/outputs.tf` (`host_project_id`, `subnets`), `envs/gcp/network-hub/outputs.tf` (`contract`) and `envs/aws/workload/outputs.tf` (`vpc_id`); read the contract keys with `terraform console` on the root before writing the `jq` paths. The `SANDBOX_TFC_TOKEN_READ` team token reads state outputs only (it never reads full state).

- [ ] **Step 4:** `pre-commit run yamllint --files .github/workflows/sandbox-estate-probe.yml`, `make zizmor test-scripts shellcheck`, `bash scripts/check-github-governance.sh` (the `estate-probe` environment is declared in Task 9). Commit: `ci(e2e): nightly estate convergence and spoke probes in the sandbox`.

## Task 29: Release Proof gate on release PRs (A) (D14)

**Files:** `.github/workflows/terraform-plan.yml`, `docs/guides/BRANCH_PROTECTION.md`, `CONTRIBUTING.md`

- [ ] **Step 1:** Add the job (it reuses `scripts/require-release-proof.sh` from Task 16, which already has a test):

```yaml
  release-proof:
    name: Release Proof
    # Only release-please PRs: no release without a green estate probe and
    # green unit e2e on the exact commit being released (D14).
    if: github.event_name == 'pull_request' && startsWith(github.head_ref, 'release-please--')
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
      actions: read
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - name: Require the release proof on the base commit
        env:
          GH_TOKEN: ${{ github.token }}
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: ./scripts/require-release-proof.sh "${GITHUB_REPOSITORY}" "${BASE_SHA}"
```

Add `release-proof` to the `summary` job's `needs`, add a row to its table, and make its result check accept `skipped` for this job only (non-release PRs). Because the job feeds `Validation Summary`, the single required check fails closed on a release PR without proof.

- [ ] **Step 2:** `make required-checks` PASS (the job is not a separate required context). Document the criterion in `CONTRIBUTING.md` ("Releasing") and `docs/guides/BRANCH_PROTECTION.md`, replacing the "Sandbox convergence" paragraph.
- [ ] **Step 3:** Commit: `ci(release): block release PRs without a green estate proof on the base commit`.

## Task 30: Stand up the sandboxes and record the first green proof (B + C)

All steps need the funding in D10.

- [ ] **Step 1 (C):** Approve the budget: HCP Terraform Standard for two organizations, about USD 1,000 to 1,300 per month for the sandbox estate, under USD 5 per month for the unit sandbox. Name the bill owner (platform cost centre, per `sandbox-estate.md`).
- [ ] **Step 2 (B), unit e2e sandbox:** follow `docs/guides/sandbox-e2e.md` "Enabling it": one empty GCP project and one empty AWS account. Then:

```bash
gh variable set E2E_GCP_WIF_PROVIDER --body "projects/<n>/locations/global/workloadIdentityPools/<pool>/providers/<provider>"
gh variable set E2E_GCP_SA --body "e2e-runner@<project>.iam.gserviceaccount.com"
gh variable set E2E_GCP_PROJECT --body "<project>"
gh variable set E2E_GCP_REGION --body "us-east4"
gh variable set E2E_AWS_ROLE_ARN --body "arn:aws:iam::<account>:role/e2e-runner"
gh variable set E2E_AWS_REGION --body "us-east-2"
gh label create e2e --force
gh workflow run sandbox-e2e.yml -f cloud=all
```

A maintainer approves the `e2e-sandbox` environment gate. Expected: both suites green, cleanup steps report nothing left.

- [ ] **Step 3 (B), sandbox estate:** follow `docs/guides/sandbox-estate.md` with the Task 25 config: second HCP organization, Cloud Identity domain and GCP organization, AWS organization (request an account quota of 15 first), replace every `REPLACE_WITH_*` placeholder, phase 0, then apply in the documented order. Create in the sandbox HCP organization a read-only team (`estate-reader`: read runs, read state outputs) and its token.
- [ ] **Step 4 (B), probe identities:** GCP: in the sandbox organization, a WIF pool for GitHub with condition `assertion.sub == 'repo:<owner>/Ashes-Devops-Tools:environment:estate-probe'`, and SA `estate-probe` with `roles/compute.instanceAdmin.v1` on each environment's host project and a custom role (`dns.changes.create`, `dns.changes.get`, `dns.resourceRecordSets.*`, `dns.managedZones.get`) on the DNS anchor project. Check that sandbox org policies allow `debian-cloud` images (`constraints/compute.trustedImageProjects`) and that the prod VPC-SC perimeter admits the probe SA (if not, that is ARC-13 showing up: record it). AWS: deploy `templates/aws/bootstrap/e2e-probe-role.yaml` to `workload_dev` and `workload_prod` with a StackSet.

```bash
gh secret set SANDBOX_TFC_TOKEN_READ --env estate-probe
gh variable set SANDBOX_TFC_ORGANIZATION --env estate-probe --body "<sandbox-org>"
gh variable set SANDBOX_GCP_REGION --env estate-probe --body "us-east4"
gh variable set SANDBOX_AWS_REGION --env estate-probe --body "us-east-2"
gh variable set SANDBOX_GCP_PROBE_WIF_PROVIDER --env estate-probe --body "<provider>"
gh variable set SANDBOX_GCP_PROBE_SA --env estate-probe --body "estate-probe@<project>.iam.gserviceaccount.com"
gh variable set SANDBOX_AWS_PROBE_ROLES --env estate-probe --body '{"dev":"arn:aws:iam::<dev>:role/e2e-probe","prod":"arn:aws:iam::<prod>:role/e2e-probe"}'
gh workflow run sandbox-estate-probe.yml
```

- [ ] **Step 5 (B), cost guard and teardown:** budget alerts at 50, 80 and 100 percent are built in (`org.monthly_budget_usd`). Add an AWS Budgets action that applies a deny-all-except-delete SCP to the Workloads OU at 120 percent, and on GCP leave the billing kill switch off (as `sandbox-estate.md` explains). Every probe resource carries `e2e-run-id` and is removed by `terraform test` plus the safety-net scripts. Review sandbox spend weekly for the first month.
- [ ] **Step 6 (B), turn the checks on:** `gh variable delete REAL_CLOUD_CHECKS_OPT_OUT`, configure `TFC_TOKEN_DRIFT` and `TFC_ORGANIZATION` in `tfc-drift` (production HCP org), remove the Task 5 entry from `docs/known-gaps.md`.
- [ ] **Step 7 (A), evidence:** when the first estate probe and unit e2e are green on the same commit, write `docs/evidence/2026-xx-first-real-apply.md` with the run URLs, commit SHA, workspace list, probe results and cost so far. Update the README status line (with the docs workstream). Expect earlier red runs to name ARC-1, ARC-2, ARC-3 and ARC-10 in their assertion messages; link those runs from the matching architecture fixes.
- [ ] **Step 8:** Cut the next release only after `Release Proof` is green on the release PR.

---

## Self-review against the brief

| Brief item | Where |
|---|---|
| CICD-1, CICD-8 | Tasks 8, 14 (ruleset, `required-checks-live` reads rules and fails while classic protection exists) |
| CICD-3 | Tasks 12, 13 (slug-sourced policy sets + OPA content guard; real CODEOWNERS after D1) |
| CICD-4 | Task 9 (all 9 environments, policies, reviewers, `can_admins_bypass = false`) |
| CICD-5 | Tasks 16, 17, D7 (OPA input verified first; four-eyes via promotion environment) |
| CICD-6 | Tasks 15, 16 (production branch, exact-commit fast-forward) |
| CICD-7 | Tasks 8, 18 (tag rulesets, signatures on main, provenance + SBOM, fail-closed verifier) |
| CICD-9 | Task 10 |
| CICD-12, 13, 15, 16, 17, 18 | Tasks 20, 21, 6, 19, 22, 19 |
| IAC-3, IAC-6 | Tasks 23, 21 |
| Red CI on main | Tasks 1 to 5 |
| WS6 proof, cost guard, teardown, release criterion | Tasks 25 to 30 |
| Bus factor | Task 24 (artefacts, A) and its people step (C) |
| New-root conventions | Tasks 7, 11 (config.tf, versions.tf, 3-platform lockfile, 3 test suites, README markers, counts, CODEOWNERS, schema, shard discovery is automatic) |
