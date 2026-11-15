# Fifth due-diligence re-audit (2026-11-15)

Six new independent reviewers read the code at commit `2c89d156` (branch `claude/enterprise-devops-audit-949b65`, not merged and not pushed). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md) and re-audits [1](2026-11-12-due-diligence-reaudit.md), [2](2026-11-13-due-diligence-reaudit-2.md), [3](2026-11-13-due-diligence-reaudit-3.md) and [4](2026-11-15-due-diligence-reaudit-4.md). They read the code first and the earlier reports only at the end, to label each finding NEW or KNOWN. The lead re-checked every NEW High in the code, and reproduced the two scanner bypasses.

This round follows the fixes for re-audit 4's "Fix now" list (commit `2c89d156`): the firewall internal pass group and drop alarms (ARC-1), the release verifier (CICD-1), regulated implies production (CMP-1), the file-read and remote-state scanner checks (SEC-1, SEC-2), and the config loader that failed soft (IAC-3).

## Verdict

**Overall: 6.4 / 10. Up from 6.3 at re-audit 4, the highest score so far, and still 0.8 below the Phase 2 forecast of 7.2. No Critical finding for the first time.**

Re-audit 4's Critical (ARC-1) is fixed correctly in code: the architecture reviewer traced every production packet path and found them consistent. System design rose from 5.5 to 6.8. But two of the last round's fixes were incomplete, and the panel found them:

1. **The SEC-1 file-read fix can be bypassed (SEC-1).** The scanner's allowlist matches the text of a call (`file(f)`), not what `f` is bound to. A one-line change in a root's `config.tf`, or in `envs/tfc-admin/main.tf`, reads `/proc/self/environ` at plan time and prints it in the plan error. The `archive` provider and the `google_client_config` data source are two more routes (SEC-2). Security fell from 7.5 to 6.0.
2. **The firewall fix removed a layer of prod/nonprod isolation (ARC-1).** The internal pass rule passes all of `top_cidr`, so the transit gateway blackhole routes are now the only barrier between prod and nonprod spokes. A spoke without a CIDR gets no blackhole, and the plan only warns.
3. **The tests miss security-critical mutations (IAC-1).** The Terraform reviewer seeded 16 bugs and the tests killed 9 (56%). A bug that makes the GCP admin-containment deny policy deny nobody passes all 33 runs that cover it.
4. **Nothing is proven on a real cloud, and the live repository is ungoverned.** Live settings still score 2/10. The audited HEAD is 237 commits ahead of `main` and on no remote branch. 67 breaking commits are unreleased.

## Scorecard

| Lens | 2026-11-11 | Forecast | Re-audit 1 | Re-audit 2 | Re-audit 3 | Re-audit 4 | Re-audit 5 | Change |
|---|---|---|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | 5.5 | 7.5 | 6.0 | -1.5 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 6.0 | 5.8 | 6.0 | +0.2 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | 6.0 | 5.5 | 6.8 | +1.3 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | 4.5 | 5.5 | 5.8 | +0.3 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | 7.0 | 7.4 | 6.8 | -0.6 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | 5.5 | 7.0 | 7.0 | 0.0 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | 4.5 | 4.5 | 4.5 | 0.0 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | 8.0 | 7.5 | 8.0 | +0.5 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **5.9** | **6.3** | **6.4** | **+0.1** |

Delivery is scored on the branch's code; the live repository settings score 2/10 (unchanged). Panel-to-panel differences of about 0.5 are within reviewer variance. The Terraform craft drop is mostly the new mutation test (re-audit 4's panel seeded 6 bugs, all caught; this panel seeded 16 in different code).

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| SEC-1 | `FILE_REFERENCE_ALLOW` matches the call text, not the binding. `[for f in ["/proc/self/environ"] : tonumber(file(f))]` in any root `config.tf`, or a redefined `local.workspace_variables_file_path` in `envs/tfc-admin/main.tf`, passes the scanner; `tonumber(file(f))` prints the file in the plan error (terraform 1.17.1). A platform-team writer (CODEOWNERS "platform or security" on `/envs/tfc-admin/`) can read the org-admin `TFE_TOKEN` from the run log | `scripts/check-plan-time-exec.py` (`FILE_REFERENCE_ALLOW`, `file_reference_allowed`) | VERIFIED (lead reproduced, rc=0), NEW: the re-audit 4 fix is incomplete |
| SEC-2 | Allowlisted data sources read runner files and tokens at plan. `data "archive_file"` with `source_file = "/proc/self/environ"` and `output_path = "${path.module}/e.zip"`, then `filebase64("${path.module}/e.zip")`, passes both layers (real plan read the file). `data "google_client_config"` returns the run's access token; the `google_service_account_access_token` / `_id_token` data sources mint tokens | `policies/opa/no_plan_time_code_execution.rego:84` (`exec_data_types`), `..._allowlist.rego:14` (`hashicorp/archive`) | VERIFIED (lead reproduced, rc=0), NEW (archive); KNOWN in part (`google_client_config`, 2026-11-05 audit) |
| ARC-1 | The internal pass group (`pass ip $HOME_NET -> $HOME_NET`, priority 1500) makes the transit gateway blackholes the only prod/nonprod isolation. A blackhole exists only when the spoke has a CIDR; the root copies the CIDR only when the spoke key equals the environment key; `segments_isolated` is a `check` (warning). Before `2c89d156`, the fail-closed firewall dropped prod-to-nonprod traffic as a second layer | `modules/aws/stages/network-hub/spokes.tf:76-99`, `envs/aws/network/config.tf:170`, `modules/aws/network/network-firewall/main.tf` | VERIFIED, NEW (regression from the ARC-1 fix) |
| IAC-1 | The deny-policy tests never assert the planned rules (`denied_principals`, `exception_principals`, `denied_permissions`, `denial_condition`). Mutants that exempt every denied principal or set the condition to `"true"` pass the primitive (6), the guardrails stage (12) and the root (15) suites | `modules/gcp/iam/deny-policy/tests/plan_assertions.tftest.hcl` (asserts count, name, parent only) | VERIFIED, NEW |
| CMP-1 | A regulated GCP environment can run on `production_egress_proxy_waiver` with any future expiry (the Secure Web Proxy is PREVIEW, so in practice every one does): the private tier reaches any internet destination through Cloud NAT. The VPC-SC waiver is refused for regulated environments; the egress waiver is not. The crosswalk's PCI 1.2/1.3 row overclaims for GCP | `envs/gcp/workload/main.tf:379-388`, `variables.tf:391-406` | VERIFIED, KNOWN (known-gaps), crosswalk overclaim NEW |
| CMP-2 | AWS regulated workloads do not enforce encryption in transit: `envs/aws/workload` and `app-services` never read `compliance_class`; `rds-aurora` has no cluster parameter group (`rds.force_ssl`); the default ALB is internal HTTP on :80 and `cloudfront_vpc_origin` forbids a certificate. The HIPAA 164.312(e)(1) and DORA Art. 9 rows claim "On" | `modules/aws/data/rds-aurora/main.tf`, `modules/aws/stages/app-services/main.tf:640-645`, `envs/aws/workload/variables.tf:621` | VERIFIED (Aurora default SUSPECTED), KNOWN (re-audit 4 CMP-4), raised to High |
| CICD-4 | The deployment-tag ruleset in `CI_SECRETS.md` does not cover the workload tags: `refs/tags/gcp-*/v*` does not match `gcp-workload/<env>/v*` (`*` does not cross `/`). The `tfc-readonly` tag policy has the same patterns, so workload release runs could never reach `TFC_TOKEN`. `BRANCH_PROTECTION.md:136-143` gives a second ruleset without a `creation` rule | `docs/guides/CI_SECRETS.md:199,225-232` | VERIFIED, NEW (doc patterns); the missing live ruleset is KNOWN |
| IAC-2 | `envs/aws/organization` and 4 of 5 `envs/gcp/network-hub` suites override the whole stage, so a wrong root-to-stage input passes (mutant: `member_break_glass_require_mfa = false`, 44/44 pass). aws-security and gcp-organization are now fixed | `envs/aws/organization/tests/root.tftest.hcl:38` | VERIFIED, KNOWN (re-audit 4), half fixed |

**Live-repository Highs (all KNOWN, unchanged):**
- CICD-1: no review required on `main`, admins exempt, stale required checks, no rulesets.
- CICD-2: secret scanning, push protection, Dependabot alerts and private vulnerability reporting off on a public repository.
- CICD-3: the `tfc-readonly`, `tfc-audit-trail` and `e2e-sandbox` environments do not exist, and no environment has a deployment policy.
- CICD-5: gitleaks is not a PR gate and is permanently red on 16 test-fixture `password =` lines (red NEW).
- CICD-6: 67 breaking commits since `v0.1.0`, unreleased; UPGRADING.md is 3,584 lines; the sandbox upgrade log is empty.

**What held.** The panel could not bypass the `landing_zone_config_path` validation (escapes and cleaned escapes fail; no symlinks), the remote-state `hostname` check, or the regulated-implies-production rule in the four roots it touches. The release verifier now runs from the default branch, after an on-`main` check, before any secret.

## Tool results at `2c89d156`

| Check | Result |
|---|---|
| `scripts/check-plan-time-exec.py` | 1,225 files, 0 problems (the bypasses are not in the repository) |
| `opa test policies/opa` | 339/339 |
| Scaffold matrix (`tests/config.tftest.hcl`, 15 roots) | All pass |
| Mutation test (16 non-equivalent mutants) | 9 killed (56%) |
| `make count` / `make links` / `make config-check` | Match README; 1,692 links, 0 broken; 130 valid, 24 negatives rejected |
| zizmor 1.31.1 (repo config) | 0 findings |
| `terraform fmt` / `validate` (sampled) | Clean |
| Live `main` CI | Red (run 43066418064); Sandbox E2E, Security Scan, State Backup and Drift scheduled runs red |

## Industry readiness (compliance lens)

| Target | Verdict | Blocking items |
|---|---|---|
| Fintech PCI DSS v4.0.1 | Ready with heavy work | GCP egress allowlist (CMP-1); AWS TLS to databases and ALB (CMP-2); no file integrity monitoring; MFA enforcement manual; no real-cloud evidence |
| HIPAA | Ready with work | CMP-2; CMEK beyond Cloud SQL on regulated GCP (CMP-8); BAAs; aws-backup ignores the class |
| SOC 2 | Ready with work | Operating evidence (CMP-9); waiver approver (CMP-6); branch protection not codified |
| ISO 27001 | Ready with work | ISMS documents are the customer's; waiver register; asset inventory export |
| UK FCA/PRA-regulated firm | Ready with heavy work | No FCA/PRA crosswalk; waiver governance; GCP backups in the same project and region; DR untested; single region |
| EU public sector (GDPR/NIS2) | Ready with heavy work | No sovereign partition, Assured Workloads or EKM; HCP Terraform EU needs a new organization; Vercel transfers to the US; no NIS2/GDPR crosswalk |

## Adopter verdicts (adoption lens)

| Adopter | Verdict | Why |
|---|---|---|
| Startup, GCP only | Adopt with work | About 28 manual actions over 8 workspaces, 2 to 3 days; production needs policy sets or a waiver, an egress proxy or waiver, and a VPC-SC decision; start on `starter` and sandbox first |
| Mid-size SaaS, AWS only | Adopt with work, sandbox first | About 27 actions over 9 workspaces, 1 to 2 weeks; an irreversible Vault Lock decision; TGW attachment IDs copied by hand |
| Regulated fintech, both clouds | Do not adopt yet | About 55 actions over 17 workspaces; 51 "validate before relying on" controls; no real-cloud evidence an auditor can sample |
| Platform team wanting a reference | Adopt as a reference | The one-file config, layered contracts, plan-time guard, scaffold matrix and runbooks are high quality and largely accurate |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Estate | Estimate |
|---|---|
| AWS production, 1 region, 2 AZs | About 1,600 to 2,100 with one spoke (1,050 to 1,500 before the first spoke); add about 440 for the VPN and Resolver endpoints |
| AWS starter | About 900 to 1,100 with a spoke (350 to 550 before) |
| GCP, hub and 2 environments | About 60 to 180; add about 912 per Secure Web Proxy gateway |
| HCP Terraform | Standard about 700 to 1,400 (about 1,500 to 3,000 resources under management); Essentials about 150 to 300 |

The repository's cost tables still omit the Route 53 Profile (about 548 per month in every profile, starter included), transit gateway attachments, interface endpoints, NAT, PSC endpoints, the Secure Web Proxy and the HCP resource count (ARC-4, KNOWN).

## Genuinely strong

- Transit gateway routing: separate prod, nonprod, inspection, shared and hybrid tables, appliance mode, and on-premises prefixes learned only by the inspection table. The firewall rule order and pass semantics are correct.
- The plan/apply identity split on both clouds, ID-pinned bindings, the AWS apply boundary and the RCP data perimeter.
- A broad, fail-closed plan-time scanner that reads its lists from the OPA policy; most bypass attempts were caught.
- Workflow hygiene: SHA pins, `permissions: {}`, harden-runner `block` on every job with a secret, zizmor clean.
- The audit trail: CloudTrail digests, Object Lock COMPLIANCE by default, retention floors per framework, the GCP regulated audit store.
- The scaffolder and the CI-checked scaffold-to-plan matrix in all 15 roots; 0 broken links; runbooks that cite file and line.

## Recommendation

**Fix now (small, mostly non-breaking):**

1. SEC-1: pin each allowed file reader to its full canonical expression (hash the normalised `lz_documents` and `landing_zone_config_file` blocks, and the tfc-admin local's definition), and add the two bypasses to the scanner test corpus.
2. SEC-2: add `google_client_config`, `google_service_account_access_token`, `google_service_account_id_token` and `google_service_account_jwt` to `exec_data_types`; allow `archive_file` only in `modules/aws/security/incident-response`, with literal sources under `path.module`.
3. ARC-1 and ARC-2: make `segments_isolated` a precondition when both segments exist; build the pass rules per segment (prod to prod, nonprod to nonprod, every spoke to the hub VPCs and on-premises) instead of `top_cidr` to `top_cidr`; accept only private ranges outside `top_cidr` in `internal_pass_cidrs`.
4. IAC-1 and IAC-3: assert the deny-policy rules on the planned resource at the primitive and stage levels; decode the KMS key policy and assert the organization condition on every log-service statement.
5. CICD-4 and CICD-10: one tag ruleset with `creation`, `update`, `deletion` and `non_fast_forward` on every pattern in `on.push.tags` (workload tags listed explicitly), a matching `tfc-readonly` tag policy, a check that diffs the documented patterns against the workflow, and a boolean instead of `TFC_TOKEN` in the "Assert credentials" step.
6. CMP-1 to CMP-3: refuse the egress proxy waiver for regulated GCP environments (or cap its lifetime), read `compliance_class` in aws-workload (`rds.force_ssl`, refuse the `is_production` and gateway-endpoint overrides), run the tfc-admin CMP-1 check on the effective environment map, and correct the PCI 1.2/1.3, HIPAA 164.312(e)(1) and DORA Art. 9 crosswalk rows.

**Then, as the last four reports said:** turn the freeze on (`docs/moai/plans/2026-11-13-freeze-and-v0-2-0.md` Part A), push and merge the branch so `main` is the audited code, fund one sandbox apply per cloud, and take the Phase 3 owner steps: codified rulesets and environments (with the corrected tag patterns), a second maintainer, a green `main`.

## Appendix: Medium and Low findings

**Security.** SEC-3 the provisioner-exempt module (`modules/supabase/vault-secrets`, its `.mjs` scripts and `envs/saas`) is owned by the app-platform team alone, and the scanner does not pin the provisioner commands or script hashes (NEW). SEC-4 speculative plans and CLI uploads skip the scanner; CI runs the PR's own copy (KNOWN). SEC-5 `organization-apply` holds unconditional org `folderIamAdmin`; principal access boundary off by default (KNOWN). Low: SEC-6 tag ruleset manual; SEC-7 Supabase password and service-role key in state; SEC-8 WIF name fallback (all KNOWN).

**Compliance.** CMP-3 the CMP-1 rule can be bypassed with variables: `var.is_production` and `enable_gateway_endpoint_policies = false` win in aws-workload, and tfc-admin's check reads only the config file, not `var.environments` (NEW). CMP-4 some production controls are keyed on `org.profile` (`restrictTLSVersion`, the AWS egress gate for non-regulated production) or only warn (the GCP production audit store, the hub perimeter) (NEW). CMP-5 `gcp.admin_containment: false` waives containment for a regulated estate with no reason or expiry (NEW). CMP-6 waivers have no approver or maximum lifetime; `egress_alert_only_waived` and the containment opt-out never expire; no waiver register output (KNOWN). CMP-7 a regulated AWS estate can run the log archive in GOVERNANCE mode when `compliance.frameworks` is empty (KNOWN). CMP-8 `restrictNonCmekServices` is not applied to regulated folders (KNOWN in part). CMP-9 `compliance.frameworks: [pci_dss]` does not enable the Security Hub PCI standard; no GCP posture (NEW in part). Low: CMP-10 the GCP organization stage's default `allowed_regions` includes `us-central1` (NEW); CMP-11 aws-backup, gcp-projects and saas ignore the class (KNOWN).

**Architecture.** ARC-2 `internal_pass_cidrs` accepts any CIDR, `0.0.0.0/0` included, which passes all egress before the allowlist while the production egress gate still passes (NEW). ARC-3 expired waivers fail every plan, the hotfix included, with no warning beforehand (KNOWN). ARC-4 cost tables (above, KNOWN). ARC-5 AZ IDs optional in production (KNOWN). ARC-6 spoke onboarding takes three runs and a hand copy on both clouds (KNOWN). ARC-7 single region; a workload in another region fails without a clear message (KNOWN). Low: ARC-8 no firewall or attachment health alarm (NEW); ARC-9 the "threat groups drop before any allow" comment is wrong for internal flows, which are not inspected after the pass (NEW); ARC-10 address space limits (KNOWN); ARC-11 the allowlist sees only HTTP and TLS, so Postgres egress to Supabase needs custom rules (NEW).

**Terraform craft.** IAC-3 the KMS key-policy tests match `aws:SourceOrgID` anywhere in the JSON, so dropping it from the non-CloudTrail log grants passes (NEW). IAC-4 no check that the hub CIDRs are disjoint; `inspection_cidr = egress_cidr` plans (NEW). IAC-5 the GCP KMS checkov skip says rotation is capped at 90 days; the validation allows 365 (NEW). IAC-6 the config loader still turns a wrong-typed key into null and a default (KNOWN, half fixed). IAC-7 `modules/vercel/project` `nonsensitive()` on whole value maps (KNOWN). Low: IAC-8 a directory path gives a raw `fileexists` error (fails closed, NEW); IAC-9 `tfc/workspace` `agent_pool_id` gating untested (NEW); IAC-10 the config loader in 15 roots, 5 variants (KNOWN).

**Delivery.** CICD-7 `main` CI red (KNOWN). CICD-8 Renovate never ran; no release-age delay (KNOWN). CICD-9 CODEOWNERS placeholders, 71 errors, enforcement off (KNOWN). Low: CICD-10 `TFC_TOKEN` also reaches the "Assert credentials" step, so the commit's "curl step only" claim is false (NEW); CICD-11 plan jobs run harden-runner in `audit` (KNOWN); CICD-12 `check-jsonschema` without hashes, terraform-docs checked against its own release (KNOWN), live `sha_pinning_required` off (NEW); CICD-13 release App unset (KNOWN). OpenSSF Scorecard estimate: about 5.0 live, 6.0 after merge, 7.5 with the documented governance in force.

**Adoption and documentation.** ADO-R1 `make install` fails on a PEP 668 Python (stock macOS Homebrew, Ubuntu 24.04) (NEW). ADO-R2 UPGRADING.md says upstream never changes `.github/CODEOWNERS` or `config/sandbox/`; it does (NEW). ADO-R3 the GCP runbook names `organization_apply_grantable_roles` and `github_wif_pool_id` as root inputs; they are stage variables only (NEW). ADO-R4 `ghain-REPLACE_ME` not rejected at plan (KNOWN). ADO-R5 health assessments ignore `org.tfc.plan` (KNOWN). Low: ADO-R6 QUICK_START GitHub WIF claim, ADO-R7 sandbox upgrade log promise (KNOWN); ADO-R8 `aws-landing-zone.md` still says spoke-to-spoke and on-premises flows are inspected and omits the internal pass group (NEW); ADO-R9 "exact versions" claim for `make install` (NEW); ADO-R10 the example YAML called "the schema" (NEW); ADO-R11 `make ci` gate lists incomplete (NEW); ADO-R12 scaffold plans only `dev`, no `terraform login` step (KNOWN); ADO-R13 cognitive load: `known-gaps.md` 1,895 lines with 51 "validate before relying on" items (KNOWN).
