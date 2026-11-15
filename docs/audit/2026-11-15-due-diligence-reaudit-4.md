# Fourth due-diligence re-audit (2026-11-15)

Six new independent reviewers read the code at commit `1ad72af2` (branch `claude/enterprise-devops-audit-949b65`, not merged and not pushed). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md) and re-audits [1](2026-11-12-due-diligence-reaudit.md), [2](2026-11-13-due-diligence-reaudit-2.md) and [3](2026-11-13-due-diligence-reaudit-3.md). They read the code first and the earlier reports only at the end, to label each finding NEW or KNOWN. The lead re-checked the Critical and every NEW High in the code.

This round follows the fixes for re-audit 3's "Fix now" list: the plan-time execution guard (credential keys and values, ephemeral blocks, override files, module sources, file reads), pipefail on every workflow, two-digit GCP regions, and release metadata that fails closed.

## Verdict

**Overall: 6.3 / 10. Up from 5.9 at re-audit 3, the highest score so far, and still 0.9 below the Phase 2 forecast of 7.2.**

The fixes worked. Security rose two points (5.5 to 7.5): the reviewer reproduced no bypass that works without a reviewed malicious commit or an org-owner action. Delivery code rose to 7.0, and Terraform craft to 7.4. The tests caught all six deliberate breakages. What holds the score down:

1. **One Critical in the production AWS network (ARC-1).** The default fail-closed firewall policy very likely drops spoke traffic to the central endpoints, between spokes and to on-premises. Adopters have no config input to add the missing pass rules. The fix advice in `known-gaps.md` cannot work.
2. **Nothing is proven on a real cloud, and the live repository is ungoverned.** Live settings score 2/10. No review is required on `main`. The required checks are stale, so every merge needs an admin bypass. Secret scanning and private reporting are off. The audited HEAD is 239 commits ahead of `main` and on no remote branch.
3. **The breaking-change load keeps growing.** 66 breaking commits since `v0.1.0`, all unreleased. UPGRADING.md has 158 Unreleased entries. The freeze is still not in force.

## Scorecard

| Lens | 2026-11-11 | Forecast | Re-audit 1 | Re-audit 2 | Re-audit 3 | Re-audit 4 | Change from re-audit 3 |
|---|---|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 5.5 | 5.5 | 7.5 | +2.0 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | 6.0 | 6.0 | 5.8 | -0.2 |
| System design | 4.8 | 7.5 | 6.0 | 5.5 | 6.0 | 5.5 | -0.5 |
| Operability | 4.5 | 6.5 | 5.5 | 4.5 | 4.5 | 5.5 | +1.0 |
| Terraform craft | 7.5 | 8.5 | 7.6 | 7.0 | 7.0 | 7.4 | +0.4 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | 4.5 | 5.5 | 7.0 | +1.5 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | 5.0 | 4.5 | 4.5 | 0.0 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | 7.5 | 8.0 | 7.5 | -0.5 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **5.7** | **5.9** | **6.3** | **+0.4** |

Delivery is scored on the branch's code. The reviewer scores the live repository settings 2/10 (3/10 at re-audit 3). Panel-to-panel differences of about 0.5 are within reviewer variance. No compliance code changed in this range, so the compliance and design movements are reviewer variance plus newly found gaps.

## Critical finding (lead-verified)

| ID | Finding | Lead verdict | Status |
|---|---|---|---|
| ARC-1 | Production AWS Network Firewall drops spoke-to-endpoint, east-west and hybrid traffic; adopters cannot add pass rules; the documented workaround cannot work | CONFIRMED in code; packet behaviour SUSPECTED until a sandbox run | KNOWN as SUSPECTED High at re-audit 3; raised to Critical, two parts NEW |

**ARC-1.** The lead checked the following in the code:
- `envs/aws/network/config.tf:121` turns `enforce_egress_allowlist` on for any production profile with a production AWS workload. The `production_egress_enforced` precondition (`modules/aws/stages/network-hub/main.tf:504-517`) then requires `aws:drop_established` and a domain allowlist.
- `home_net_cidrs = [var.top_cidr]` (`network-hub/main.tf:495`) makes `HOME_NET` the whole `10.64.0.0/10` supernet.
- The allowlist group is `generated_rules_type = "ALLOWLIST"` under `STRICT_ORDER` (`modules/aws/network/network-firewall/main.tf:95-118`). AWS documents that it generates pass rules for `$HOME_NET -> $EXTERNAL_NET` only.
- So traffic from a spoke to the hub interface endpoints (sts, kms, logs, ssm), from one spoke to another, or to on-premises (including Resolver DNS) has a destination inside `HOME_NET`. It matches no pass rule and is dropped by the default action.

Two NEW points:
- `envs/` exposes no `network_firewall_suricata_rules` input, so an adopter cannot add pass rules without forking the root.
- `docs/known-gaps.md:1848-1856` says the traffic passes when the allowlist covers `.amazonaws.com`. That cannot work: a domain rule cannot match a destination inside `HOME_NET`, and the stage's own check rejects `.amazonaws.com`.

**Failure scenario:** a default production estate with one production AWS workload. ECS tasks cannot reach the `logs`, `kms` or `sts` endpoints, and every hybrid flow breaks.

**Fix:**
- Ship a default strict-order pass group at a high priority: `pass ip $HOME_NET any -> $HOME_NET any` plus the on-premises and DNS ranges.
- Expose the Suricata rules in config.
- Correct `known-gaps.md` and `config/landing-zone.example.yaml`.
- Add Network Firewall drop alarms (ARC-11).

**Re-audit 3's Criticals are closed.** The security reviewer re-tested the fixes for SEC-1 (credential redirection) and SEC-2 (ephemeral blocks) and found no bypass. The two remaining scanner gaps are below, rated High.

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| CICD-1 | The release job checks out `scripts/verify-run-commit.sh` from the tagged commit and runs it in the step that holds `TFC_TOKEN`; nothing checks the tag is on `main`. A writer can tag a branch commit, forge a "successfully applied" release, and send the token out through `github.com:443` | `.github/workflows/terraform-apply.yml:66-72,164-225` (lead-checked) | VERIFIED, NEW (introduced by the CICD-2 fix) |
| CMP-1 | `compliance_class: regulated` does not imply `is_production`. A regulated non-production environment gets the regulated perimeter, flow-log, Cloud Armor and vault guards, but not the egress proxy gate, the immutable-ID WIF binding, containment or the AWS gateway endpoint policies | `envs/gcp/workload/main.tf:153,352,379` vs `:412-461` (lead-checked) | VERIFIED, NEW |
| SEC-1 | `file()` / `templatefile()` with a variable or local argument passes the scanner; OPA cannot see it. At apply, `file(var.x)` with default `/proc/self/environ` reads the apply runner's credentials | `scripts/check-plan-time-exec.py:537-560` | VERIFIED, KNOWN (accepted residual), severity raised |
| SEC-2 | `terraform_remote_state` with `backend = "remote"` and an attacker `config.hostname` passes both layers and sends the run's token to that host at plan | `policies/opa/no_plan_time_code_execution.rego`, the scanner | VERIFIED, KNOWN, severity raised |
| CICD-2 | Governance documented, not codified. Live required contexts are stale (the bare `Terraform Tests` matrix never reports), so every merge needs an admin bypass, and `Validation Summary` is not required | `docs/guides/BRANCH_PROTECTION.md`; live `gh api` | KNOWN; stale contexts NEW |
| CICD-3 | Label and fork gates live in the editable workflow file; environments are unconfigured, so a modified workflow reaches sandbox OIDC, the drift token and the state-backup token | `sandbox-e2e.yml`, `drift-detection.yml`, `state-backup.yml` | KNOWN, new detail |
| CICD-4 | One overridable set holds `destroy_guard`, `tfc_admin_guard` and `tfc_vcs_run_only`; the separate-person check is by team ID only | `envs/tfc-admin/main.tf:1136-1141,1541-1545` | KNOWN |
| CICD-5 | No release signing, SBOM or provenance; mutable tags | `release.yml` | KNOWN |
| CMP-2 | The regulated class reaches 4 of 15 roots | no references in aws-workload, aws-backup, gcp-projects, gcp-network-hub, saas, tfc-admin | KNOWN (CMP-N2) |
| CMP-3 | GCP flow logs never reach the protected store: the org sink excludes `vpc_flows`, regulated spoke logs sit in a workload-administered dataset, and retention ignores framework floors | `cloud-audit-logs/main.tf:275-283`, `envs/gcp/workload/config.tf:261`, `network-hub/main.tf:99-101` | KNOWN (R1, N1) |
| ARC-2 / ARC-3 / ARC-4 | PSA `/16` chosen by Google and unpinnable; about 62 AWS workload VPCs and 6 GCP environments fit the plan; Cloud Run and GKE share one `/24` | `net-spoke/main.tf:203-211`; `cidr-plan.md`; `tiered-vpc/main.tf:37` | KNOWN |
| IAC-1 | AWS name validations accept trailing and doubled hyphens that the API rejects mid-apply | `rds-aurora/variables.tf:6`, `app-services/variables.tf:10,206` | KNOWN (re-audit 3 IAC-4) |
| ADO-1 / ADO-2 | No real-cloud proof; `main` red; HEAD on no remote; 66 breaking commits unreleased; bus factor 1, 83 % AI co-authored | `git log`, `gh run list` | KNOWN, worse |
| ADO-3 / ADO-4 | No multi-team state model (ADR 0015 Proposed); no EKS, Azure, data or AI/ML services, IdP or SCIM, service mesh, cost export | grep | KNOWN |

## Tool results at `1ad72af2`

| Gate | Result |
|---|---|
| `terraform fmt -check -recursive` | Pass |
| tflint, 15 roots and 10 modules | 0 issues |
| checkov 3.3.17, modules / envs | 1,443 / 872 passed, 0 failed; 1 + 3 parse errors (known) |
| trivy 0.70.0, CI flags | 0 Critical or High |
| `opa test policies/` | 543 / 543, about 360 deny cases, 98.5 % coverage |
| zizmor 1.31.1 offline, 11 workflows + 3 app-delivery files | 0 findings |
| `make examples-plan` (sample of 15) | 15 / 15 |
| 12 sampled suites; 6 deliberate breakages | All pass; 6 / 6 breakages caught |
| `make count-check`, `make links` | Pass (126 modules, 15 roots, 353 suites; 1,687 links) |

## Industry readiness (compliance lens)

| Industry | Verdict | Blocking gap |
|---|---|---|
| Startup SOC 2 | Ready with work | Supplier process evidence (CMP-8); MFA and access reviews are customer steps; no restore evidence |
| Retail / media / telecom | Ready with work | AWS request logs opt-in (CMP-5); GCP flow-log immutability |
| AI/ML | Ready with work | No data-classification enforcement; GCP malware detection needs SCC Premium |
| Fintech PCI DSS v4.0.1 | Ready with heavy work | FIM, CMP-1, CMP-3, CMP-4, CMP-5, per-environment segmentation only |
| Banking DORA / FCA / SOX ITGC | Not supported as shipped | Waiver governance, backup segregation and testing, UK regimes, supplier process evidence |
| Healthcare HIPAA | Ready with work | Transmission security (CMP-4), flow-log retention floor, regulated class missing from aws-backup |
| US public sector | Not supported | No FIPS endpoints, GovCloud or Assured Workloads |
| EU sovereignty | Not supported | No sovereign partition, Assured Workloads, KAJ or EKM |
| EU GDPR | Ready with work | No GDPR article crosswalk; noncurrent versions never expire |

The regulatory notification runbook was re-checked against DORA RTS 2025/301, NIS2 Art. 23, GDPR, HIPAA and SEC rules: every deadline is correct.

## Adopter verdicts (adoption lens)

| Persona | Verdict | Workspaces | Manual steps | Overrides and waivers | Time to first apply |
|---|---|---|---|---|---|
| Startup (SaaS + small AWS, SOC 2) | Do not adopt the whole landing zone; take `envs/saas` | 10 (6 minimum) | About 30 | 1 policy-sets waiver | SaaS 1 to 2 days; AWS 1 to 2 weeks |
| Fintech, AWS only | Adopt with work; sandbox first | 9 | About 32 | 2 to 3 overrides | 2 to 4 weeks |
| Enterprise, GCP + AWS, 50 teams | Do not adopt now; use as a reference | 16 | About 50 | 3 to 4 overrides, 2 production waivers | 4 to 8 weeks |

All three scaffolds plan under mock providers once the documented waivers are set. The fintech PCI variant plans clean.

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Profile | AWS | GCP | HCP Terraform |
|---|---|---|---|
| Production | 1,800 to 2,600 | 50 to 150, plus about 900 per Secure Web Proxy gateway | 700 to 1,400 (resources under management) |
| Starter | 1,050 to 1,250 | 50 to 150 | Same |

NEW: the Route 53 Profile, always created (`route53-resolver/main.tf:151`), costs about USD 548 per month and appears in no repo cost table. It is about half of the starter AWS bill.

## Genuinely strong

- The plan-time execution guard survives a red-team review: per-stage read-only plan identities, credential keys and values checked, ephemeral types allowlisted, and the allowlists defined once and read by both layers.
- Tests check behaviour: six deliberate breakages, six failures. Every module example plans under mock providers.
- Workflows: SHA pins that match upstream tags, `permissions: {}`, pipefail enforced by a check, egress blocked on every credential-holding job.
- AWS: apply boundary with propagation and trust-update lock, plan-role data-read deny, log archive in COMPLIANCE lock, KMS separation of duties.
- GCP: role-conditioned `securityAdmin`, an isolated `denyAdmin` identity, the 10-role `hasOnly` guard, PSC name rules checked against the API.
- Documentation is honest: the Default and PREVIEW columns, the notification runbook, `disaster-recovery.md` targets labelled as targets, and an exact `known-gaps.md`.

## Recommendation

The pattern holds for a fourth round: code-only rounds close their findings, and the next panel finds new ones. But this time no Critical came from the security control, and the one Critical is a network design defect that only a real apply settles.

**Fix now (small, non-breaking):**

1. ARC-1: a default `$HOME_NET -> $HOME_NET` and on-premises pass group, a config input for Suricata rules, corrected docs, and Network Firewall drop alarms.
2. CICD-1: run the verifier from the default branch, give `TFC_TOKEN` only to the curl step, and require the tagged commit to be on `main`.
3. CMP-1: make every production gate key on `is_production || regulated`, or refuse a regulated environment that is not production.
4. SEC-1 and SEC-2: reject non-literal `file()` arguments outside an allowlist, and forbid or pin the remote-state `hostname`.
5. IAC-3: fail the plan when `landing_zone_config_path` is set and the file is missing, so roots stop silently falling back to `eu-west-2`.

**Then, as the last three reports said:** turn the freeze on (`docs/moai/plans/2026-11-13-freeze-and-v0-2-0.md` Part A), push and merge the branch so `main` is the audited code, fund one sandbox apply per cloud (it settles ARC-1, ARC-2, ARC-5 and the IAC-2 class), and take the Phase 3 owner steps: codified rulesets and environments, a second maintainer, a green `main`.

## Appendix: Medium and Low findings

**Security.** SEC-3 CLI/API uploads and speculative plans skip the scanner; no pre-plan run task (KNOWN). SEC-4 `organization-apply` holds org `folderIamAdmin` and can grant itself owner on any folder; principal access boundary off by default (KNOWN). SEC-5 AWS org Config recorders, the Config SCP and CloudTrail delegated admin off by default (KNOWN). Low: SEC-6 non-production WIF name binding; tfc-admin can repoint the guardrails workspace (KNOWN).

**Compliance.** CMP-4 Aurora has no `rds.force_ssl`, the ALB serves HTTP without a certificate, Supabase does not enforce SSL; the HIPAA 164.312(e)(1) crosswalk row overclaims (KNOWN in part). CMP-5 AWS ALB, CloudFront and WAF logs opt-in (KNOWN). CMP-6 a regulated AWS estate can run the log archive in GOVERNANCE mode when `compliance.frameworks` is empty (`envs/aws/security/variables.tf:146-154`, NEW). CMP-7 waivers have no maximum horizon or approver; the AWS egress waiver has no expiry (KNOWN). CMP-8 SECURITY.md names private reporting as the channel but it is off; SECURITY.md:281 claims a Trivy filesystem scan that does not run; CLAUDE.md says `Validation Summary` is the single required check, which the live settings contradict (KNOWN in part). CMP-9 GCP backup vault in the same project and region; no restore evidence (KNOWN). CMP-10 no UK FCA/PRA, GDPR article, NIS2 or SOX crosswalk (KNOWN in part). Low: CMP-11 the GRD-08 row is stale (the EC2 baseline is attached at the root), LOG-02 omits that versioning is off under the lock (NEW). CMP-12 SECURITY.md CMK overclaim, PCI 1.4 cites DP-03, no GCP asset inventory export. CMP-13 thin SaaS controls, `password_min_length` accepts 6.

**Architecture.** ARC-5 GKE control plane defaults to `172.16.0.0/28` and auto-picked ranges (KNOWN). ARC-6 service-team project IDs are `<team>-<4 hex>` with no prefix or environment (`modules/gcp/stages/workload/main.tf:25,46`, NEW). ARC-7 onboarding: about 5 runs and an override per account (KNOWN). ARC-8 an expired production waiver fails every production plan, the incident hotfix included (KNOWN in part). ARC-9 UPGRADING.md 3,541 lines, sandbox upgrade log empty (KNOWN, worse). ARC-10 single region on both clouds (KNOWN). ARC-11 no Network Firewall or attachment alarms in the AWS hub (`network-hub/alarms.tf`, NEW). ARC-12 cost tables omit the Route 53 Profile (NEW), TGW, endpoints and HCP resources under management. Low: ARC-13 `network-topology.md` stale; ARC-14 no IPv6, AWS AZ IDs unset by default, both clouds' routers default to ASN 64512 (ASN point NEW).

**Terraform craft.** IAC-2 four roots (aws-organization, aws-security, gcp-network-hub, gcp-organization) never plan against their real stage (NEW). IAC-3 the config loader fails soft: a missing file decodes to `{}`, wrong types become `null`, and AWS roots fall back to `eu-west-2` (`envs/aws/network/config.tf:105,108`, NEW). IAC-4 a supplied EBS key set as default in every region (SUSPECTED, KNOWN). IAC-5 `modules/vercel/project` uses `nonsensitive()` on whole value maps, so a secret-derived value marked `sensitive = false` reaches the plan and state in clear (NEW; the unsalted fingerprint is KNOWN S4). IAC-6 `envs/tfc-admin/main.tf` 1,743 lines; config loader duplicated in 15 roots (KNOWN). Low: IAC-7 4 of 270 override blocks carry stale outputs (down from 37). IAC-8 checkov parse errors; `known-gaps.md` names the wrong file. IAC-9 `tfc_apply_role_policy_arns` hardcodes the `aws` partition (NEW). IAC-10 `cloud-storage` `name_suffix` has no validation (NEW). IAC-11 `expect_failures` passes on any rule of a variable.

**Delivery.** CICD-6 CODEOWNERS "platform or security" lines leave workflows, tfc-admin, the TFC OIDC baseline and the config file to platform approval alone (KNOWN). CICD-7 checkov runs a tag-referenced image; the pin comment `# v12` is wrong (comment NEW). CICD-8 terraform-docs checked against a checksum from the same release; `check-jsonschema` installed without hashes (NEW). CICD-9 no PR-time plan on production workspaces (accepted). CICD-10 `destroy_guard` does not cover detective controls (KNOWN). Low: CICD-11 drift default list covers dev only (`drift-detection.yml:117`, NEW); CICD-12 workflow-level `security-events: write`; CICD-13 CI zizmor skips `examples/app-delivery`; CICD-14 pre-commit tag pin, a PAT where an App would do; CICD-15 drift step `|| true` (NEW). OpenSSF Scorecard estimate after merge: 5.5 to 6.0; about 7.5 with live governance codified.

**Adoption.** ADO-5 the scaffolder omits the GCP production prerequisites (KNOWN). ADO-6 `ghain-REPLACE_ME` is said to be rejected at plan but is not; no doc says where to get the ID (NEW). ADO-7 `enable_health_assessments` defaults true and ignores `org.tfc.plan` (NEW). ADO-8 tfc-admin's own inputs have no documented home. ADO-9 `--clouds saas` needs both providers. ADO-10 removing a cloud breaks the gates. ADO-11 "a little AWS" means 8 member accounts. ADO-12 the phase-0 break-glass principal must already exist. ADO-13 cognitive load: 453 config properties, 502 root variables, 79 doc pages, 106 OPEN known gaps. Low: ADO-14 scaffold tests plan only `dev` (NEW); ADO-15 `TfcProject=<prefix>aws` misleads; ADO-16 no `terraform login` step; ADO-17 seven false doc claims, three NEW (QUICK_START:178 GitHub WIF, UPGRADING.md:4-5 sandbox log promise, the ADO-6 and ADO-7 wording).
