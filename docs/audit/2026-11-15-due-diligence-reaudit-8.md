# Eighth due-diligence re-audit (2026-11-15)

Six new independent reviewers read the code at commit `4479cabc` (branch `claude/enterprise-devops-audit-949b65`, not merged and not pushed). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md) and re-audits [1](2026-11-12-due-diligence-reaudit.md) to [7](2026-11-15-due-diligence-reaudit-7.md), read the code first, and read earlier reports only to label findings NEW or KNOWN. The lead re-checked every NEW High in the code. The shared brief now forbids building or running anything that reads or uploads real runner secrets: every bypass below was shown on inert fixtures, from provider schemas or by reading the code.

This round follows the fixes for re-audit 7's "Fix now" list (commit `4479cabc`). One adversarial review ran on those fixes before the commit and found more upload arguments and an aws-security gap, which the same commit closed.

## Verdict

**Overall: 6.7 / 10. Unchanged from re-audit 7 (the highest score so far). No Critical finding in the code.**

Design (7.0) and operability (6.2) rose. The panel found that three of the re-audit 7 fixes do not hold on the paths that matter:

1. **The regulated central backup copy cannot copy the data it exists for (ARC-1).** The commit made the copy mandatory for regulated AWS estates, but the workload CMK that encrypts Aurora and EBS has no key-policy statement for the backup account. AWS Backup needs one to copy those recovery points across accounts, so every copy job would fail, silently by default, after the estate has paid for an irreversible vault lock.
2. **The AWS regulated class is still removable (CMP-1 to CMP-3, IAC-2).** Supplying `organization_contract` as a workspace variable turns the aws-organization remote-state read off, and the regulated keys with it. Where the contract does apply, aws-network's refusals and aws-security's retention floor still read only the root's own config file.
3. **The security-only scanner can be disarmed in CI (CICD-1, SEC-2).** In the meta-lint job a platform-owned script runs before the scanner and can set `PLAN_EXEC_TEST` and an empty root, rewrite the scanner on disk, or pre-install a fake parser. The delivery reviewer reproduced the effect on inert fixtures (0 files parsed, rc 0).
4. **An allowlisted provider nobody uses is unchecked (SEC-1).** `azurerm` is on the provider allowlist for a commented example only; none of its credential, endpoint or upload arguments is checked, so it passes both layers.

The usual: nothing is proven on a real cloud, live settings score 2/10, and 70 breaking commits are unreleased.

## Scorecard

| Lens | 2026-11-11 | Forecast | RA 1 | RA 2 | RA 3 | RA 4 | RA 5 | RA 6 | RA 7 | RA 8 | Change |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | 5.5 | 7.5 | 6.0 | 6.2 | 7.0 | 7.0 | 0.0 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 6.0 | 5.8 | 6.0 | 6.4 | 6.5 | 6.6 | +0.1 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | 6.0 | 5.5 | 6.8 | 6.8 | 6.9 | 7.0 | +0.1 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | 4.5 | 5.5 | 5.8 | 5.6 | 5.8 | 6.2 | +0.4 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | 7.0 | 7.4 | 6.8 | 7.2 | 6.9 | 6.6 | -0.3 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | 5.5 | 7.0 | 7.0 | 7.6 | 7.5 | 6.8 | -0.7 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | 4.5 | 4.5 | 4.5 | 4.5 | 6.0 | 6.0 | 0.0 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | 8.0 | 7.5 | 8.0 | 7.0 | 7.0 | 7.0 | 0.0 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **5.9** | **6.3** | **6.4** | **6.4** | **6.7** | **6.7** | **0.0** |

Delivery is scored on the branch's code; live settings score 2/10. Terraform craft reflects a mutation test on 27 mutants in 17 modules not covered by the last two tests (59% killed).

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| ARC-1 | The mandatory regulated central backup copy cannot copy Aurora or EBS: the workload CMK (the account's default EBS key and the Aurora key) has no statement for the backup account; AWS Backup requires the source key to be shared for these services; `copy_vault_notification_topic_arn` is off by default | `envs/aws/workload/kms.tf:39-115` (Sids: AccountRootAdmin, CloudWatchLogsThisAccount, CloudWatchAlarmsToEncryptedTopic, EcrThisAccount, AppTaskExecutionRolesDecrypt), `envs/aws/backup/main.tf:119-129` | VERIFIED in code and AWS docs (lead read the key policy), NEW |
| CMP-3 / IAC-2 | A supplied `organization_contract` (workspace variable or `aws.contracts.organization`) turns the aws-organization remote-state read off, so `regulated_account_keys` is empty and every AWS regulated guard goes quiet; `try(..., [])` also fails open on an older producer state | `envs/aws/{workload,network,security,backup}/main.tf` (`read_organization = local.organization_contract == null`) | VERIFIED (two reviewers' probes), NEW for AWS (KNOWN on GCP) |
| CMP-1 | aws-network accepts `enable_network_firewall = false`, `enforce_egress_allowlist = false` or `egress_alert_only_waived = true` when only the contract marks the estate regulated: the refusals read only the config file | `envs/aws/network/variables.tf:227,335,389`, `config.tf:124,130` | VERIFIED (probe), NEW |
| CMP-2 | aws-security accepts a log-archive retention below 365 days when only the contract marks the estate regulated; the new precondition checks lock mode only | `envs/aws/security/variables.tf:160`, `main.tf:154-164` | VERIFIED (probe), NEW |
| CICD-1 / SEC-2 | The security-only scanner runs after a platform-owned script in the same CI job; that script can set `PLAN_EXEC_TEST=1` and an empty `PLAN_EXEC_ROOT` through `$GITHUB_ENV`, shadow `python3` through `$GITHUB_PATH`, rewrite the scanner or policies, or pre-install a fake `hcl2` | `.github/workflows/terraform-plan.yml` (meta-lint: `check-module-api.sh` before "Consistency guards"), `scripts/check-plan-time-exec.py:109-121` | VERIFIED (inert reproduction: 0 files parsed, rc 0), NEW vector |
| SEC-1 | `azurerm` is an allowlisted provider (for a commented example only); its credential arguments (`client_secret`, `client_certificate_path`, `oidc_token_file_path`), `oidc_request_url` and upload arguments (`azurerm_storage_blob.source`) pass both layers | `policies/opa/no_plan_time_code_execution_allowlist.rego:16`, `templates/shared/cloud-root/providers.tf:13` | VERIFIED (inert fixture, lead read the allowlist), NEW |
| IAC-1 | Mutation survivors in org-wide detective controls and secret exposure: Security Hub central policy `service_enabled = false`, Config recorders `is_enabled = false`, `tfe_variable.sensitive = false`, Vercel production variables targeted at preview builds, the regulated log-archive lock precondition removed; every one passes its suite | `modules/aws/security/securityhub-org`, `config-org`, `modules/tfc/workspace`, `modules/vercel/project`, `envs/aws/security` | VERIFIED (mutation test), NEW |
| CMP-4 | Waiver governance: only the GCP egress waiver has a horizon; `audit_store_waiver` (a fixture waives the regulated WORM store to 2099), `egress_alert_only_waived` and `production_containment_waived` have none; no approver, ticket or register | `envs/gcp/organization/config.tf:192-199` | VERIFIED, KNOWN |
| ARC-6 | Single region on both clouds; `dr_region` copies backups but there is no network to restore into | | KNOWN |

**Live-repository findings (all KNOWN, unchanged):** inert `main` protection, no rulesets, unprotected or missing environments, GitHub security features off (private vulnerability reporting off, so SECURITY.md's only reporting channel does not work), no secrets, red `main`.

**What held.** The path-reading attribute rules against the cached schemas of every provider the repo uses; the PLAN_EXEC_TEST gating and PYTHONPATH refusal when nothing earlier in the job tampers with them; the AWS packet paths and the `_to_server` default against AWS documentation; the regulated class on its own config path (GOVERNANCE refused, central copy required, workload guard follows the contract); the config-path form across 20+ places; the Route 53 Profile cost row; 16 of 27 new mutants.

## Tool results at `4479cabc`

| Check | Result |
|---|---|
| `python3 -P scripts/check-plan-time-exec.py` | 1,225 files, 0 problems |
| `opa test policies/opa` | 364/364 |
| Mutation test (27 mutants, 17 modules or roots) | 16 killed (59%) |
| check-consistency, check-contracts, check-config, check-backends, fmt, validate (9 sampled) | Clean |
| `make links` | 1,706 links, 0 broken |
| GitHub CI on this branch | Never run (branch not pushed) |

## Industry readiness (compliance lens)

| Target | Verdict | Blocking items |
|---|---|---|
| Fintech PCI DSS v4.0.1 | Ready with work | CMP-1 to CMP-3; ARC-1; the ALB log bucket can be any bucket; GCP egress allowlist while the proxy is PREVIEW; no file integrity monitoring |
| HIPAA | Ready with work | ARC-1 (backup copy); BAAs; Supabase controls if it holds PHI |
| SOC 2 | Ready with work | CMP-4 (waivers); evidence that controls operated; CI unfunded |
| ISO 27001 | Ready with work | ISMS, risk and waiver register |
| UK FCA/PRA-regulated firm | Ready with heavy work | No FCA/PRA crosswalk; DR untested; single region; CMP-3 |
| EU public sector (GDPR/NIS2) | Ready with heavy work | No sovereign partitions; NIS2 timelines not codified |

## Adopter verdicts (adoption lens)

| Adopter | Verdict | Why |
|---|---|---|
| Startup, GCP only | Adoptable with help | About 22 manual actions, 2 to 3 days; `make install`, `terraform login` and the production egress choice need workarounds |
| Mid-size SaaS, AWS only | Adoptable with a platform engineer | About 28 actions, 1 to 2 weeks; budget the always-on firewall and Route 53 Profile and the irreversible backup lock |
| Regulated fintech, both clouds | Not turnkey | The regulated page is stale for AWS, the ALB log bucket is hand-built, no pinnable release, nothing proven on a real cloud |
| Platform team wanting a reference | Strong yes | Module library, cross-cloud mapping, guard design and runbooks |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Estate | Estimate |
|---|---|
| AWS production, 2 AZs, before workloads | About 1,550 to 1,850; about 438 more with the VPN; about 80 to 150 per golden-path environment |
| AWS starter | About 950 to 1,100 (the always-on Route 53 Profile is about half) |
| GCP | About 50 to 200; about 900 more per Secure Web Proxy gateway |
| HCP Terraform Standard | About 950 to 1,900 for an estimated 2,000 to 4,000 resources (unmeasured) |

## Genuinely strong

- The plan-time gates: one source of truth, deny-by-default ephemeral and action blocks, credential reference pinning, path-reading attributes, fail-closed parsing.
- IAM on both clouds: the AWS plan-role data-read deny and apply boundary, SCPs pinning federation, the GCP plan viewer without data-plane permissions, the guardrails split.
- TGW defence in depth (blackholes, segment pass rules, a plan failure for a spoke without a CIDR) and correct firewall rule order.
- The organization-policy SCP/RCP suite (68 runs, every mutant killed); write-only secrets throughout.
- One config file with schema, scaffolder and per-combination plan matrix; guards that name the config key to fix.

## Recommendation

**Fix now:**

1. ARC-1: when the central copy or `dr_region` is on, add a key-policy statement to the workload CMK for the backup account and `backup.amazonaws.com`; make the copy-vault notification topic mandatory for a regulated estate.
2. CMP-1 to CMP-3 and IAC-2: read `regulated_account_keys` from aws-organization state even when a contract is supplied (or carry it in the contract variable and fail closed when absent); apply it to aws-network's three refusals and aws-security's retention floor; add a contract-driven test to each root.
3. CICD-1 / SEC-2: run the scanner (and OPA tests) in their own job, from a fresh checkout, before any other repo script, with an absolute interpreter and a clean environment; refuse `PLAN_EXEC_TEST` when `CI=true`; fail when 0 files are parsed.
4. SEC-1: remove `azurerm` from `allowed_provider_sources` (a fork adds it in a reviewed change), and add a test that fails when an allowlisted provider has no schema-review entry.
5. IAC-1 and documentation: assert Security Hub `service_enabled`, Config `is_enabled`, `tfe_variable.sensitive`, the Vercel targets and the aws-security lock precondition; correct `regulated-environments.md` for the AWS backup and audit-store guards (ADO-1) and carry the `_to_server` UDP/ICMP caveat into the example config and the regulated page (ADO-5).

**Then, as the last seven reports said:** turn the freeze on, push and merge the branch, fund one sandbox apply per cloud, cut v0.2.0 with a recorded upgrade, and take the Phase 3 owner steps.

**A process note.** For three rounds the fix-now list has included a bypass of the previous round's fix, found by the next independent panel even after a pre-commit adversarial review. The repository has reached the point where each round of code fixes buys less than the steps the reports keep deferring: a sandbox apply would settle ARC-1 and the firewall questions, and running the scanner as an isolated job or an HCP pre-plan run task would end the in-job tampering class.

## Appendix: Medium and Low findings

**Security.** SEC-3 PR speculative plans and CLI uploads on control-plane workspaces skip the scanner (KNOWN). SEC-4 an AWS provider can `assume_role` into a foreign account; no `allowed_account_ids` requirement and no identity-side `aws:ResourceOrgID` SCP (NEW in part). Low: SEC-5 a `path.module` path into `.terraform/` passes (NEW); SEC-6 `data "tfe_outputs"` / `tfe_variables` workspace not pinned (NEW); SEC-7 CODEOWNERS placeholders and bootstrap-apply's org `securityAdmin` (KNOWN).

**Compliance.** CMP-5 the regulated ALB log bucket can be any bucket (KNOWN). CMP-6 aws-backup can turn the copy on while aws-organization never created the `-cmk` member vault (SUSPECTED, NEW). CMP-7 restore testing is not evidenced; the notification topic is off (SUSPECTED). Low: CMP-8 crosswalk HIPAA and DORA backup rows and NET-11 stale (NEW); CMP-9 Glacier transition at day 90 is on the edge of PCI's "3 months immediately available" (NEW).

**Architecture.** ARC-2 the DNS Firewall blocks only `malware.example.` by default and spoke DNS queries are not logged (NEW). ARC-3 a BGP VPN with empty `vpn.onprem_cidrs` makes a fail-closed firewall drop all hybrid traffic; only a warning, only with Resolver endpoints (NEW). ARC-4 turning the central copy on is an ordering hazard between aws-organization and aws-backup (SUSPECTED, NEW). ARC-5 waiver cliffs with no warning; the AWS egress waiver has no expiry (KNOWN, worse). ARC-7 UPGRADING.md 3,715 lines (KNOWN). Low: ARC-8 Aurora reboot not detected (KNOWN); ARC-9 starter pays for an idle inspection attachment (NEW); ARC-10 PSC DNS maps only `googleapis.com` (SUSPECTED, NEW); ARC-11 cost tables partial and one stale "nothing is copied" line (KNOWN in part).

**Terraform craft.** IAC-3 the aws-security lock precondition and the contract paths in aws-network and aws-backup have no tests (NEW). IAC-4 secret-manager's guard does not protect individual secrets; the native per-secret `deletion_protection` is unused (NEW). IAC-5 cloud-sql replace guard, identity-center inline policies, secret replica CMEK and Supabase `disable_signup` untested (NEW). IAC-6 thin plan suites on several security modules (NEW). IAC-7 aws-organization never planned against its real stage (KNOWN). Low: IAC-8 identity-center session duration validation accepts `PT0H` (NEW); IAC-9 `tfe_notification_configuration.token` in state despite `token_wo` (NEW); IAC-10 Vercel `allowed_branches` unescaped in `ignore_command` (NEW); IAC-11 Vercel `nonsensitive()` maps (KNOWN).

**Delivery.** CICD-2 a new workflow with a job named `Validation Summary` may satisfy the required check (SUSPECTED, NEW). CICD-3 live settings inert (KNOWN). CICD-4 Renovate not installed; `enabledManagers` omits pre-commit (NEW part); Dependabot has no cooldown (KNOWN). CICD-5 breaking-change gate checks only the diff (KNOWN). CICD-6 `v0.1.0` is a lightweight, unsigned tag with no `v*` ruleset (KNOWN). Low: CICD-7 `BRANCH_PROTECTION.md` secret table stale, `GITLEAKS_LICENSE` undocumented, drift workflow says "repository secret" (NEW); CICD-8 the drift summary job never fails (NEW); CICD-9 checkov-action pin comment mismatch, image tag-pinned (NEW); CICD-10 no pre-merge secret scan (KNOWN). OpenSSF Scorecard estimate: about 4.5 live, 7.3 with governance applied.

**Adoption and documentation.** ADO-1 `regulated-environments.md` says "No change" for AWS backups and the audit store and omits aws-backup (NEW). ADO-2 `make install` fails on stock macOS (3.9 system Python fails the new check; Homebrew Python is PEP 668) (KNOWN). ADO-3 the scaffolder's production checklist omits the GCP egress decision; the scaffold matrix plans only `dev` (KNOWN). ADO-4 no `terraform login` step (KNOWN). ADO-5 the `_to_server` UDP/ICMP caveat is not in the example config or the regulated page (NEW). Low: ADO-6 to ADO-11 KNOWN (fork-owned paths, ALB log bucket creator, bootstrap runbook variables, Option A instructions, "schema" wording, three QUICK_START claims); ADO-12 the scaffolder's idle-cost figure has no source (SUSPECTED, NEW); ADO-13 CONTRIBUTING omits Python 3.11 (NEW).
