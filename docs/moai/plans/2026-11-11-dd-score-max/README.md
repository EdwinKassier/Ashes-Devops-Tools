# Due-diligence score maximisation: Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or build to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise every score in [the 2026-11-11 due-diligence audit](../../../audit/2026-11-11-due-diligence-audit.md) from 5.0 overall to the highest level this repository can honestly reach, and make each gain provable to a buyer.

**Architecture:** Five workstream sub-plans hold the 114 test-first tasks. This master plan fixes the order, names the files that two workstreams share, lists the decisions only the owner can make, and states a score ceiling for each lens. Code changes come first, then the operator and funding steps that turn "mock-tested" into "proven". Long-range capability (WS7) needs its own design work, so this plan only scopes it.

**Tech Stack:** Terraform 1.17.1, google/google-beta ~> 8.0, aws >= 6.46.0 < 7.0.0, tfe, integrations/github (new), OPA/Rego, HCP Terraform, GitHub Actions, python-hcl2 (new, hash-pinned), bash.

---

## Score ceilings

A score is only worth what a buyer can verify. Code alone cannot prove that the estate works, that two people review changes, or that controls operated for a year. So each lens has three stages, plus a hard ceiling.

| Lens | Now | After code (Phases 0 to 2) | After operator and funding (Phases 3 and 4) | After WS7 and 6 to 12 months of operation | What stops a 10 |
|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 8.5 | 9.0 | HCP Terraform organization owners stay the root of trust. A 9+ needs an external penetration test. |
| Compliance readiness | 4.5 | 7.0 | 7.5 | 8.5 to 9.0 | SOC 2 Type II and ISO certification need operating evidence over time. FedRAMP High, IL5 and EU sovereign partitions stay out of scope. |
| System design | 4.8 | 7.5 | 8.0 | 9.0 | Needs a second region (ADR 0009) and team-owned stacks (ADR 0015). |
| Operability | 4.5 | 6.5 | 8.0 | 8.5 to 9.0 | Needs measured RTO and RPO from real restore drills, and real usage. |
| Terraform craft | 7.5 | 8.5 | 9.0 | 9.0 | Per-module registry versioning is deferred until 1.0 (WS5 D9). |
| Delivery and supply chain | 4.5 | 6.0 | 8.5 | 9.0 | OpenSSF Code-Review needs a second human reviewer on every change. |
| Adoption readiness | 3.5 | 5.0 | 6.5 | 8.0 | Needs time in market, external adopters and a support commitment. Code cannot buy these. |
| Documentation accuracy | 5.0 | 9.0 | 9.0 | 9.5 | Generated references and drift checks keep it true. |
| **Overall** | **5.0** | **7.2** | **8.1** | **8.9** | |

**Read this table as a forecast, not a promise.** Each stage ends with a fresh, independent six-lens re-audit (Task M3). The re-audit sets the real score.

## Workstreams

| ID | Sub-plan | Tasks | Covers |
|---|---|---|---|
| WS1 | [Every claim is true and every documented path works](ws1-truth-and-config.md) | 28 | ADO-1 to ADO-28, IAC-1, IAC-2, IAC-4, IAC-8 to IAC-11, IAC-14 |
| WS2 | [Data plane works as a system](ws2-data-plane.md) | 17 | ARC-1 to ARC-6, ARC-10 to ARC-12, ARC-16, ARC-21, and 3 new defects |
| WS3 | [Trust model holds](ws3-trust-model.md) | 16 | SEC-1 to SEC-12, CICD-2, CICD-10, CICD-11 |
| WS4 | [Controls a regulated auditor can test](ws4-compliance.md) | 23 | CMP-1 to CMP-20, ARC-8, ARC-17, framework crosswalks |
| WS5 | [Change management, supply chain and proof](ws5-governance-and-proof.md) | 30 | CICD-1 to CICD-18, IAC-3, IAC-5, IAC-6, ADO-10, red CI, sandbox proof |
| WS7 | Market breadth (this file, scoped only) | 6 epics | ADR 0015, ADR 0016, ADR 0009, IdP, EKS, PCI standard |

Each task in WS5 is labelled (A) code an agent can do, (B) an admin step with exact commands, or (C) a funding or people step.

## Corrections to the audit found while planning

The planners read the code behind every finding. Fix the audit report before any buyer sees it (Task M1).

| Finding | Correction |
|---|---|
| CMP-7 | The production egress gate already exists: `envs/aws/network/config.tf:83` and `modules/aws/stages/network-hub/main.tf:409-423` fail the plan for alert-only egress in production. The endpoint policy, VPC-SC, flow-log and missing-regulated-zone parts stay valid. |
| CMP-16 | The AWS console-without-MFA alert exists (`security-notifications/main.tf:61`, CIS 4.2). What remains is Identity Center MFA and Google 2-Step Verification, which have no Terraform API. |
| CMP-15 | SCC tier activation has no Terraform API. The fix is documentation only. |
| SEC-1 | Wider than reported: PR speculative plans also leak the token, not only CLI plans. |
| SEC-3 | The escalation is the self-grant of `iam.denyAdmin`; deleting alerts only removes detection. A missed path: with `enable_pam`, `organization-apply` holds `privilegedaccessmanager.admin`. |
| SEC-10 | The wildcard binding needs `setIamPolicy` on the service account, not `workloadIdentityPoolAdmin`. |
| IAC-4 | 9 `any` inputs, not 11. The 3 network-hub inputs have no allowlist at all. |
| ADO-3 | `aws-bootstrap.md:146` already documents local mode. Only the step 2 command is wrong. |
| ADO-11 | The live badges are accurate. The CHANGELOG and README release-please text is what misleads. |
| ADO-20 | The first stand-up fits the quota (9 of 10 accounts). The third workload account fails. |
| ADO-23 | `README.md:42` is correct. Only the mermaid diagram and `bootstrap.md:13` are wrong. |
| CICD-12 | `release.yml` and `drift-detection.yml` already block egress. |
| CICD-16 | Valid but Low: only a writer can create a branch. |
| "CI unfunded" | Actions ran 9 workflows on `c08f3c4f`. The cost question is HCP Terraform and the sandbox clouds (WS5 D10). |

New defects found while planning, all fixed inside the workstreams:

- AWS resolver endpoints default to fake security-group and subnet IDs, so they cannot apply (WS2 Task 7).
- AWS interface endpoints use the deny-all default security group, so nothing can reach them (WS2 Task 8).
- Workload apply SAs lack `roles/dns.peer`, so the spoke DNS peering zone fails with 403 (WS2 Task 4).
- The backup account sits in the Infrastructure OU, so the Workloads-OU backup policy never writes to it. Aurora carries no `backup=true` tag. EBS on the `aws/ebs` key cannot be copied cross-account (WS4 Tasks 1 and 2).
- The region regex rejects GovCloud names (WS4 Task 22).
- Trivy also fails on 3 High findings. yamllint fails first, so 14 meta-lint steps have not run on recent commits (WS5 Task 1).
- Private vulnerability reporting and Discussions are off, but `SECURITY.md` relies on both (WS1 Task 22).

## Owner decisions

The sub-plans list 39 decisions. Four block progress and need the owner. For the other 35, the recommendation in each sub-plan is the default. Execution proceeds on that default unless the owner overrules it before the task starts.

| # | Decision | Blocks | Recommendation |
|---|---|---|---|
| O1 | Move the repository from the personal account to a GitHub organization (WS5 D1) | WS5 Task 13 (CODEOWNERS teams), team reviewers in rulesets | Yes. A personal repository cannot have teams. GitHub redirects the old URL. |
| O2 | Fund HCP Terraform Standard and the sandbox estate (WS5 D10) | Phase 4, every "proven" claim | About USD 1,000 to 1,300 per month for the `starter` sandbox, plus the HCP Standard quote. Without it the overall score stops near 7.2. |
| O3 | Recruit a second maintainer with merge rights | Delivery above 6, adoption above 5, WS5 D2 sunset | Interim: a dated 60-day admin bypass for pull requests only (WS5 D2). |
| O4 | Accept irreversible compliance settings in the production scaffold (WS4 D3) | WS4 Tasks 2, 6, 8 | Off by default; `make init --profile production` writes them, so the owner commits each one knowingly. |

## Files more than one workstream edits

Run tasks that touch the same file one after another, in the order below. Rebase before each task.

| File | Order |
|---|---|
| `config/landing-zone.schema.json` | WS1 Task 5 (required `is_production`) → WS4 shared config contract (Task 1 Step 0) → WS2 config keys (Tasks 1, 6, 7, 12, 15) → WS5 Task 25 |
| `envs/tfc-admin/main.tf` | WS3 Task 1 → WS3 Task 4 → WS3 Task 12 → WS2 Task 3 → WS5 Tasks 11, 12, 15 |
| `envs/tfc-admin/config.tf`, `variables.tf` | WS1 Tasks 5, 13 → WS2 Task 3 → WS3 Task 1 |
| `scripts/check-consistency.sh` | WS3 Task 3 (replaces the grep gate) → WS1 Task 5 → WS4 tasks |
| `modules/gcp/stages/bootstrap/service_accounts.tf`, `variables.tf` | WS3 Task 5 → WS3 Task 6 → WS2 Task 4 (`dns.peer`) → WS4 Task 17 |
| `modules/gcp/stages/organization/main.tf`, `variables.tf`; `envs/gcp/organization/main.tf` | WS3 Task 6 → WS4 Tasks 5, 8, 9 |
| `modules/gcp/stages/app-services/*` | WS3 Task 7 → WS2 Task 16 → WS4 Task 17 |
| `modules/aws/stages/app-services/*` | WS2 Task 17 → WS5 Task 22 |
| `modules/aws/stages/workload/main.tf`, `envs/aws/network/config.tf` | WS2 Tasks 1, 6 → WS4 Tasks 2, 11 |
| `modules/aws/network/vpc-endpoints/main.tf` | WS2 Task 8 → WS4 Task 11 |
| `envs/gcp/workload/main.tf`, `variables.tf` | WS1 Task 5 → WS3 Task 9 → WS2 Task 14 → WS4 Task 11 |
| `Makefile`, `.github/workflows/terraform-plan.yml`, `drift-detection.yml` | WS5 Tasks 1, 6 → WS1 Tasks 6, 11, 20 → WS3 Tasks 3, 12 → WS5 Task 19 |

## Phases

Each phase is one pull request per workstream slice, so a reviewer sees one concern at a time. Every phase ends with the full local gate:

```bash
make fmt-check consistency count-check links docs-check config-check
```

```bash
make test TERRAFORM=<path to terraform 1.17.1>
```

Expected: every target exits 0, and `terraform test` reports 0 failed.

### Task M1: Correct the audit report (before Phase 0)

**Files:**
- Modify: `docs/audit/2026-11-11-due-diligence-audit.md`

- [ ] **Step 1:** Apply every row of "Corrections to the audit found while planning" above. Use the same finding IDs. Add a "Corrections after planning (2026-11-11)" section at the end that lists each change.
- [ ] **Step 2:** Run `make links`. Expected: 0 broken.
- [ ] **Step 3: Commit.**

```bash
git add docs/audit/2026-11-11-due-diligence-audit.md docs/moai/plans/2026-11-11-dd-score-max/
git commit -m "docs(audit): add 2026-11-11 due-diligence audit, corrections and remediation plans"
```

### Phase 0: Green CI and true claims (days)

- [ ] WS5 Tasks 1 to 6: yamllint, Trivy, Checkov, release App, nightly opt-out, `make ci` parity.
- [ ] WS1 Tasks 1 to 4: README retitle and CI status, workload plan command, first AWS apply path, generated variable reference.
- [ ] WS4 Tasks 4 and 21: make the backup rows true; fix stale citations and `SECURITY.md`.
- **Exit:** `main` is green. No README, `SECURITY.md` or control-matrix sentence contradicts the code.

### Phase 1: Critical defects (one to two weeks)

- [ ] WS1 Tasks 5 and 6: one production rule (IAC-1) and a validated real config file (IAC-2). Do these first: WS3 Task 9 and WS4 Task 11 read `is_production`.
- [ ] WS2 Tasks 1 to 6: ARC-1, ARC-2, ARC-3.
- [ ] WS3 Tasks 1 to 3: SEC-1, SEC-2.
- [ ] WS4 Tasks 1 to 3, 5 and 6: CMP-1, CMP-2.
- **Exit:** every Critical in the audit is closed in code with a failing-then-passing test, or reclassified in the audit with evidence.

### Phase 2: High and Medium findings (two to four weeks)

- [ ] WS3 Tasks 4 to 16.
- [ ] WS2 Tasks 7 to 17.
- [ ] WS4 Tasks 7 to 20, 22, 23.
- [ ] WS1 Tasks 7 to 28.
- [ ] WS5 Tasks 19 to 23 (code parts).
- **Exit:** re-audit (Task M3). Target: overall about 7.2.

### Phase 3: Codified governance (one to two weeks, needs O1 and O3)

- [ ] WS5 Tasks 7 to 18: the `envs/github-admin` root, rulesets, environments, security settings, uploaded policy sets, real CODEOWNERS, production branch, `promote.yml`, provenance and SBOM.
- [ ] WS5 Task 24: `MAINTAINERS.md`, `GOVERNANCE.md`, support and compatibility policy.
- **Exit:** `gh api repos/<owner>/Ashes-Devops-Tools/rulesets` lists the rulesets, and a test PR without review cannot merge.

### Phase 4: Proof (two to four weeks, needs O2)

- [ ] WS5 Tasks 25 to 30: sandbox estate in `us-east-2` and `us-east4` with two GCP environments and two AWS workload accounts, estate probe, Release Proof gate, first green run.
- [ ] Run every "Sandbox proof" check in WS2, WS3 and WS4. Move each proven item out of the "mock-tested only" lists in `docs/known-gaps.md`.
- [ ] Cut `v0.2.0` through the Release Proof gate.
- **Exit:** re-audit (Task M3). Target: overall about 8.1.

### Phase 5: WS7 market breadth (one to two quarters)

Each epic needs its own brainstorm and plan before any code. Scope only:

| Epic | Source | Lenses it raises |
|---|---|---|
| E1 Team-owned app stacks (`envs/gcp/app`, `envs/aws/app`) | ADR 0015 | System design, operability, adoption |
| E2 Split `aws-organization` | ADR 0016 | Security, operability |
| E3 Second AWS region and GCP regional hub, with stated RTO and RPO and a restore drill | ADR 0009, WS4 Task 14 | System design, operability, compliance |
| E4 IdP integration: SCIM to IAM Identity Center, Workforce Identity Federation | ADO-8 | Security, adoption |
| E5 EKS golden path, matching `gke-autopilot` | ADO-12 | Adoption |
| E6 Security Hub PCI DSS v4.0.1 standard as an opt-in, plus SaaS hardening (Supabase PITR and network restrictions, Vercel deployment protection and log drains) | CMP review, ADO-9 | Compliance, adoption |

- **Exit:** re-audit after 6 to 12 months of operation. Target: overall about 8.9.

### Task M2: Track execution

**Files:**
- Modify: `docs/known-gaps.md`

- [ ] **Step 1:** At the start of each phase, add one line under "OPEN — residual items" that names the phase and links this plan.
- [ ] **Step 2:** At the end of each phase, remove the line and move every proven item out of the "mock-tested only" lists.
- [ ] **Step 3: Commit** with `docs(known-gaps): phase <n> status`.

### Task M3: Re-audit after Phases 2, 4 and 5

- [ ] **Step 1:** Run six independent reviewers with the same lenses and briefs as the 2026-11-11 audit. Give them the code, not this plan.
- [ ] **Step 2:** The lead reviewer re-reads every new Critical and a sample of Highs.
- [ ] **Step 3:** Write `docs/audit/<date>-due-diligence-reaudit.md` with the scorecard and the delta against this plan's forecast.
- [ ] **Step 4:** If a lens lands more than 0.5 below the forecast, add the gap as tasks to the relevant workstream before the next phase.

**Status after Phase 2 (2026-11-12):** the re-audit scored 6.0 overall against the 7.2 forecast; seven lenses landed more than 0.5 below. The gap tasks are listed in [the re-audit report](../../../audit/2026-11-12-due-diligence-reaudit.md#gap-tasks-before-phase-3) as Phase 2b.

## Findings no sub-plan owns (run in Phase 2)

The self-review found four findings that no sub-plan fixes. Their evidence was read on 2026-11-11.

### Task M4: An enforced environment perimeter admits its own pipeline (ARC-13)

The environment perimeter has no default ingress rule (`modules/gcp/stages/environment/main.tf:17-24`). WS3 Task 9 and WS4 Task 11 push production toward an enforced perimeter. Once enforced, the environment's own `wl-<env>-plan` and `wl-<env>-apply` service accounts are blocked. gcp-bootstrap already publishes them in `contract.workload_service_accounts` (`envs/gcp/bootstrap/outputs.tf:27,62`), and gcp-projects already reads them (`envs/gcp/projects/main.tf:97-98`).

**Files:**
- Modify: `envs/gcp/projects/outputs.tf:14-31` (add `automation_identities` to each `environment_config` entry) and `:54-65` (type)
- Modify: `modules/gcp/stages/environment/variables.tf` (new input `automation_identities`)
- Modify: `modules/gcp/stages/environment/main.tf:23` (`effective_vpc_sc_ingress_policies`)
- Modify: `envs/gcp/workload/main.tf` (pass `try(local.env_config.automation_identities, [])`)
- Test: `modules/gcp/stages/environment/tests/plan_assertions.tftest.hcl`, `envs/gcp/projects/tests/` contract suite

- [ ] **Step 1: Write the failing test** in `modules/gcp/stages/environment/tests/plan_assertions.tftest.hcl`. Copy the variables of the suite's existing enforced-perimeter run, and add:

```hcl
run "enforced_perimeter_admits_the_environment_pipeline" {
  command = plan

  variables {
    automation_identities = [
      "serviceAccount:wl-dev-plan@admin-abc.iam.gserviceaccount.com",
      "serviceAccount:wl-dev-apply@admin-abc.iam.gserviceaccount.com",
    ]
  }

  assert {
    condition = anytrue([
      for p in local.effective_vpc_sc_ingress_policies :
      toset(p.identities) == toset(var.automation_identities)
    ])
    error_message = "the perimeter must carry one ingress rule for the environment's own plan and apply service accounts"
  }
}

run "no_identities_means_no_default_rule" {
  command = plan

  variables {
    automation_identities = []
  }

  assert {
    condition     = length(local.effective_vpc_sc_ingress_policies) == length(var.vpc_service_controls.ingress_policies)
    error_message = "without automation identities the stage must add no ingress rule"
  }
}
```

- [ ] **Step 2: Run it.** `make test TEST_DIRS=modules/gcp/stages/environment TERRAFORM=<tf 1.17.1>`. Expected: FAIL, `An input variable with the name "automation_identities" has not been declared`.
- [ ] **Step 3: Implement.** In `variables.tf`:

```hcl
variable "automation_identities" {
  description = "The environment's own Terraform plan and apply identities (serviceAccount:<email>). When set, the perimeter gets one ingress rule that lets them reach every restricted service, so an enforced perimeter does not block the pipeline. Empty = no rule."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for i in var.automation_identities : can(regex("^serviceAccount:[a-z0-9-]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", i))])
    error_message = "automation_identities entries must be serviceAccount:<name>@<project>.iam.gserviceaccount.com."
  }
}
```

In `main.tf`, replace line 23 with the block below. Match the object to the `ingress_policies` element type at `variables.tf:221-236`; set every attribute that type declares without `optional()`.

```hcl
  automation_ingress_policy = length(var.automation_identities) == 0 ? [] : [{
    title         = "${var.environment}-pipeline"
    identities    = var.automation_identities
    identity_type = null
    sources       = [{ access_level = "*", resource = null }]
    operations    = [{ service_name = "*", method_selectors = [] }]
    resources     = ["*"]
  }]
  effective_vpc_sc_ingress_policies = concat(local.automation_ingress_policy, local.vpc_sc.ingress_policies)
```

In `envs/gcp/projects/outputs.tf`, add to each `environment_config` entry:

```hcl
        automation_identities = [for sa in compact([
          try(local.bootstrap.workload_service_accounts[env_key].plan, ""),
          try(local.bootstrap.workload_service_accounts[env_key].apply, ""),
        ]) : "serviceAccount:${sa}"]
```

Add `automation_identities = list(string)` to the type at `:54-65`. In `envs/gcp/workload/main.tf`, pass `automation_identities = try(local.env_config.automation_identities, [])` to `module "environment"`.

- [ ] **Step 4: Run.** Both suites, plus `make test TEST_DIRS=envs/gcp/projects` and `TEST_DIRS=envs/gcp/workload`. Expected: PASS.
- [ ] **Step 5: Docs.** Remove the ARC-13 residual from `docs/known-gaps.md` (the line that says an enforced prod perimeter blocks the TFC service accounts). Replace it with: "An enforced environment perimeter admits the environment's own plan and apply SAs (mock-tested; prove in the sandbox by enforcing the dev perimeter and running a plan)." Run `make docs`.
- [ ] **Step 6: Commit.** `git commit -m "feat(gcp-environment): enforced perimeters admit the environment's own pipeline identities"`

### Task M5: One drift source of record (ARC-14)

**Correction to the audit:** HCP health assessments are already on by default (`envs/tfc-admin/variables.tf:173`, `main.tf:1172`). What remains is the hand-kept GitHub workspace list (`.github/workflows/drift-detection.yml:126-155`) and two drift paths that can disagree.

**Files:**
- Modify: `.github/workflows/drift-detection.yml:1-45` (header) and `:126-155` (matrix)
- Modify: `docs/runbooks/` drift section in `docs/guides/TROUBLESHOOTING.md` or the runbook that `drift-detection.yml` names in its header
- Modify: `docs/audit/2026-11-11-due-diligence-audit.md` (ARC-14 text)

- [ ] **Step 1:** In the workflow header, state that HCP health assessments are the drift source of record when `enable_health_assessments = true`. The GitHub job is the fallback for the Free tier only.
- [ ] **Step 2:** Make the job exit 0 with a notice when the repository variable `TFC_HEALTH_ASSESSMENTS=true` is set, before the matrix runs:

```yaml
      - name: Skip when HCP health assessments are the drift source
        if: vars.TFC_HEALTH_ASSESSMENTS == 'true'
        run: echo "::notice::HCP health assessments own drift detection for this estate; this job is the Free-tier fallback."
```

  Put `if: vars.TFC_HEALTH_ASSESSMENTS != 'true'` on the matrix job.
- [ ] **Step 3:** Run `make lint-yaml` or the yamllint target the Makefile defines, and `zizmor` if WS5 Task 19 has landed. Expected: 0 errors.
- [ ] **Step 4:** Correct ARC-14 in the audit report ("HCP health assessments are not used" is false).
- [ ] **Step 5: Commit.** `git commit -m "ci(drift): HCP health assessments are the drift source; the GitHub job is the Free-tier fallback"`

### Task M6: AWS network alarms for TGW, VPN, NAT and firewall (ARC-15)

**Files:**
- Modify: `modules/aws/stages/network-hub/variables.tf` (new `alarm_sns_topic_arn`)
- Create: `modules/aws/stages/network-hub/alarms.tf`
- Modify: `modules/aws/stages/network-hub/outputs.tf` (`alarm_topic_arn`)
- Test: `modules/aws/stages/network-hub/tests/plan_assertions.tftest.hcl`

- [ ] **Step 1: Write the failing test.** Reuse the file-level variables of the suite:

```hcl
run "hub_network_alarms_exist" {
  command = plan

  assert {
    condition     = alltrue([for k in ["tgw-blackhole-drops", "nat-port-allocation-errors"] : contains(keys(module.network_alarms.alarm_arns), k)])
    error_message = "the hub must alarm on TGW blackhole drops and NAT port allocation errors"
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/stages/network-hub TERRAFORM=<tf 1.17.1>`. Expected: FAIL, `Reference to undeclared module`. If `modules/aws/ops/cloudwatch/outputs.tf` names the alarm map differently, use that name in the test and in Step 3.
- [ ] **Step 3: Implement** `alarms.tf`:

```hcl
locals {
  nat_alarms = {
    for i, ng in aws_nat_gateway.this : "nat-port-allocation-errors${i == 0 ? "" : "-${i}"}" => {
      namespace           = "AWS/NATGateway"
      metric_name         = "ErrorPortAllocation"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      dimensions          = { NatGatewayId = ng.id }
      alarm_description   = "NAT gateway ${ng.id} cannot allocate source ports: spoke egress is failing."
    }
  }
  tgw_alarms = {
    "tgw-blackhole-drops" = {
      namespace           = "AWS/TransitGateway"
      metric_name         = "PacketDropCountBlackhole"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      dimensions          = { TransitGateway = module.transit_gateway.tgw_id }
      alarm_description   = "Traffic hits a blackhole route on the hub TGW: a spoke or segment has no route."
    }
  }
  vpn_alarms = var.enable_vpn ? {
    "vpn-tunnel-down" = {
      namespace           = "AWS/VPN"
      metric_name         = "TunnelState"
      statistic           = "Maximum"
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      evaluation_periods  = 2
      treat_missing_data  = "breaching"
      dimensions          = { VpnId = module.vpn[0].vpn_connection_id }
      alarm_description   = "Both hub VPN tunnels are down: on-premises connectivity is lost."
    }
  } : {}
}

module "network_alarms" {
  source = "../../ops/cloudwatch"

  name_prefix      = "network-hub"
  alarms           = merge(local.nat_alarms, local.tgw_alarms, local.vpn_alarms)
  create_sns_topic = var.alarm_sns_topic_arn == null
  sns_topic_arn    = var.alarm_sns_topic_arn
  tags             = var.tags
}
```

  Check `modules/aws/ops/cloudwatch/variables.tf:60-75` for how `create_sns_topic` and `sns_topic_arn` combine, and pass what it expects. Network Firewall has no drop-rate metric worth paging on in alert-only mode, so the firewall gets no alarm here; record that in known-gaps.

  In `variables.tf`:

```hcl
variable "alarm_sns_topic_arn" {
  description = "SNS topic for the hub network alarms. Null = the stage creates its own topic, which you must subscribe to."
  type        = string
  default     = null
}
```

- [ ] **Step 4: Run.** Expected: PASS. Then `make test TEST_DIRS=envs/aws/network`. Expected: PASS.
- [ ] **Step 5: Docs.** `make docs`. In `docs/known-gaps.md`, replace the ARC-15 line ("AWS alarms open") with the alarms now created, and state the firewall decision.
- [ ] **Step 6: Commit.** `git commit -m "feat(aws-network-hub): alarm on TGW blackholes, NAT port exhaustion and VPN tunnel loss"`

### Task M7: Assert the real SCP size limit (ARC-18)

**Status: done in commit 6bbcffcc (2026-11-12).** The text below is the original plan. Its evidence was wrong: the SCP quota is 10,240 characters and the RCP quota is 5,120 (AWS docs, checked 2026-11-12). The defect was the RCP test asserting 10,240. The commit adds a per-type plan precondition in `modules/aws/governance/organization-policy`; the worst case is `scp-deny-tamper` at 6,485 and `rcp-data-perimeter` at 2,811 characters.

**Original evidence (superseded):** ~~the AWS SCP limit is 5,120 characters.~~ A scratch measurement on 2026-11-11 with the suite's inputs gave `scp-deny-tamper` 4,376, `rcp-data-perimeter` 1,945, `scp-baseline` 1,641 and `scp-region-restriction` 1,464 characters.

**Files:**
- Modify: `modules/aws/governance/organization-policy/tests/plan_assertions.tftest.hcl:163-166`

- [ ] **Step 1: Write the failing test.** Add a run with realistic long inputs (64-character role names, a 63-character bucket name, four allowed regions):

```hcl
run "scps_fit_the_5120_character_limit_with_long_names" {
  command = plan

  variables {
    allowed_regions         = ["eu-west-2", "eu-west-1", "eu-central-1", "us-east-1"]
    terraform_run_role_arn  = "arn:aws:iam::111111111111:role/landing-zone/tfc-apply-organization-management-account-role"
    break_glass_role_arn    = "arn:aws:iam::111111111111:role/landing-zone/break-glass-organization-administrator-role"
    log_archive_bucket_name = "sra-log-archive-111111111111-eu-west-2-organization-trail-logs"
  }

  assert {
    condition = alltrue([
      for k, p in aws_organizations_policy.policy : length(p.content) <= 5120
      if startswith(k, "scp-") || startswith(k, "rcp-")
    ])
    error_message = "every SCP and RCP must fit the 5,120-character AWS limit: ${jsonencode({ for k, p in aws_organizations_policy.policy : k => length(p.content) })}"
  }
}
```

  Change the existing assertion at `:163-166` to `<= 5120` and its message to "the 5,120-character SCP limit".
- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/governance/organization-policy TERRAFORM=<tf 1.17.1>`. If it passes, the limit holds and the test now guards it. If it fails, the message prints each size; split the deny-tamper SCP into two policies (`scp-deny-tamper` and `scp-deny-tamper-logs`) along its existing Sid groups, and attach both where the first is attached.
- [ ] **Step 3: Coordinate.** WS3 Task 10 adds a KMS alias deny to the boundary, not the SCP. Any future SCP addition must keep this test green.
- [ ] **Step 4: Commit.** `git commit -m "test(organization-policy): assert the real 5,120-character SCP limit with long names"`

## Effort

| Phase | Agent effort | Owner or operator effort |
|---|---|---|
| 0 | 2 to 4 days | Create the release GitHub App |
| 1 | 1 to 2 weeks | Review 4 to 5 PRs |
| 2 | 2 to 4 weeks | Review about 10 PRs |
| 3 | 1 week | O1 transfer, O3 second maintainer, first `github-admin` apply |
| 4 | 1 week of code | O2 funding, sandbox accounts and projects, 2 to 3 weeks elapsed |
| 5 | One quarter or more | Design reviews per epic |

## Self-review

- **Coverage:** every finding ID in the audit maps to a workstream task, a master task (M4 to M7), an owner decision, or a WS7 epic. ARC-7 (onboarding steps) and ARC-9 (app services in platform workspaces) go to E1 and E2, with WS5 Task 25 covering the sandbox side of ARC-7. ARC-13 is Task M4, ARC-14 is Task M5, ARC-15 is Task M6, ARC-18 is Task M7. CICD-14 and ADO-10 (bus factor) are O3 plus WS5 Task 24. ADO-7, ADO-8 and ADO-12 are E1, E4 and E5. ARC-19 and ARC-20 (per-zone subnets, IPv6) are Low and go to the E3 design.
- **Phase placement:** Tasks M4 to M7 run in Phase 2. M4 must land before WS3 Task 9 and WS4 Task 11 are applied anywhere, because those tasks push production toward an enforced perimeter.
- **Placeholders:** none in this file. WS1 Task 9 leaves the HCP tier column to be filled from the live pricing page on the day of the change. That is deliberate: pricing must not be guessed.
- **Consistency:** finding IDs and task numbers match the five sub-plans as written on 2026-11-11.
