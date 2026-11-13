# Third due-diligence re-audit (2026-11-13)

Six new independent reviewers read the code at commit `afee9f71` (branch `claude/enterprise-devops-audit-949b65`, not merged). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md), the [first re-audit](2026-11-12-due-diligence-reaudit.md) and the [second re-audit](2026-11-13-due-diligence-reaudit-2.md). They read the code first and the earlier reports only at the end, to label each finding NEW or KNOWN. The lead re-checked every Critical in the code.

This round follows the code wave from re-audit 2, the examples audits (top-level `examples/` and all 126 module examples) and three module bugs those audits exposed.

## Verdict

**Overall: 5.9 / 10. Up from 5.7 at re-audit 2, still 1.3 below the Phase 2 forecast of 7.2.**

The code is measurably better. Every module example now plans under mock providers, three hidden module bugs are gone, documentation accuracy is at its highest so far (8.0), and system design rose to 6.0. The score barely moves because:

1. **The plan-time code-execution guard has two proven bypasses (Critical).** An AWS provider `profile` with a `credential_process` in a committed config file, and `ephemeral` blocks, run code or reach a foreign tenant while both the OPA policy and the CI scanner report zero problems. This is the control the repo leans on most.
2. **The work keeps adding breaking changes.** 65 breaking commits since `v0.1.0` (57 at re-audit 2). The freeze that re-audit 2 recommended was planned but not turned on. One fix in this range introduced a new production bug (two-digit GCP regions).
3. **Nothing is proven on a real cloud, and governance is unchanged.** No enforced review on `main`, CI on `main` red, bus factor 1. The gate added in the last commit (`examples-plan` in CI) is fail-open.

## Scorecard

| Lens | 2026-11-11 | Forecast | Re-audit 1 | Re-audit 2 | Re-audit 3 | Change from re-audit 2 |
|---|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | 5.5 | 0.0 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 6.0 | 0.0 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | 6.0 | +0.5 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | 4.5 | 0.0 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | 7.0 | 0.0 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | 5.5 | +1.0 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | 4.5 | -0.5 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | 8.0 | +0.5 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **5.9** | **+0.2** |

Delivery is scored on the branch's code; the reviewer scores the live repository settings 3/10. Panel-to-panel differences of about 0.5 are within reviewer variance.

## Critical findings (lead-verified)

| ID | Finding | Lead verdict | Status |
|---|---|---|---|
| SEC-1 | AWS `profile` plus `shared_config_files` with `credential_process` runs a command at plan and apply; OPA and the CI scanner both pass it | CONFIRMED in code; reviewer reproduced it locally | KNOWN as a doc gap, severity raised |
| SEC-2 | `ephemeral` blocks are absent from the plan JSON, and the scanner's code-execution type list applies only to `data`; `ephemeral "aws_lambda_invocation"` and token-minting ephemerals pass both layers | CONFIRMED in code; reviewer reproduced it locally | NEW |

**SEC-1.** `endpoint_key_pattern` in `policies/opa/no_plan_time_code_execution.rego` (lead-checked) lists endpoint, proxy and credential keys but not `profile`, `shared_config_files`, `shared_credentials_files`, `access_key`, `secret_key`, `token`, `assume_role*`, `web_identity_token_file` or google `impersonate_service_account`. The reviewer committed an `aws.cfg` with a `credential_process`, set the provider's `profile` and `shared_config_files`, and `terraform plan` ran the command; `opa eval` returned `[]` and `scripts/check-plan-time-exec.py` reported 0 problems. At apply this runs on the HCP runner next to the apply-phase web-identity token. Fix: deny `profile` always, deny `shared_config_files`/`shared_credentials_files` unless their only reference is `var.tfc_aws_dynamic_credentials` (the two roots that use them), deny inline AWS static keys, and mirror every rule in the scanner.

**SEC-2.** In `scripts/check-plan-time-exec.py` (lead-checked) the code-execution check is `kind == "data" and rtype in pol["exec_data_types"]`, so the same types as `ephemeral` blocks pass; the provider allowlist still admits them because they use `aws` and `google`. Ephemeral blocks do not appear in `terraform show -json`, so OPA cannot see them at all. aws 6.x has ephemeral `aws_lambda_invocation`; google 8.x has ephemeral `google_client_config` (with `access_token`) and `google_service_account_access_token`. Fix: an `ephemeral` type allowlist in the scanner, and run the scanner as an HCP Terraform pre-plan run task on every configuration version (VCS and CLI uploads), not only in GitHub CI.

**Not Critical this round:** CICD-3 (no enforced review on `main`), rated Critical by earlier panels, is rated High by this panel. It is unchanged and still blocks a buyer; see [High findings](#high-findings).

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| IAC-1 | Zone validations accept one region digit only, so a production estate in `europe-west10`/`-12` has no zone list that plans; app-ingress region regex has the same defect | `modules/gcp/stages/{net-hub,net-spoke}/variables.tf:110`, `dns-anchor/variables.tf:77`, `modules/gcp/network/app-ingress/variables.tf:16` (lead-checked) | VERIFIED, NEW (introduced by the zone-pinning fix) |
| CICD-1 | The new `examples-plan` CI step is fail-open: `if ! script \| tee log` runs under `bash -e` without `pipefail` | `.github/workflows/terraform-plan.yml:333`; no `shell:` or `defaults` (lead-checked) | VERIFIED, NEW |
| CICD-2 | Release provenance is dead code: the run is fetched with `include=configuration_version`, so `ingress-attributes` is never present, `run_commit` is empty and `commit_match` is always true | `.github/workflows/terraform-apply.yml:158,205-209` | VERIFIED (API detail SUSPECTED), root cause NEW |
| SEC-3 | Phase-0 `tfc-mgmt-apply` is unbounded `AdministratorAccess` in the payer account | `templates/aws/bootstrap/phase0-management.yaml` | KNOWN |
| SEC-4 | `organization-apply` holds unconditional org `folderIamAdmin` and `orgpolicy.policyAdmin` | `modules/gcp/stages/bootstrap/service_accounts.tf` | KNOWN |
| ARC-1 | Production AWS firewall (`drop_established` with a generated allowlist of `$HOME_NET -> $EXTERNAL_NET` rules) likely drops spoke traffic to the central endpoints, east-west and hybrid traffic | `modules/aws/network/network-firewall/main.tf`, `network-hub` `production_egress_enforced` | SUSPECTED, KNOWN in part, severity raised |
| ARC-2 | AWS address space holds about 62 workload VPCs; tier `newbits` is fixed at 8, so roots cannot size VPCs down | `modules/aws/stages/workload/variables.tf:117-121` | VERIFIED, KNOWN ceiling, newbits NEW |
| ARC-3 | Private Service Access is a Google-chosen /16 per VPC, exported over NCC by default and unpinnable | `net-spoke/main.tf:203-211` | KNOWN |
| ARC-4 | Every environment defaults the GKE control plane to `172.16.0.0/28` (inside the on-premises range); secondary ranges unset lets GKE pick ranges outside the plan, and the plan does not fail | `envs/gcp/workload/variables.tf:671-675` | KNOWN, severity raised |
| ARC-5 / IAC-2 / ADO-2 | 65 breaking commits since `v0.1.0`; UPGRADING.md is 3,512 lines with 156 Unreleased entries; the freeze is not in force | `git log v0.1.0..HEAD` | KNOWN, worse |
| CMP-N1 | Hub VPC flow logs sample 50 %, are not exported and keep 30 days, regulated estates included; SECURITY.md overclaims | `modules/gcp/stages/network-hub/main.tf:99-102` | VERIFIED, NEW |
| CMP-N2 | `compliance_class: regulated` has no effect on AWS workload, backup, identity or SaaS roots | no references in those roots | VERIFIED, NEW |
| CMP-R1 / R5 | Regulated GCP flow logs in a workload-administered dataset; waivers with no maximum horizon or approver | `net-spoke/main.tf:340-383`; `envs/gcp/workload/variables.tf:347-380` | KNOWN |
| CICD-3 to CICD-6 | No enforced review; unprotected environments; secret scanning and private reporting off; four-eyes by team, one-person override, CODEOWNERS placeholders (71 errors) | live `gh api` | KNOWN |
| ADO-1 | A production GCP scaffold's `gcp-workload-prod` fails on the VPC-SC and egress guards; the scaffolder does not list them | `scripts/init-landing-zone.sh` | VERIFIED, scaffolder gap NEW |
| ADO-3 / ADO-4 | No real-cloud proof; bus factor 1, 83 % AI co-authored | known-gaps, `git log` | KNOWN |

## Tool results at `afee9f71`

| Gate | Result |
|---|---|
| `terraform fmt -check -recursive` | Pass |
| tflint, 15 roots and 8 modules | 0 issues |
| checkov 3.3.17, modules / envs | 1,452 / 872 passed, 0 failed; 4 parse errors still unscanned |
| trivy 0.70.0, CI flags | 0 Critical or High |
| `opa test policies/` | 505 / 505 |
| zizmor 1.31.1 offline | 0 findings |
| `make examples-plan` (sample of 15) | 15 / 15 |
| `make count-check`, `make links` | Pass (126 modules, 15 roots, 353 suites; 1,682 links) |

## Industry readiness (compliance lens)

Unchanged from re-audit 2: Ready with work for startup SOC 2, retail and media, AI/ML, HIPAA and GDPR; Ready with heavy work for PCI DSS; Not supported for banking (DORA, FCA/PRA, SOX ITGC), US public sector and EU sovereignty. New blockers named this round: hub flow-log retention (PCI), the regulated class not reaching AWS backups (HIPAA, DORA), and no backup or restore-test evidence on either cloud (SOC 2 A1.3, DORA Art. 12).

## Adopter verdicts (adoption lens)

| Persona | Verdict | Manual steps | First governed estate |
|---|---|---|---|
| Startup (SaaS + small AWS, SOC 2) | Adopt with work; SaaS path first | About 28 | SaaS 1 to 2 days; AWS 2 to 3 weeks |
| Fintech, AWS only | Adopt with work; fork pinned, sandbox first | About 26 | 3 to 5 weeks |
| Enterprise, GCP + AWS, 50 teams | Do not adopt as the foundation | About 38, plus an override per new environment | 6 to 10 weeks |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Profile | Estimate |
|---|---|
| Production, both clouds | 2,800 to 4,400, plus HCP Terraform |
| Starter, both clouds | 700 to 1,200, plus HCP Terraform |

The GCP cost table in the repo omits the Secure Web Proxy (about USD 900 per month per gateway), which production needs unless waived (ARC-10).

## Genuinely strong

- Every module example plans under mock providers, and two lasting checks (unknown nested attributes, README example links) back it.
- Module APIs: 2,322 typed and described inputs, 1,466 validations, typed cross-root contracts, 107 `moved` blocks.
- GCP plan and apply identities are split per workspace and run phase; plan identities read metadata only.
- The AWS apply boundary, the RCP data perimeter on by default, KMS policies with no root delegation, and a security-team-only guardrails workspace.
- Workflows: SHA-pinned actions, least-privilege tokens, egress blocked on every credential-holding job.
- Documentation accuracy at 8.0: 60+ claims checked, 7 false, all Low or Medium.

## Recommendation

The pattern from re-audit 2 holds: code-only rounds close their findings and the next panel finds a new class. This round's two Criticals and the fail-open gate are cheap and must be fixed first. After that, the score is limited by things outside the code.

**Fix now (small, high value, non-breaking where possible):**

1. SEC-1 and SEC-2: extend `endpoint_key_pattern` and the scanner (profile, shared config files, AWS static keys, assume-role keys, google impersonation; an `ephemeral` type allowlist), with tests for each bypass.
2. CICD-1: `shell: bash` (pipefail) on the `examples-plan` step, and a test that a failing example fails the job.
3. IAC-1: `[0-9]+` in the four region and zone regexes, a two-digit-region test in each suite, and a consistency check against `[0-9]-` / `[0-9]$` in GCP region patterns.
4. CICD-2: `include=configuration_version.ingress_attributes` and fail closed with no commit.

**Then change approach, as re-audit 2 said:** turn the freeze on (`docs/moai/plans/2026-11-13-freeze-and-v0-2-0.md` Part A), fund one sandbox apply per cloud (it settles ARC-1, ARC-3, ARC-4 and the contract-value class IAC-3 exposed), and take the Phase 3 owner steps.

## Appendix: Medium and Low findings

**Security.** SEC-5 org `securityAdmin` grantable list includes `cryptoKeyEncrypterDecrypter` and `storage.objectCreator` with no resource scope. SEC-6 the preventive layer depends on unfunded GitHub CI; OPA's provisioner chain matches names only. SEC-7 app-deploy WIF binds the GitHub environment without a ref. SEC-8 platform team `runs = plan` on control-plane projects. SEC-9 hub VPC-SC automation ingress `access_level = "*"`. SEC-10 `endpoint_key_pattern` gaps (folded into SEC-1's fix). Off by default and not defensible for regulated buyers: principal access boundary, Config recorder SCP, policy sets below the Standard tier, optional WIF organization/project pins.

**Compliance.** N3 SECURITY.md claims a Trivy filesystem dependency scan that does not exist. N4 no backup or restore-test evidence on either cloud. R8 Aurora TLS. R2 CloudFront TLS floor unreachable. R17 `global` log buckets. R13 noncurrent versions never expire. CMP-08 frameworks set floors in two places only. R6 GCP patching overclaim. R14 starter drops Macie and Security Lake. R3 standing AWS admin. Low: N5 HIPAA "reasonable diligence" wording; N6 no Access Approval, Access Transparency, KAJ or EKM; R7 missing UK and US notification regimes; R10 no GCP asset inventory export; thin Supabase controls.

**Architecture.** ARC-6 Cloud Run and GKE share one zonal /24. ARC-7 onboarding runs 4 to 6 control-plane roots with manual hand-offs and an override each time. ARC-8 GCP single region on the production path. ARC-9 segment isolation still a check. ARC-10 GCP cost table omits the Secure Web Proxy, Data Access logs, HA Cloud SQL and the backup vault. Low: ARC-11 stale network-topology.md; ARC-12 no IPv6; ARC-13 AZ names by default; ARC-14 default `internal_domain` is `internal.local` (reserved for mDNS).

**Terraform craft.** IAC-3 37 of 286 `override_module` blocks carry outputs the real module no longer has; contract fixtures are hand-written, which is how the `gcp-projects` folder-ID bug hid for eight days. IAC-4 AWS name validations accept trailing or doubled hyphens that the API rejects mid-apply. IAC-5 a supplied single-region EBS key is set as the default in every enabled region (SUSPECTED). IAC-6 `envs/tfc-admin/main.tf` is 1,743 lines. Low: IAC-7 checkov parse errors; IAC-8 service-team key rules differ between layers; IAC-9 assertions that pass by construction under mocks; IAC-10 lockfiles in leaf modules.

**Delivery.** CICD-7 `destroy_guard` does not cover detective controls (log sinks, SCC notifications, GuardDuty, Security Hub, Config recorder, Security Lake, log groups). CICD-8 mutable unsigned `v*` tags, no SBOM or provenance. CICD-9 wildcard egress allowlists; app-delivery harden-runner in audit mode with `id-token: write`. CICD-10 app-delivery examples are SLSA Build L2 with no promotion. Low: unhashed pip install; `setup.sh` unpinned trivy and checkov fallback; `tfc_vcs_run_only` replay of an older configuration version; workflow-level `security-events: write`. OpenSSF Scorecard estimate after merge: about 5.5; about 7.5 with live governance codified.

**Adoption.** ADO-5 `--clouds saas` needs both Supabase and Vercel. ADO-6 starter still writes the full AWS estate. ADO-7 a new non-production environment needs a `tfc_admin_guard` override (SUSPECTED). ADO-8 removing a cloud breaks the gates. ADO-9 the quick start never says to run `terraform login`. ADO-10 `make install` does not pin versions, and README sends adopters to the heavy `make ci`. Low: seven false doc claims (a nonexistent identifier in QUICK_START, `make ci` lists missing `examples-plan`, a policy-set name, the `0.1.0` CHANGELOG date, a nonexistent module cited in a comment, a `dev.tfvars.example` claim, a GCP impersonation expiry written when GCP is off). Capability gaps unchanged: no EKS, AI/ML services, Azure, IdP or SCIM, service mesh, developer portal, AWS cost export or active-active primitives.
