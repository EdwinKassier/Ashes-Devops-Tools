# Seventh due-diligence re-audit (2026-11-15)

Six new independent reviewers read the code at commit `fe03d146` (branch `claude/enterprise-devops-audit-949b65`, not merged and not pushed). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md) and re-audits [1](2026-11-12-due-diligence-reaudit.md) to [6](2026-11-15-due-diligence-reaudit-6.md). They read the code first and the earlier reports only at the end, to label each finding NEW or KNOWN. The lead re-checked every NEW High in the code.

This round follows the fixes for re-audit 6's "Fix now" list (commit `fe03d146`). One adversarial review ran on those fixes before the commit and found four further gaps, which the same commit closed.

Two process notes. All six reviewers were interrupted once by an account usage limit and resumed from their saved work. The security reviewer stopped building working exfiltration payloads partway (a safety boundary) and settled three findings from the provider schemas instead of live runs; they are marked accordingly.

## Verdict

**Overall: 6.7 / 10. Up from 6.4, the highest score so far. No Critical finding in the code.**

For the first time in four rounds, no reviewer bypassed the plan-time scanner's file-function checks. Security rose from 6.2 to 7.0, adoption readiness from 4.5 to 6.0, and the architecture reviewer confirmed the firewall change against the AWS documentation (the `_to_server` app-layer pair is the AWS-recommended default since June 2026). What holds the score down:

1. **A new class outside both plan-time layers (SEC-1).** Provider resource attributes that take a local path, such as `aws_s3_object.source`, `google_storage_bucket_object.source` and `aws_lambda_function.filename`, read a runner file at apply and upload it. The scanner and the OPA policy model only Terraform file functions. `data "tfe_slug"` and `vercel_deployment.files` are the same class (SEC-2, SEC-3).
2. **Regulated AWS estates are still weaker than regulated GCP estates.** A regulated AWS estate can switch the log archive to GOVERNANCE mode (CMP-2), its backups ignore the class (CMP-4), and its class can still be dropped by repointing a workspace's config file (CMP-1), because the class is not carried in an AWS contract as it now is on GCP.
3. **The tests miss security content that earlier audits did not look at (IAC-1).** On mutants seeded in such code, the kill rate was 50%. Narrowing the GCP org audit sink to the organization only (`include_children = false`) passes all 39 tests.
4. **Nothing is proven on a real cloud, and the live repository is ungoverned.** Live settings score 2/10. The branch is 241 commits ahead of `main`, on no remote, and has never run in GitHub CI. 69 breaking commits are unreleased.

## Scorecard

| Lens | 2026-11-11 | Forecast | RA 1 | RA 2 | RA 3 | RA 4 | RA 5 | RA 6 | RA 7 | Change |
|---|---|---|---|---|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | 5.5 | 7.5 | 6.0 | 6.2 | 7.0 | +0.8 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 6.0 | 5.8 | 6.0 | 6.4 | 6.5 | +0.1 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | 6.0 | 5.5 | 6.8 | 6.8 | 6.9 | +0.1 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | 4.5 | 5.5 | 5.8 | 5.6 | 5.8 | +0.2 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | 7.0 | 7.4 | 6.8 | 7.2 | 6.9 | -0.3 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | 5.5 | 7.0 | 7.0 | 7.6 | 7.5 | -0.1 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | 4.5 | 4.5 | 4.5 | 4.5 | 6.0 | +1.5 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | 8.0 | 7.5 | 8.0 | 7.0 | 7.0 | 0.0 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **5.9** | **6.3** | **6.4** | **6.4** | **6.7** | **+0.3** |

Delivery is scored on the branch's code; live settings score 2/10. The Terraform craft drop reflects a harder mutation test (mutants placed in security code earlier audits had not examined), not a regression. Panel-to-panel differences of about 0.5 are within reviewer variance.

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| SEC-1 | Resource attributes that take a local path upload a runner file at apply; neither layer checks them (`google_storage_bucket_object.source`, `aws_s3_object.source`, `aws_lambda_function` / `aws_lambda_layer_version.filename`). A merged change could upload `/proc/self/environ` with the apply identity. AWS's RCP may block a cross-organization write; GCP has no runner-side perimeter | `scripts/check-plan-time-exec.py` (file functions only), `policies/opa/no_plan_time_code_execution.rego` (no attribute rule) | VERIFIED from provider schemas and code (lead), not run; NEW |
| CMP-2 | A regulated AWS estate can run the log archive in GOVERNANCE mode: the refusal checks only `compliance.frameworks`. A regulated `pci` environment with no frameworks and `log_archive_object_lock_mode = "GOVERNANCE"` plans | `envs/aws/security/variables.tf:169-172` | VERIFIED (probe, lead read), NEW |
| CMP-1 | The AWS roots read `compliance_class` only from their own config file; pointing a workspace's `landing_zone_config_path` at another estate's file (which the OPA rule accepts) drops every regulated guard on aws-workload, aws-network and aws-security | `envs/aws/workload/config.tf:94-97`, `envs/aws/network/config.tf:83`, `envs/aws/security/config.tf:43` | VERIFIED (probe), KNOWN (the AWS remainder of re-audit 6 CMP-4) |
| CMP-3 | Waivers other than the GCP egress waiver have no maximum horizon; a shipped fixture waives the regulated WORM audit store to 2099; no waiver has an approver, a ticket or a register | `envs/gcp/organization/config.tf:192-199` | VERIFIED, KNOWN |
| CMP-4 | AWS backups ignore the regulated class: recovery points sit in unlocked member vaults on the AWS-managed key, and the weekly restore test selects a vault that receives nothing | `envs/aws/backup/config.tf:58`, control matrix BCK-01/02 | VERIFIED, KNOWN |
| IAC-1 | The GCP org audit sink's org-wide scope is never asserted: `include_children = false` on `org_audit_sink` passes all 39 tests, and every project's audit logs would stop reaching the WORM bucket | `modules/gcp/governance/cloud-audit-logs/main.tf:188-198`; tests assert it only on the analytics and network sinks | VERIFIED (mutant survived, lead confirmed), NEW |
| ADO-1 | No release a fork can pin: 69 breaking commits since `v0.1.0`; UPGRADING "Unreleased" spans lines 39 to 3635; the sandbox upgrade log is a template | `UPGRADING.md` | VERIFIED, KNOWN |

**Live-repository findings (all KNOWN, unchanged):** `main` protection is inert (no reviews, admins exempt, stale contexts; #599 merged with 6 failed checks) (CICD-1); no rulesets and unprotected or missing environments (CICD-2); GitHub security features off with 310 open code-scanning alerts (CICD-3).

**What held.** Every file-function bypass the security reviewer tried (escaped `..` segments, comments between name and parenthesis, split `templatestring` pieces); the IAM trust model on both clouds (no new finding in stage roles, WIF/OIDC pins, the AWS apply boundary, the RCP, CI secret scoping or `vault-secrets`); the firewall action change against the AWS documentation; the regulated GCP class carried in the contract (its mutant was killed); every re-audit 6 compliance fix, re-proven by probe.

## Tool results at `fe03d146`

| Check | Result |
|---|---|
| `python3 -P scripts/check-plan-time-exec.py` | 1,225 files, 0 problems |
| `opa test policies/opa` | 356/356 |
| Mutation test (12 mutants in previously unaudited security code) | 6 killed (50%) |
| Scaffold matrix (`config.tftest.hcl`, 15 roots) | All pass |
| zizmor 1.31.1, `check-tag-patterns.py`, `check-contracts.sh`, `check-consistency.sh` | Clean |
| GitHub CI on this branch | Never run (branch not pushed) |

## Industry readiness (compliance lens)

| Target | Verdict | Blocking items |
|---|---|---|
| Fintech PCI DSS v4.0.1 | Ready with work | CMP-1, CMP-2 and the ALB-log protection (CMP-5); GCP egress allowlist while the proxy is PREVIEW; no file integrity monitoring; MFA manual |
| HIPAA | Ready with work | AWS backup segregation and restore testing (CMP-4); BAAs; Supabase controls if it holds PHI |
| SOC 2 | Ready with work | Waiver governance and evidence that controls operated (CMP-3); CI unfunded |
| ISO 27001 | Ready with work | ISMS, risk register and waiver register |
| UK FCA/PRA-regulated firm | Ready with heavy work | No FCA/PRA crosswalk; CMP-4; DR untested; single region |
| EU public sector (GDPR/NIS2) | Ready with heavy work | No sovereign partitions; NIS2 incident timelines not codified; GDPR processor controls are the customer's |

PCI DSS moved from "heavy work" to "work" in this panel's view.

## Adopter verdicts (adoption lens)

| Adopter | Verdict | Why |
|---|---|---|
| Startup, GCP only | Feasible but heavy | About 22 manual actions, 2 to 3 days; use `--profile starter` and leave `prod` out until VPC-SC and egress are decided |
| Mid-size SaaS, AWS only | Feasible | About 27 actions, 1 to 2 weeks, about USD 1,400 to 1,900 per month idle plus HCP Standard |
| Regulated fintech, both clouds | Not turnkey | Unproven on real clouds, the ALB-log bucket gap (ADO-3), no pinnable release; a funded 6 to 10 week programme with a sandbox apply first |
| Platform team wanting a reference | Strong yes | Cross-cloud layering, policy-as-code and the regulated-class design are worth copying |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Estate | Estimate |
|---|---|
| AWS production, 1 region, 2 AZs, 1 spoke | About 1,750 to 2,150; each extra spoke account about 37 plus its security baseline; about 440 more with the VPN |
| AWS starter | About 850 to 1,000 (the sandbox budget is 300) |
| GCP | About 50 to 150 without the Secure Web Proxy; about 1,000 or more on the production default path (proxy) |
| HCP Terraform Standard | About 1,200 to 1,900 at an estimated 2,500 to 4,000 resources (unmeasured) |

The Route 53 Profile is billed to the owning account: about 548 per month in the network account in total, not per workload account. The cost row added in `fe03d146` says per account and overstates the bill (ARC-1).

## Genuinely strong

- The plan-time scanner fails closed, reads its lists from the OPA policy, and held against every file-function bypass this round.
- Plan and apply identities split on both clouds; WIF/OIDC tenant and workspace pins; the self-propagating AWS apply boundary; environment-scoped CI tokens.
- Symmetric AWS hub routing with per-segment firewall rules backing the TGW blackholes; the app-layer default matches AWS guidance.
- The GCP regulated class fails closed across organization, projects and workload, now through the contract too.
- 433 moved and removed blocks for state safety; one typed contract per producer, enforced by script.
- The scaffolder, committed fixtures under a `--check` gate and the 15-root scaffold plan matrix.

## Recommendation

**Fix now (small, mostly non-breaking):**

1. SEC-1 to SEC-3: add a curated list of path-reading resource attributes (`source`, `filename`, `source_path`, `files` keys) to both layers, requiring a literal path under `path.module`; refuse `data "tfe_slug"` (or pin its `source_path`) and `vercel_deployment.files` outside reviewed code.
2. CMP-1, CMP-2 and CMP-4: refuse GOVERNANCE mode when any AWS workload environment is regulated; publish `compliance_class` per account in the aws-organization contract and OR it into the AWS roots (as on GCP); force `copy_to_central_vault` when an environment is regulated.
3. IAC-1 to IAC-5: assert the org audit sink's `include_children`, filter and destination; add `expect_failures` runs for the WIF issuer guards; assert deny-policy `exception_permissions`, the CIS metric-filter event names and every managed org-policy name.
4. Documentation: the exact config-path form (`../../../config/<estate>/landing-zone.yaml`) in the docs and the 15 root error messages (ADO-2); Python 3.11 or newer for `python3 -P` (ADO-4); the Route 53 Profile cost row (ARC-1); the `_to_server` UDP and ICMP caveat (ARC-6); the regulated ALB-log bucket (ADO-3).
5. CICD-4: make the scanner's callers (`check-consistency.sh`, `terraform-plan.yml`) security-owned, and honour `PLAN_EXEC_*` only under a test flag.

**Then, as the last six reports said:** turn the freeze on, push and merge the branch, fund one sandbox apply per cloud, cut v0.2.0 with a recorded upgrade, and take the Phase 3 owner steps (rulesets, environments, scanning, real CODEOWNERS teams, a second maintainer, a green `main`).

## Appendix: Medium and Low findings

**Security.** SEC-2 `data "tfe_slug"` packs any runner directory at plan and `tfe_policy_set` can upload it (VERIFIED by schema, NEW). SEC-3 `vercel_deployment.files` keys are local paths the provider uploads (VERIFIED by schema, exploitability unconfirmed, NEW). Low: SEC-4 WIF binding falls back to the workspace name, and only warns for production (KNOWN); SEC-5 CODEOWNERS teams are placeholders (KNOWN).

**Compliance.** CMP-5 the regulated ALB access-log bucket can be any bucket, not a locked 365-day store (NEW). CMP-6 Supabase has no SSL enforcement, network restriction or PITR management, and a regulated AWS workload can enable the SaaS bridge (KNOWN). Low: CMP-7 the crosswalk PCI 6.4.x and 10.2/10.3 rows and review date are stale (NEW); CMP-8 gcp-network-hub parses `compliance_class` but uses it for nothing (NEW).

**Architecture.** ARC-1 the Route 53 Profile cost row bills per workload account; AWS bills the owner account (NEW). ARC-2 the starter sandbox idles at about 3 times its budget (KNOWN). ARC-3 waivers give no warning before expiry; the AWS egress waiver has no expiry (KNOWN). ARC-4 the Aurora reboot step has no runbook or detection; no `allow_major_version_upgrade` (KNOWN in part). Low: ARC-5 the gate accepts `aws:drop_strict`, which drops the handshake before the allowlist (NEW); ARC-6 `_to_server` also drops UDP and ICMP in both directions, so PMTUD and external NTP or DNS need pass rules (NEW); ARC-7 the active threat defense group's per-GB surcharge and data-sharing default are undocumented (SUSPECTED, NEW). Still open: the hub trusts the configured spoke CIDR; single region; spoke onboarding needs several runs; one Secure Web Proxy allowlist; firewall rule groups cannot be replaced in place.

**Terraform craft.** IAC-2 the WIF GitLab and AWS issuer guards are untested (NEW). IAC-3 deny-policy `exception_permissions` is unasserted (NEW). IAC-4 the CIS metric-filter patterns are checked for structure only; removing `StopLogging` passes (NEW). IAC-5 the managed org-policy names are not asserted per entry (NEW). IAC-6 the AWS regulated class via the config path (KNOWN, see CMP-1). Low: IAC-7 VPC-SC `vpc_accessible_services` unasserted (NEW); IAC-8 a stale checkov skip and no enum on GCP KMS `purpose` (NEW); IAC-9 `compliance_class_guard` creates a resource for `standard` too, not in UPGRADING (NEW); IAC-10 Vercel `nonsensitive()` maps (KNOWN); IAC-11 aws-organization is never planned against its real stage (KNOWN).

**Delivery.** CICD-4 the security-only scanner's callers (`check-consistency.sh`, `terraform-plan.yml`) are platform-approvable and the scanner honours `PLAN_EXEC_ROOT`, `PLAN_EXEC_POLICY_DIR` and `PYTHONPATH`, so a platform-only change could repoint or remove it (SUSPECTED, NEW in part). CICD-5 Renovate not installed (KNOWN). CICD-6 breaking-change discipline: 69 of 245 commits, a gate that checks only the diff (KNOWN). CICD-7 the work exists only on one disk (KNOWN). Low: CICD-8 `pre-commit/action` installs pre-commit unpinned (NEW), other weak pins (KNOWN); CICD-9 `BRANCH_PROTECTION.md` secret table and security-path list are stale (NEW); CICD-10 tag parsing accepts `aws-workload/v1` and does not encode tag segments in the API URL (NEW). OpenSSF Scorecard estimate: about 4.5 live, 7.5 with governance in force.

**Adoption and documentation.** ADO-2 the config-path form in the docs and root error messages is not the form the policy accepts (NEW). ADO-3 the regulated ALB-log bucket has no config key, creator or guidance (NEW). ADO-4 `python3 -P` needs Python 3.11 or newer, undocumented (NEW). ADO-5 to ADO-8 `make install` on PEP 668 Python, the fork-owned paths, no `terraform login` step, runbook inputs that are not root variables (KNOWN, still open). ADO-9 contradictory Option A credential instructions in the AWS bootstrap runbook (NEW). Low: ADO-10, ADO-11 KNOWN; ADO-12 to ADO-14 the GitHub WIF claim, the Aurora reboot step without a command, an ambiguous project placeholder (NEW).
