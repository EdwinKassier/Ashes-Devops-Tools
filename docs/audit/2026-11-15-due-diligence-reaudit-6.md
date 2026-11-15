# Sixth due-diligence re-audit (2026-11-15)

Six new independent reviewers read the code at commit `e1ade74d` (branch `claude/enterprise-devops-audit-949b65`, not merged and not pushed). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md) and re-audits [1](2026-11-12-due-diligence-reaudit.md) to [5](2026-11-15-due-diligence-reaudit-5.md). They read the code first and the earlier reports only at the end, to label each finding NEW or KNOWN. The lead re-checked every NEW High in the code and reproduced the scanner bypasses.

This round follows the fixes for re-audit 5's "Fix now" list (commit `e1ade74d`). Two adversarial reviews ran on those fixes before the commit and found five further bypasses, which the same commit closed.

## Verdict

**Overall: 6.4 / 10. Unchanged from re-audit 5. No Critical finding in the code.**

The re-audit 5 fixes are real. The compliance reviewer re-ran each one as a probe and found none cosmetic. The architecture reviewer traced every production packet path and confirmed that prod and nonprod are again separated by two layers. The Terraform mutation kill rate rose from 56% to 73%. Terraform craft (7.2), delivery code (7.6) and compliance (6.4) went up. Documentation accuracy fell (8.0 to 7.0), because the fix commit left its own changes undocumented in four places. What holds the score down:

1. **The plan-time scanner was bypassed for the third round running (SEC-1).** Its new template scan strips `#` comments and counts braces without knowing string literals, so `${"#" != "" ? file(...) : ""}` and `${"}" == "}" ? file(...) : ""}` pass. A real plan printed the file. Separately, the scanner runs without `python3 -I`, so a platform-owned `scripts/hcl2.py` can switch it off (SEC-2).
2. **A new production network risk (ARC-1).** The production egress gate requires `aws:drop_established`. AWS documents that this action drops TLS handshakes split across two packets, which post-quantum key shares now cause (Go 1.24+, OpenSSL 3.5, Chrome). AWS added `aws:drop_established_app_layer` for this in 2025, and the module refuses it. If a sandbox confirms the breakage, this is Critical.
3. **The regulated class is still thin on AWS (CMP-1)** and can still be removed through a gcp-organization variable (CMP-3) or another estate's config file (CMP-4).
4. **Nothing is proven on a real cloud, and the live repository is ungoverned.** Live settings score 2.5/10. 82 of 90 control rows are mock or PREVIEW. 68 breaking commits are unreleased.

## Scorecard

| Lens | 2026-11-11 | Forecast | Re-audit 1 | Re-audit 2 | Re-audit 3 | Re-audit 4 | Re-audit 5 | Re-audit 6 | Change |
|---|---|---|---|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | 5.5 | 7.5 | 6.0 | 6.2 | +0.2 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 6.0 | 5.8 | 6.0 | 6.4 | +0.4 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | 6.0 | 5.5 | 6.8 | 6.8 | 0.0 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | 4.5 | 5.5 | 5.8 | 5.6 | -0.2 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | 7.0 | 7.4 | 6.8 | 7.2 | +0.4 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | 5.5 | 7.0 | 7.0 | 7.6 | +0.6 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | 4.5 | 4.5 | 4.5 | 4.5 | 0.0 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | 8.0 | 7.5 | 8.0 | 7.0 | -1.0 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **5.9** | **6.3** | **6.4** | **6.4** | **0.0** |

Delivery is scored on the branch's code; live settings score 2.5/10 (2.0 at re-audit 5). The delivery reviewer rates the live branch protection and the missing tag ruleset Critical; earlier reports rated them High, and they are settings, not code. Panel-to-panel differences of about 0.5 are within reviewer variance.

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| SEC-1 | The `templatefile()` template scan strips `#...` inside `${...}` before looking for calls and matches braces without string awareness. `${"#" != "" ? file("/etc/hosts") : ""}` and `${"}" == "}" ? file("/etc/hosts") : ""}` pass the scanner; a real plan printed the file. A platform writer can read the org-admin `TFE_TOKEN` through a template in `envs/tfc-admin` | `scripts/check-plan-time-exec.py` (`template_expressions`, `TEMPLATE_COMMENT`) | VERIFIED (lead reproduced, rc=0), NEW: the re-audit 5 fix is incomplete |
| ARC-1 | Production and regulated egress must use `aws:drop_established`; the module allows only the four classic actions. AWS added `aws:drop_established_app_layer` (2025) because a TLS ClientHello split across segments is dropped before the SNI rule matches; post-quantum key shares (X25519MLKEM768) make that common. ECR pulls, Secrets Manager and GitHub egress can fail, and the fix is refused | `modules/aws/network/network-firewall/variables.tf:62-64`, `modules/aws/stages/network-hub/main.tf:535` | VERIFIED in code (lead), SUSPECTED on a real cloud, NEW |
| ARC-2 | The Route 53 Profile costs USD 0.75 per account-hour (about 548 per month); every workload account associates it, so 5 accounts may cost about 2,700 per month. It is in no cost table. The sandbox budget is USD 300 against about 1,000 idle | `modules/aws/stages/workload` (`aws_route53profiles_association.spoke`), `config/sandbox/landing-zone.yaml:32` | Price VERIFIED, per-account billing SUSPECTED, partly KNOWN |
| CMP-1 | The AWS regulated class does not require the ALB WAF, ALB access logs, an immutable backup copy or CloudTrail S3 read events. A regulated `public_alb` with `enable_app_waf = false` and no log bucket plans | `envs/aws/workload/main.tf:379-398`, `variables.tf:626,675` | VERIFIED (probe), KNOWN parts raised to a regulated-class gap |
| CMP-2 | 82 of 90 control-matrix rows are mock or PREVIEW; the HCP audit trail (CHG-07) is off until a secret is set; MFA is manual | `docs/compliance/control-matrix.md` | VERIFIED, KNOWN |
| ADO-1 | No release a fork can pin: 68 breaking commits since `v0.1.0`, UPGRADING "Unreleased" spans lines 39 to 3597, the sandbox upgrade log is a template | `UPGRADING.md` | VERIFIED, KNOWN |

**Live-repository findings (all KNOWN, unchanged):** no review required on `main`, admins exempt, a phantom required context, and PR #599 merged with `Validation Summary` red (CICD-1); no rulesets, and the `tfc-readonly`, `tfc-audit-trail` and `e2e-sandbox` environments missing (CICD-2); secret scanning, push protection, Dependabot alerts and private vulnerability reporting off, with 306 open code-scanning alerts (CICD-3). No secrets are configured, so today's blast radius is zero; the ruleset and environments must exist before the secrets.

**What held.** The pinned file readers (re-audit 5 SEC-1), the token data-source denylist, the per-segment firewall rules, the spoke CIDR validations, the regulated-by-account check, the 90-day waiver cap, Aurora `rds.force_ssl` (as a parameter group), and the release workflow's default-branch check. The security reviewer's other probes (`for`-bound `f`, `core::file`, `file/**/()`, `templatestring`) were refused or failed closed.

## Tool results at `e1ade74d`

| Check | Result |
|---|---|
| `scripts/check-plan-time-exec.py` | 1,225 files, 0 problems (the bypasses are not in the repository) |
| `opa test policies/opa` | 356/356 |
| Mutation test (11 non-equivalent mutants) | 8 killed (73%) |
| Scaffold matrix and default scaffold under the new OPA rule | Pass |
| `make links` / `check-tag-patterns.py` / zizmor 1.32.0 | 1,698 links, 0 broken; 0 problems; 0 findings |
| Live `main` CI | Red |

## Industry readiness (compliance lens)

| Target | Verdict | Blocking items |
|---|---|---|
| Fintech PCI DSS v4.0.1 | Ready with heavy work | GCP egress allowlist (PREVIEW proxy); AWS regulated WAF, request logs and read data events (CMP-1); no file integrity monitoring; MFA manual; no real-cloud evidence |
| HIPAA | Ready with work | Immutable AWS backups not required for regulated (CMP-1); BAAs; CMEK beyond Cloud SQL; waiver lifetime (CMP-5) |
| SOC 2 | Ready with work | Operating evidence (CMP-2); CHG-07 off by default; waiver approver and register; branch protection not codified |
| ISO 27001 | Ready with work | ISMS documents are the customer's; waiver register; asset inventory export |
| UK FCA/PRA-regulated firm | Ready with heavy work | Single region, DR never tested, AWS backup copy opt-in; no FCA/PRA crosswalk; HCP Terraform as a material third party |
| EU public sector (GDPR/NIS2) | Ready with heavy work | No sovereign partition, Assured Workloads or EKM; Vercel transfers to the US; no NIS2/GDPR crosswalk |

## Adopter verdicts (adoption lens)

| Adopter | Verdict | Why |
|---|---|---|
| Startup, GCP only | Do not adopt for production; adopt with work for a dev foundation | About 30 manual actions; production needs HCP Standard and either the PREVIEW egress proxy or rolling waivers |
| Mid-size SaaS, AWS only | Adopt with work, sandbox first | The most complete path, about USD 1,400 to 1,900 per month idle, never applied; 2 to 3 weeks |
| Regulated fintech, both clouds | Do not adopt yet | Regulated guards proven only under mocks; regulated GCP rests on PREVIEW or 90-day waivers; the regulated-controls page is stale; no release to pin |
| Platform team wanting a reference | Adopt | Scaffolder plus fixture matrix, two policy layers, pinned loaders, runbooks |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Estate | Estimate |
|---|---|
| AWS production, 1 region, 2 AZs, 1 spoke | About 1,700 to 2,200; about 585 more per extra spoke account (Route 53 Profile and attachment); about 475 more with the VPN |
| AWS starter | About 900 to 1,150 |
| GCP, hub and 2 environments | About 60 to 200; about 912 more per Secure Web Proxy gateway |
| HCP Terraform | Standard about 700 to 2,800; Essentials about 150 to 600 |

## Genuinely strong

- Per-stage, per-phase identities on both clouds; WIF bindings by immutable ID; the AWS apply boundary and RCP set.
- The per-segment Suricata design and the CIDR validations (private ranges, no overlap with HOME_NET, spokes inside `top_cidr` and disjoint).
- Regulated implies production in every root; regulated detection by account; guards that name the config key to fix.
- An honest crosswalk with an "ID checked" column, corrected for partial coverage.
- Workflow hygiene and the release-metadata chain; one dependency bot per ecosystem.
- The scaffolder, its CI-checked plan matrix, and 0 broken links.

## Recommendation

**Fix now (small, mostly non-breaking):**

1. SEC-1 and SEC-2: make the template scan fail closed on any `file`, `templatefile` or `templatestring` token anywhere in a template body (no comment stripping, no brace matching), add both bypasses to the test corpus, and run the scanner as `python3 -I` with a check that no tracked `scripts/*.py` shadows `hcl2` or a standard-library module.
2. ARC-1: accept `aws:drop_established_app_layer` and `aws:drop_established_to_server` in the module and the production gate, and make `drop_established_app_layer` the documented and example default.
3. CMP-1, CMP-3 and CMP-4: in `regulated_guard`, refuse `enable_app_waf = false` and require `app_alb_access_logs_bucket`; copy tfc-admin's `var.environments` check to gcp-organization; carry `compliance_class` in the gcp-projects contract (or pin the estate path per workspace) so another estate's file cannot drop it.
4. IAC-1 and IAC-2: assert that the Aurora cluster attaches the TLS parameter group, and apply `rds.force_ssl` immediately (it is a dynamic parameter) instead of at the next reboot.
5. Documentation: correct the four stale places (the example YAML's firewall comment, `regulated-environments.md`, the `policy-as-code.md` row, and the `""` advice in QUICK_START and the root validation messages), put the Route 53 Profile in the cost tables per account, add security owners for the firewall modules, `vault-secrets`, `verify-run-commit.sh` and the ruleset docs in CODEOWNERS, and put the environment in every secret row of `CI_SECRETS.md`.

**Then, as the last five reports said:** turn the freeze on, push and merge the branch, fund one sandbox apply per cloud (it settles ARC-1 and ARC-2 too), cut v0.2.0 with a recorded upgrade, and take the Phase 3 owner steps (rulesets, environments, scanning, a second maintainer, a green `main`).

**A process note.** Three rounds in a row, the plan-time scanner fix was bypassed by the next panel. A regular-expression scanner of HCL and template syntax will keep losing this race. Running the scanner as an HCP pre-plan run task, parsing templates with a real HCL template parser, and restricting `templatefile()` to reviewed paths would end it.

## Appendix: Medium and Low findings

**Security.** SEC-2 the scanner runs without `python3 -I`, so a platform-owned `scripts/hcl2.py` (`def loads(t): return {}`) makes it report 0 problems (`scripts/check-consistency.sh:264`, NEW). SEC-3 regulated controls switch off when a workload reads another estate's file, including the committed sandbox file; a committed `*.auto.tfvars` can set it (KNOWN in part). SEC-4 `organization-apply` holds unconditional org `folderIamAdmin` (KNOWN). SEC-5 speculative plans and CLI uploads run before or without the scanner (KNOWN). Low: SEC-6 unsalted Vercel fingerprints (KNOWN); SEC-7 `modules/gcp/project` and `monitoring/control-plane` platform-only owners (KNOWN residual); SEC-8 the documentation job runs repo code before the `DOCS_BOT_PAT` step (SUSPECTED, NEW).

**Compliance.** CMP-3 a gcp-organization `environments` variable that omits `compliance_class` drops the regulated audit-store guard (`envs/gcp/organization/config.tf:165,183`, NEW). CMP-4 the OPA rule accepts `config/sandbox/landing-zone.yaml`, which has no regulated environment (NEW). CMP-5 the 90-day cap covers one waiver; `audit_store_waiver` and `policy_sets_waiver` are uncapped, a shipped test waives regulated WORM to 2099, and no waiver has an approver (NEW remainder of KNOWN). CMP-6 regulated GCP egress still unrestricted while the proxy is PREVIEW (KNOWN). Low: CMP-7 `regulated-environments.md` and the NET-11 and DP-04 matrix rows not updated (NEW); CMP-8 no `log_connections`/pgaudit, a stale checkov skip comment, no Security Hub PCI standard (KNOWN in part).

**Architecture.** ARC-3 expired waivers block every plan with no warning; the regulated cap means four renewals a year (KNOWN, worse). ARC-4 the hub trusts the configured spoke CIDR, not the real VPC CIDR; a missing `vpc_cidr`, a netmask allocation or an out-of-band secondary CIDR breaks the blackholes and pass rules (NEW). ARC-5 single region (KNOWN). ARC-6 upgrade burden: 72 breaking commits since 2026-11-01, UPGRADING.md 3,641 lines (KNOWN). Low: ARC-7 the example YAML's stale firewall comment, copied into new estates (NEW); ARC-8 one Secure Web Proxy allowlist for every GCP environment (SUSPECTED, NEW); ARC-9 spoke onboarding needs three runs (KNOWN).

**Terraform craft.** IAC-1 the Aurora TLS group is never asserted as attached to the cluster (mutant survived, NEW). IAC-2 `pending-reboot` leaves existing clusters accepting plaintext until a reboot Terraform never triggers (SUSPECTED, NEW). IAC-3 an Aurora major-version upgrade will fail without `allow_major_version_upgrade` (SUSPECTED, NEW). IAC-4 aws-organization and 4 of 5 gcp-network-hub suites override the whole stage (KNOWN). IAC-5 aws-workload has no `compliance_class` enum check; `Regulated` silently means standard there (KNOWN class). Low: IAC-6 the log-archive TLS deny on object ARNs is unasserted (NEW); IAC-7 a firewall rule-group replacement will fail (fixed names, no create-before-destroy; SUSPECTED, NEW); IAC-8 Vercel `nonsensitive()` maps (KNOWN).

**Delivery.** CICD-4 the breaking-change gate only checks that UPGRADING.md is in the diff (NEW weakness). CICD-5 CODEOWNERS gives no security review to the firewall and network modules, `vault-secrets`, `verify-run-commit.sh` and the ruleset docs (NEW). CICD-6 the sandbox E2E jobs allow egress to `*.googleapis.com` while holding OIDC credentials (NEW). CICD-7 the documented release gate is stale (KNOWN). CICD-8 `CI_SECRETS.md` lists the TFC tokens as plain secrets in one table and as environment secrets in another (NEW). Low: CICD-9 `check-tag-patterns.py` accepts any bypass actor (NEW); CICD-10 unhashed `check-jsonschema`, gitleaks download without a digest (gitleaks NEW); CICD-11 workflow-level `security-events: write`; CICD-12 Renovate not installed, release App unset (KNOWN). OpenSSF Scorecard estimate: about 5.0 live, 6.0 after merge, 7.5 with governance in force.

**Adoption and documentation.** ADO-2 the example YAML still says the firewall passes all traffic inside `top_cidr` (NEW). ADO-3 `regulated-environments.md` omits the 90-day cap, the aws-workload guard and Aurora TLS (NEW). ADO-4 `policy-as-code.md` omits the AWS, Redshift and Vercel data sources and the config-path rule (NEW). ADO-5 QUICK_START, the root validation messages and ADR-0002 advise `""`, which OPA now refuses in HCP (NEW). ADO-6 the UPGRADING fork-owned paths (KNOWN). ADO-7 `make install` fails on PEP 668 Python (KNOWN). ADO-8 no `terraform login` step; CLAUDE.md says the CLI needs `TFC_TOKEN` (NEW claim). Low: ADO-9 to ADO-12 KNOWN; ADO-13 the scaffolder's production checklist omits the GCP VPC-SC and egress decisions (NEW); ADO-14 the waiver variable description omits the 90-day cap (NEW).
