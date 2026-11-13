# Second due-diligence re-audit, after Phase 2b (2026-11-13)

Six new independent reviewers read the code at commit `5abf1570` (branch `claude/enterprise-devops-audit-949b65`, not merged). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md) and the [first re-audit](2026-11-12-due-diligence-reaudit.md). They got the code first and read the earlier audits only at the end, to label each finding NEW or KNOWN. The lead re-checked every Critical.

## Verdict

**Overall: 5.7 / 10. Down from 6.0 at the first re-audit, and 1.5 below the Phase 2 forecast of 7.2.**

Phase 2b closed all ten of its gap groups, and the gates are green (3,220 test runs, 403 policy tests, clean scanners). The score still fell, for three reasons:

1. **Each panel looks deeper and finds a new class of defect.** This panel found gaps in the data-exfiltration perimeter, in the identity policy gates and in the GCP network plan. Earlier panels did not reach these areas. Fixing findings one by one does not converge, because nothing has been applied to a real cloud. Mocks accept values and designs that the cloud APIs or the attack paths would reject.
2. **The change rate counts against operability and adoption.** There are 57 breaking commits since v0.1.0 (5 days), UPGRADING.md is 3,218 lines, and no upgrade has been tested.
3. **Governance is unchanged.** No review is enforced on `main`, CI on `main` is red, and the bus factor is 1. Only owner action fixes these (Phase 3).

Score differences of about 0.5 between panels are within reviewer variance. The direction is clear: more code changes alone will not reach the forecast. The next gains come from a sandbox apply, owner governance steps and a breaking-change freeze. See [Recommendation](#recommendation).

## Scorecard

| Lens | 2026-11-11 | Forecast after Phase 2 | Re-audit 1 (2026-11-12) | Re-audit 2 (2026-11-13) | Against re-audit 1 |
|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | -0.5 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 0.0 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | -0.5 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | -1.0 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | -0.6 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | -0.5 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | +0.5 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | +0.5 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **-0.3** |

## Critical findings (lead-verified)

| ID | Finding | Lead verdict | Status |
|---|---|---|---|
| ARC-C1 | The production VPC-SC perimeter protects only the network host project, not the team projects where the services and data live | CONFIRMED | NEW |
| CICD-1 | No review is enforced before a change reaches `main`, which HCP Terraform deploys from | CONFIRMED (live settings) | KNOWN, Phase 3 |

**ARC-C1.** `modules/gcp/stages/environment/main.tf:131-133` sets `protected_projects = [data.google_project.host_project.number]` and nothing else. No other code adds projects to an environment perimeter (lead-checked: no `google_access_context_manager_service_perimeter_resource`, no other `protected_projects` source). Production refuses services in the host project (`envs/gcp/workload/main.tf:203-205`), so Cloud Run, Cloud SQL, Artifact Registry and Secret Manager sit in `service_team` projects outside the perimeter. The regulated class says the perimeter must be enforced. The plan gate passes, but data in the team projects is not protected against exfiltration. Fix: add every service-team, GKE and app project number to the environment perimeter, then prove in the sandbox that an enforced perimeter still lets the Shared VPC services run.

**CICD-1.** Live `main` protection has no required reviews, `enforce_admins=false`, and stale required checks. The last 30 pull requests were self-merged. Fix: Phase 3 (codified rulesets and a second maintainer, owner decisions O1 and O3).

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| SEC-1 | The mandatory OPA federated-trust gates can be bypassed: AWS subjects with a wildcard after the first segment, `sts:AssumeRoleWith*` actions, `repo:owner/app:*`; GCP `attribute.terraform_run_phase/apply`, `attribute.terraform_workspace_name/...` and workforce pools | `policies/opa/aws_iam_federated_trust_pinned.rego`, `gcp_wif_principalset_pinned.rego:21-26` (reviewer proved with `opa eval`) | VERIFIED, NEW |
| SEC-2 | `organization-plan` holds `roles/logging.viewer` at the org node, so every platform engineer (default `runs = plan`) and the drift token can read all org logs through a speculative plan | `modules/gcp/stages/bootstrap/service_accounts.tf:55` (lead-checked) | VERIFIED, NEW |
| SEC-3 | A provider binary committed under `terraform.d/plugins` beats the provider-name allowlist and the CI scanner | `no_plan_time_code_execution_allowlist.rego`, `scripts/check-plan-time-exec.py` | SUSPECTED, NEW |
| SEC-4 | `tfc_vcs_run_only` is PREVIEW and overridable; an approver can also replay an older VCS configuration version | `policies/opa-destructive/tfc_vcs_run_only.rego` | KNOWN; replay NEW |
| SEC-5 | The phase-0 management apply role has no boundary; it can create IAM users and access keys in the payer account | `templates/aws/bootstrap/phase0-management.yaml` | KNOWN, severity raised |
| ARC-H1 | Cloud Run defaults to `PRIVATE_RANGES_ONLY` egress, so production traffic skips NAT, the Secure Web Proxy and the egress gate | `modules/gcp/stages/app-services/variables.tf:238` | VERIFIED, NEW |
| ARC-H2 | The egress proxy endpoint must be in the hub's region (Google rule); environments in another region fail | `modules/gcp/stages/net-spoke/main.tf:163-185` | VERIFIED, NEW |
| ARC-H3 | Private Service Access takes an auto-allocated /16 in every VPC, outside the IP plan and the overlap check | `net-spoke/main.tf:189-197`, `net-hub/main.tf:166-174` | VERIFIED, NEW |
| ARC-H4 | On-premises may never learn AWS spoke routes over BGP VPN: the hybrid TGW table holds only `0.0.0.0/0` | `modules/aws/stages/network-hub/main.tf:450-462` | SUSPECTED, NEW |
| ARC-H5 / H7 / H9 | IP plan ceiling; single region; upgrade load (149 entries, 39 breaking) | `docs/architecture/cidr-plan.md`, `UPGRADING.md` | KNOWN |
| ARC-H6 | All Cloud Run services and GKE nodes share one /24 per environment | `modules/gcp/stages/environment/main.tf:374` | VERIFIED, NEW |
| ARC-H8 | Every new environment or account needs a `tfc_admin_guard` security override (team access and `TFC_*` variables), so overrides become routine | `policies/opa-destructive/tfc_admin_guard.rego` | VERIFIED, NEW framing |
| CMP-R1 | GCP regulated flow logs sit in a BigQuery dataset the workload pipeline administers, outside the locked audit store | `modules/gcp/stages/environment/main.tf:112-119` | VERIFIED, NEW |
| CMP-R2 | AWS WAF and ALB request logs are never wired; CloudFront uses the default certificate | `modules/aws/stages/workload/main.tf:277-291` | VERIFIED, NEW |
| CMP-R3 | The production permission-set guard blocks only `Developer` | `envs/aws/identity/variables.tf:145-150` | KNOWN (CMP-04) |
| CMP-R4 | GCP backups are not segregated or copied across regions | `modules/gcp/backup/backup-vault/main.tf:37-38` | KNOWN (CMP-07) |
| CICD-2 | Control-plane and production PRs merge without anyone seeing a plan; BRANCH_PROTECTION.md recommends a TFC status check that never posts | `docs/guides/BRANCH_PROTECTION.md:44-52` | KNOWN; doc contradiction NEW |
| CICD-3 / SEC-10 | CODEOWNERS: `/modules/gcp/iam/` (holds the deny-policy module the guardrails use) and `/modules/tfc/` are platform-approvable | `.github/CODEOWNERS` | VERIFIED, NEW |
| CICD-4 / CICD-5 | Environment secrets rely on unprotected environments; `v*` tags unsigned and mutable | live `gh api` | KNOWN |
| IAC-1 | CMEK grants name Google service agents by hand-built email and never create them; a fresh first apply can fail | `modules/gcp/stages/organization/main.tf:93-136` | SUSPECTED, NEW |
| IAC-2 | 57 breaking commits since v0.1.0; one shared version; fork-only consumption | `git log v0.1.0..HEAD` | KNOWN |
| ADO-20 | A production scaffold ships with every OPA policy set off (`org.tfc.plan` commented; check warns only) | `envs/tfc-admin/config.tf:156-157` | VERIFIED, NEW |
| ADO-21 | The scaffolded production AWS config does not plan: security contact and alarm subscriber emails are required but not prompted | `envs/aws/security/main.tf:134` | VERIFIED, NEW |
| ADO-22 / ADO-23 | GCP production needs two waivers or a PREVIEW proxy; no multi-team model (ADR 0015 Proposed) | `envs/gcp/workload/main.tf:347,373` | KNOWN |

Medium and Low findings are in the [appendix](#appendix-medium-and-low-findings).

## Tool results at `5abf1570`

| Gate | Result |
|---|---|
| `terraform fmt -check -recursive` | Pass |
| tflint, 15 roots and 12 modules | 0 issues |
| checkov 3.3.17, modules / envs | 1,432 / 872 passed, 0 failed; 4 parse errors; 410 inline skips |
| trivy 0.70.0, CI flags | 0 Critical or High |
| `opa test policies/` | 403 / 403 |
| zizmor 1.31.1, actionlint | 0 findings |
| `make test` (lead run before the last docs commit) | 3,220 runs in 145 directories, 0 failed |
| `make count-check`, `make links` | Pass (126 modules, 15 roots, 350 suites; 1,574 links) |

## Industry readiness (compliance lens)

| Segment | Verdict | Main blocker |
|---|---|---|
| Startup SOC 2 | Ready with work | MFA, access reviews and audit-trail secret are on the adopter |
| Retail, media, telecom | Ready with work | AWS WAF and ALB logs not wired (CMP-R2) |
| AI/ML | Ready with work | No AI-service controls |
| Fintech PCI DSS 4.0.1 | Ready with heavy work | No FIM; flow logs mutable on GCP; Aurora TLS not enforced |
| Banking (DORA, FCA/PRA, SOX ITGC) | Not supported as shipped | Standing production admin, GCP backups, ungoverned waivers, missing UK notification regimes, supplier SDLC evidence |
| Healthcare HIPAA | Ready with work | BAAs; Aurora TLS |
| US public sector | Not supported | No FIPS, GovCloud or Assured Workloads |
| EU sovereignty | Not supported | No sovereign partitions; US-parent control planes |
| EU GDPR | Ready with work | `global` log buckets by default; noncurrent versions never expire |

## Adopter verdicts (adoption lens)

| Persona | Verdict | Manual steps | First governed estate |
|---|---|---|---|
| Startup (SaaS + small AWS, SOC 2) | Adopt with work; start with the SaaS path | About 25 | SaaS 1 to 2 days; AWS 2 to 3 weeks |
| Fintech, AWS only | Adopt with work; one sandbox apply first | About 30 | 3 to 4 weeks |
| Enterprise, GCP + AWS, 50 teams | Do not adopt as system of record; reference design | 45+ | 6 to 10 weeks |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Profile | Estimate |
|---|---|
| Production estate, both clouds, incl. HCP Terraform Standard | 3,300 to 5,300 |
| Starter estate | 1,450 to 2,050 |

The Route 53 Profile (USD 0.75 per hour per account, checked on the pricing page) is still missing from the repo's cost table. Org-wide GCP Data Access logs (ARC-M1) add unbounded ingestion cost.

## Genuinely strong

- The AWS hub is a correct SRA shape: segmented TGW with appliance-mode inspection, IPAM reservations, central endpoints and a DNS-firewall Profile.
- The member-account `tfc-apply` boundary is unusually thorough. GCP stage identities are bound by workspace ID and run phase, and the org `securityAdmin` is role-conditioned within Google's 10-role limit.
- Plan-time guards encode real API limits (SCP and RCP sizes, `hasOnly` chunking, peering quota, PSC naming, CIDR overlap across clouds).
- Docs are candid: every count, pin, config key and policy-set name the adoption reviewer checked was true; known-gaps names what is unproven.
- Workflows are hardened: SHA-pinned actions, empty default permissions, egress blocked on every job that holds a credential.

## Recommendation

Do not run another round of code-only fixes before changing the approach. Three rounds of fixes have each closed their findings and each exposed as many new ones. The score is now limited by things only these steps can change:

1. **Freeze breaking changes** until a v0.2.0 is cut with a filled sandbox upgrade log. This stops ARC-H9, IAC-2 and ADO-27 from getting worse.
2. **Fund one sandbox apply per cloud.** It settles ARC-C1, IAC-1, ARC-H2, ARC-H3, ARC-H4, the PSC endpoint, the StackSet deny, the endpoint policies, the log sinks and `run.commit_sha` together. Each of these is a guess until then.
3. **Phase 3 owner steps** (decisions O1 and O3): codified rulesets, protected environments, a second maintainer, secret scanning and push protection, a green `main`. These move delivery, compliance and adoption more than any code change.

A short code wave is still worth doing first, because these findings are cheap and high impact: ARC-C1 (perimeter membership), SEC-1 (tighten the two OPA trust policies), SEC-2 (replace `logging.viewer` on the plan identity), ARC-H1 (force Cloud Run `ALL_TRAFFIC` when the proxy is on), ARC-H2 (region precondition), ADO-20 and ADO-21 (scaffolder production prerequisites), and the CODEOWNERS lines in CICD-3.

## Appendix: Medium and Low findings

**Security.** SEC-6 `tfc_admin_guard` does not judge remote-state sharing, `speculative_enabled`, health assessments, `allow_destroy_plan`, notification deletion, `sso_team_id`, or terraform-category variables. SEC-7 app-deploy WIF binds the GitHub environment without a ref. SEC-8 AWS plan-role deny-list gaps (`lambda:GetFunction` and others). SEC-9 non-production PR plans can read upstream control-plane state through the run token. SEC-11 the AWS Config recorder can be narrowed by `tfc-apply` (SCP off by default); GCP Data Access audit configs can be removed by organization-apply. SEC-12 `destroy_guard` does not protect identity anchors (service accounts, WIF pools, IAM roles, OIDC providers, StackSets, OUs). Off by default and not defensible for regulated buyers: `enable_principal_access_boundary`; policy sets below the Standard tier.

**Compliance.** CMP-R5 waivers have no maximum horizon or approver; `egress_alert_only_waived` is a bare boolean; `org_policy_overrides` can drop any constraint. CMP-R6 VUL-05 overclaims GCP patching (no `enable-osconfig` metadata). CMP-R7 notification runbook misses FCA/PRA, UK NIS, NYDFS and the US 36-hour rule (KNOWN). CMP-R8 Aurora does not enforce TLS. CMP-R9 the regulated class can be dropped through `landing_zone_config_path` (SUSPECTED). CMP-R10 no GCP asset inventory export. CMP-R11 copy-vault lock minimum is 7 days. CMP-R12 change evidence off by default; supplier SDLC. CMP-R13 to R17: noncurrent versions never expire; starter also drops Macie and Security Lake; no Security Hub PCI standard; IPv6 `::/0` not denied for SSH and RDP; `global` log buckets.

**Architecture.** ARC-M1 org-wide Data Access logs are unconditional. ARC-M2 the tfc-admin CIDR check ignores extra-region, PSA, proxy and GKE ranges; the example's dev extra region overlaps uat. ARC-M3 AWS hub uses 2 AZs and no AZ IDs in production. ARC-M4 segment isolation only warns. ARC-M5 `destroy_guard` does not protect network-plane resources; the hub peering follows a data-source filter. ARC-M6 run-trigger fan-out. ARC-M7 internal ALB is HTTP with access logs off. ARC-M8 Binary Authorization off in production. ARC-L1 to L4: doc and code mismatches; IPv6; GKE master CIDR inside the on-premises range; service-account ID length limits environment names.

**Terraform craft.** IAC-3 `envs/tfc-admin/main.tf` is 1,723 lines. IAC-4 some suites would pass on a broken module; 12% of runs assert nothing. IAC-5 checkov parse errors are on the files with `type = any`, and known-gaps names the wrong file. IAC-6 hand-kept key allowlists for `any` inputs. IAC-7 Cloud Run and Cloud SQL name validations looser than the API. IAC-8 two config-precedence idioms; `coalesce` ignores an explicit empty string. IAC-9 CHANGELOG contradicts the tfc-admin Terraform version default. IAC-10 lockfiles in leaf modules; provider floor untested. IAC-11 three cross-root read mechanisms.

**Delivery.** CICD-6 gitleaks is not a PR gate and downloads the latest binary. CICD-7 no release-age delay on providers and lockfiles; Dependabot has no cooldown. CICD-8 approver four-eyes and one-person override. CICD-9 the checkov action runs a tag-referenced image. CICD-10 410 checkov suppressions; workflow-level `security-events: write`. CICD-11 release metadata fails open. CICD-12 wildcard egress allowlists, unhashed pip install, tag-pinned hook, CI zizmor skips examples. OpenSSF Scorecard estimate after merge: about 5.5; about 7.5 with live governance codified.

**Adoption.** ADO-24 the break-glass IAM user must exist before the phase-0 stack (SUSPECTED). ADO-25 `TfcProject=<prefix>aws` reads like the org prefix. ADO-26 eight false doc claims, mostly in the GCP onboarding narrative and production-hardening.md. ADO-27 maturity signals (v0.1.0, bus factor 1, 82% AI co-authored, CI red on `main`). ADO-28 cognitive load (367 config keys, 501 root variables, 96 doc pages). ADO-29 the scaffolder writes a 7-day impersonation expiry at scaffold time.

## Status after the code wave (2026-11-13)

This section records what the code wave (`0590e70a..54a8dc6a`) did with the short code wave named in the Recommendation. It does not change the findings above. Scores are not re-estimated here: the next independent re-audit sets them. "Closed in code" means the code and its mock or OPA tests do what the finding asked; nothing below is proven on a real cloud or a real HCP Terraform run.

| Finding | Status | Evidence commits | Still needs the sandbox (or a decision) |
|---|---|---|---|
| ARC-C1 | Closed with residual: an enforced perimeter that holds the team projects is PREVIEW; CMEK keys, image registries and app-deploy WIF identities outside the perimeter need ingress or egress rules | `93638218`, `2982e08e`, `54a8dc6a` | An enforced environment perimeter with team projects that runs app services; read the dry-run violations for those callers |
| SEC-1 | Closed with residual: an unknown trust is exempt in its first-apply run when the role's own module tree creates the OIDC provider or the organization; issuers other than TFC and github.com are checked by shape only; CloudFormation-built trusts are not read; `attribute.repository_id/` and `attribute.project_path/` pass with an advisory | `44d6a170`, `8d467ee4`, `6a777216`, `6cfaad09` | None for the policies (OPA unit tests); one real run of each repo trust and binding with the policy sets attached |
| SEC-2 | Closed in code | `ea87977d`, `11c9052a` | A gcp-organization refresh that shows the custom role `landingZoneLoggingConfigViewer` covers the org sinks, settings, buckets, links and metrics |
| ARC-H1 | Closed with residual: mock-tested only; the JVM and older Node.js releases ignore the proxy variables; GKE workloads get no proxy settings; the hub `secure_web_proxy.certificate_urls` must stay empty | `41e6b956`, `6a834125`, `54a8dc6a` | A Cloud Run revision that reaches an allowlisted FQDN through the proxy, is denied another, and still reaches Google APIs and internal `run.app` URLs |
| ARC-H2 | Closed in code: an environment outside the hub proxy region fails the plan. There is no proxy per extra region | `41e6b956` | None for the check; a regional proxy per extra region is design work |
| ADO-20 | Closed in code. The waiver lives in `config/landing-zone.yaml` (platform-approvable) and can also be set as a tfc-admin workspace variable | `b97306ce`, `54a8dc6a` | None (that a platform approval can set the waiver is in the CICD-2 residual in `docs/known-gaps.md`) |
| ADO-21 | Closed in code | `ce01bb05`, `0e34121d` | None |
| CICD-3 | Closed in code for the listed paths. `envs/tfc-admin`, the workflows and the config files still accept a platform approval alone | `8326cce9` | Real teams and required code-owner review on the default branch (Phase 3) |

**Breaking changes and upgrade notes.** The range adds 7 breaking (`!:`) commits (`git log --oneline 0590e70a..HEAD | grep -c '!:'`); `git log v0.1.0..HEAD --oneline | grep -c '!:'` now counts 64. `UPGRADING.md` has 3,490 lines.

**Tool results at `8326cce9`** (before the two follow-up commits, which change the scaffolder, its test and fixtures, and docs)

- `terraform test`: 3,259 runs in 145 directories, 0 failed.
- `opa test` (OPA 1.22.2): 505 / 505 pass.
- `make ci-quick`, yamllint, markdownlint, commit-check, `validate-all`, `lint` and `security` pass.

**Still open.** The Recommendation's other steps are not done: a breaking-change freeze until v0.2.0 is cut with a filled sandbox upgrade log, one sandbox apply per cloud, and the Phase 3 owner steps (decisions O1 and O3).
