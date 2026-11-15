# Due-diligence audit: enterprise DevOps boilerplate (2026-11-11, HEAD c08f3c4f)

## How this audit was done

Six independent reviewers each took one expert lens. None of them read earlier audit verdicts before forming their own. Each one read the code at `main` after PR #599 merged.

| Lens | Reviewer role |
|---|---|
| Security | Cloud security architect and red-teamer (identity, privilege, trust boundaries) |
| Compliance | SOC 2, ISO 27001, PCI DSS v4.0.1, HIPAA, FedRAMP / NIST 800-53, DORA / NIS2 / GDPR, UK FCA-PRA |
| System design and operability | Platform architect and SRE lead (scale, network, resilience, FinOps) |
| Terraform craft | Public module library maintainer |
| Delivery and supply chain | DevSecOps lead (GitHub Actions, HCP Terraform, SLSA, OpenSSF Scorecard) |
| Adoption | Buyer due-diligence lead, plus three adopter personas |

The lead reviewer re-read the code for every Critical finding marked VERIFIED below.

- **VERIFIED** means the code path was read end to end.
- **SUSPECTED** means the code was read, but the cloud or HCP behaviour was not tested live.
- No `apply` ran. No cloud was touched.

### Gates run locally

| Gate | Result |
|---|---|
| `terraform test` (Terraform 1.17.1, all suites) | **Pass.** 144 directories, 2,578 runs, 0 failed, 10 min 45 s |
| `make fmt-check`, `consistency`, `count-check`, `links`, `docs-check` | Pass (1,414 links, 0 broken) |
| tflint (google, aws, recommended preset) on 15 roots and 10 large modules | 0 issues |
| Provider schema cross-check (google/google-beta 8.10.0, aws 6.72.0, tfe, supabase, vercel) | 0 unknown or deprecated arguments |
| checkov 3.2.490 (no repo config file) | 1,121 passed, 9 failed (5 unique), 178 inline skips |
| GitHub Actions on `main` | **Red.** Security Scan fails (Trivy `AWS-0104` CRITICAL, Checkov). Release fails 9 of 9 (`RELEASE_PLEASE_TOKEN` missing). Sandbox E2E has never succeeded (0 of 5 scheduled runs; 45 skipped). |

## Verdict

**Overall: 5.0 / 10. Not ready for enterprise due diligence as a production foundation.**

The leaf-module code is excellent: it is typed, validated and schema-correct, and it passes 2,578 tests. That is the most visible quality, and buyers will see it first. But due diligence tests three other things, and the repository fails each of them:

1. **The estate does not work as a system.** Three new Critical defects (ARC-1 to ARC-3) break the default data plane on both clouds. AWS spoke VPCs get one CIDR, but their subnets are cut from another. GCP spokes cannot resolve the organization's private DNS zone. AWS deploys only in `eu-west-2`. Mock tests cannot catch any of these. Nothing has ever been applied to a real cloud.
2. **The trust model still leaks.** A platform engineer with routine "plan" access can still read production Supabase credentials (SEC-1). Both plan-time code-execution controls can be bypassed (SEC-2). Nobody reviews changes before they reach `main` (CICD-1).
3. **Several written claims are false.** These include "production-grade" and "fully-tested", "WORM backups with restore testing", "audit-log retention is configurable", and the documented quick-start commands. A buyer's auditor tests claims, so each false claim costs more trust than the gap itself.

The previous audit scored 6.5 across four lenses. This audit adds compliance, operability and adoption lenses and looks at the data plane. The lower score reflects that wider scope. It does not mean the code got worse.

### Scorecard

| Lens | Score | One-line reason |
|---|---|---|
| Security | 6.0 | AWS guardrails are above the SRA baseline. The C1 fix is half done, and plan-time execution controls are bypassable. |
| Compliance readiness | 4.5 | The matrix is candid, but backups, retention, patching and GCP TLS fail an evidence-based audit. It maps no PCI, HIPAA, FedRAMP or DORA controls. |
| System design | 4.8 | The control-plane split is sound. The default data plane breaks on both clouds (ARC-1 to ARC-3). |
| Operability | 4.5 | Adding one AWS account takes about nine sequential applies with manual hand-offs. No RTO or RPO is stated. Everything is single-region. |
| Terraform craft | 7.5 | Better than most public libraries. Production semantics differ by root, and the real config file is never validated. |
| Delivery and supply chain | 4.5 | Workflow YAML is very well hardened. The process controls around it are off: no reviews, unprotected environments, no signing. |
| Adoption readiness | 3.5 | Bus factor 1, never applied, CI red, and several documented happy-path commands fail. |
| Documentation accuracy | 5.0 | Of 34 sampled factual claims, 16 are false. |
| **Overall** | **5.0** | |

Estimated OpenSSF Scorecard: about 5.3 / 10. Code-Review is 0, Signed-Releases is 0, and Branch-Protection is about 3.

### Fitness by industry and persona

| Use case | Verdict | Blocking gap |
|---|---|---|
| Startup, SOC 2 Type II (Vercel + Supabase + a little AWS) | Do not adopt (use `envs/saas` as reference) | You must stand up 8 AWS accounts for "a little AWS". The SaaS controls are too thin for SOC 2 (ADO-9). |
| Mid-size fintech, AWS only (PCI DSS) | Adopt with work, after a 4 to 6 week sandbox proof | ARC-1, ARC-3, CMP-1, CMP-3. No cardholder-data environment segmentation. |
| Global enterprise, GCP + AWS, 50 teams | Do not adopt as the foundation | No multi-team tenancy (ADR 0015 is Proposed). No IdP integration. No EKS. Bus factor 1. |
| Retail, media, telecom (general) | Ready with work | GCP TLS minimum (CMP-5), backups (CMP-1) |
| Banking: DORA, FCA-PRA, SOX ITGC | Not supported | No immutable cross-region backups. No regulatory notification timelines. No third-party register. No author-not-approver control. |
| Healthcare: HIPAA, HITRUST | Ready with work (heavy) | Retention fixed at 365 days (CMP-2). No BAA guidance for Supabase or Vercel. GCP CMEK and WORM are opt-in. |
| US public sector: FedRAMP, CJIS, IL4/5 | Not supported | No Assured Workloads. GovCloud is untested. No FIPS endpoints. Retention is below OMB M-21-31. |
| EU sovereignty | Not supported | No sovereign controls. The ARN regex rejects the `aws-eusc` partition. SaaS residency is not enforced. |
| AI/ML workloads | Ready with work | No Vertex, Bedrock or SageMaker guardrails. No data classification is enforced. |

## Part 1: Critical findings (fix before any due diligence)

| ID | Finding | Status | Tracked in known-gaps? |
|---|---|---|---|
| ARC-1 | AWS hub-attached spoke VPCs take a `/16` from IPAM in netmask mode (`envs/aws/workload/variables.tf:67`, `modules/aws/network/vpc/main.tf:90-92`), but subnets are always cut from `var.cidr_block` = `10.72.0.0/16` (`vpc/main.tf:24`). The hub VPCs are not registered in the pool. The first workload apply gets an arbitrary block, and subnet creation fails with `InvalidSubnet.Range`. | VERIFIED (IPAM pick SUSPECTED) | No |
| ARC-2 | GCP spokes cannot resolve the internal root zone. `internal-root` is visible only to `dns-vpc-core` (`modules/gcp/stages/network-hub/main.tf:185-203`). Each spoke's DNS peering zone targets the hub VPC (`envs/gcp/workload/main.tf:108-117`), which has no zone for that domain. Every internal lookup returns NXDOMAIN. `network-topology.md:178-193` documents a chain that does not exist. | VERIFIED | No |
| ARC-3 | AWS deploys only in `eu-west-2`. `availability_zones` defaults to `eu-west-2a/b` in `envs/aws/network`, `stages/network-hub` and `stages/workload`. `envs/aws/workload` has no AZ input at all. With `org.regions.aws: us-east-1`, every subnet fails. AZ names (not AZ IDs) are used across accounts. | VERIFIED | No |
| SEC-1 | The C1 residual. `secret_bearing_projects` covers only tfc-admin and `saas` (`envs/tfc-admin/main.tf:807`). Production workload workspaces that bridge SaaS secrets hold the `saas-outputs-reader` `TFE_TOKEN`. The platform team keeps `runs = plan` there. One plan with unreviewed code reads the token. This covers CLI plans and PR speculative plans, then `supabase_service_role_key` and the database password for production. | VERIFIED (HCP behaviour as documented) | No |
| SEC-2 / CICD-2 | Both plan-time code-execution controls can be bypassed. The CI grep (`scripts/check-consistency.sh:177-181`) needs quoted labels and `.tf` files. It misses `provisioner local-exec` with bare labels, `*.tf.json`, and `registry.terraform.io/hashicorp/external`. The OPA allowlist regex `(^\|/)supabase/vault-secrets/?$` matches `./evil/supabase/vault-secrets` and `git::https://attacker/x.git//supabase/vault-secrets`. OPA also runs after the plan, so plan-time exfiltration has already happened. Third-party providers and endpoint overrides are not covered. | VERIFIED | No (audit marks C1 and M19 Fixed) |
| CICD-1 | No change is reviewed. The live branch protection has no required reviews and `enforce_admins: false`. No rulesets exist. All 30 of the last 30 PRs were authored and merged by one account with no review. PRs #591 to #599 merged with failing required checks. Live required checks omit `Validation Summary`. | VERIFIED | Partly (as an operator to-do) |
| CMP-1 | "WORM backups with restore testing" is false in practice. Member-account vaults are unlocked and use the AWS-managed key (`modules/aws/stages/organization/backup_role.tf:15-24`). Nothing copies to the locked central vault. Restore testing selects only the central vault and only EBS (`modules/aws/backup/backup-vault/main.tf:66-80`), so it tests an empty vault. The matrix (BCK-01, BCK-02) and `landing-zone-conformance.md:30` still claim protection. | VERIFIED | Partly (A5, rated Medium) |
| CMP-2 | Audit-log retention cannot be changed from either cloud's root. `envs/gcp/organization` never passes `audit_log_retention_days`. AWS `retention_days` is fixed at 365. `SECURITY.md:63` and the control matrix tell the operator to change it for PCI, HIPAA and FedRAMP. | VERIFIED | No |
| ADO-1 | `README.md:7` says "Production-grade", and `README.md:38` says "fully-tested". `docs/runbooks/production-hardening.md:5` says the repo "has never been applied". | VERIFIED | Yes, but the README contradicts it |
| ADO-2 | The documented workload plan, `make plan-gcp-workload APP_VARS=examples/dev.tfvars.example` (README:313, QUICK_START:397, :424), fails. That file hard-codes `terraform_admin_email`, `tfc_organization = "acme-tfc"` and `project_prefix = "acme"`. Explicit variables beat the config file, so the plan impersonates a service account that does not exist. | VERIFIED | No |
| ADO-3 | `aws-bootstrap.md` step 2 (`:255`) runs `terraform apply` from the CLI against `aws-organization`, which is VCS-connected. HCP Terraform rejects CLI applies on VCS-connected workspaces, so the first AWS apply fails. Correction: `aws-bootstrap.md:146` already documents local mode, so only the step 2 command is wrong. | SUSPECTED (documented HCP behaviour) | No |
| ADO-4 | QUICK_START (`:315-337`) lists `admin_email`, `organization_admin_groups`, `break_glass_user` and `security_contact_email` as root variables. They exist only inside `gcp_overrides`. TFC ignores an undeclared variable, so the break-glass user and security contact are never set. | VERIFIED | No |

## Part 2: High findings

### Security

| ID | Finding | Evidence |
|---|---|---|
| SEC-3 | GCP admin containment can be removed by the identity it contains. `organization-apply` holds `roles/iam.securityAdmin` on the org and `monitoring.editor` on the project that hosts the guardrail alerts. The escalation is the self-grant of `iam.denyAdmin`, after which it can delete the deny policy. Deleting the alerts only removes detection. With `enable_pam`, `organization-apply` also holds `privilegedaccessmanager.admin`, which is a further path. | `modules/gcp/stages/bootstrap/service_accounts.tf:84,103`; `guardrails/main.tf:68-95` |
| SEC-4 | H3 is only partly fixed. `projects-apply` can still delegate roles that control IAM: `secretmanager.admin`, `cloudkms.admin`, `storage.admin`, `run.admin` and `iam.serviceAccountUser`. It can grant itself read on every production secret. | `modules/gcp/stages/bootstrap/service_accounts.tf:249`, `variables.tf:221-243` |
| SEC-5 | GCP app-deploy WIF trusts every branch of the repo when neither `ref` nor `environment` is set, including in production. AWS always pins one of them. | `modules/gcp/stages/app-services/main.tf:152-162` |
| SEC-6 | The AWS management-account plan role is plain `ReadOnlyAccess` with no data-read deny. `TrustSecurityAndBackup` defaults to `true`, so `aws-security` and `aws-backup` apply as unbounded management-account admin. | `templates/aws/bootstrap/phase0-management.yaml:29-31,79-86` |
| SEC-7 | Viewer, approver and state-backup teams can read full `saas-*` state. Approvers can run a plan on `saas` and read the account-wide `SUPABASE_ACCESS_TOKEN` and `VERCEL_API_TOKEN`. | `envs/tfc-admin/main.tf:743-749,845` |
| SEC-8 | Production VPC-SC perimeters are dry-run by default. Only a warning check flags this. | `modules/gcp/stages/environment/variables.tf:209` |

### Compliance

| ID | Finding | Evidence |
|---|---|---|
| CMP-3 | AWS "OS patching" installs nothing. There is no `AWS-RunPatchBaseline` association or maintenance window. The default OS is Amazon Linux 2, which reached end of life on 2026-06-30. | `modules/aws/ops/systems-manager/main.tf:66-85`, `variables.tf:57-60` |
| CMP-4 | GCP audit storage has no WORM lock and no separation of duties by default, even with the production preset. The checkov skip text says the org sink is "the authoritative tamper-evident copy", but a sink stores nothing. | `cloud-audit-logs/main.tf:77-98`; `examples/presets/prod-gcp-organization.tfvars` |
| CMP-5 | GCP public ingress has no minimum TLS version. No `google_compute_ssl_policy` and no `gcp.restrictTLSVersion` exist, so Google's COMPATIBLE profile (TLS 1.0) applies. | `modules/gcp/stages/environment/main.tf:388-400` |
| CMP-6 | AWS security alerts go to `secops@example.com` by default, with no validation. A test asserts this behaviour. | `envs/aws/security/config.tf:76-79` |
| CMP-7 | Network enforcement passes traffic by default: the VPC-endpoint policy is `Action="*"` and VPC-SC is in dry-run. There is no regulated or cardholder-data zone. GCP flow logs sample 10% and are kept 30 days. Correction: Network Firewall `aws:alert_established` is not a production gap, because `envs/aws/network/config.tf:83` and `modules/aws/stages/network-hub/main.tf:409-423` already fail the plan for alert-only egress in production. | `modules/aws/stages/network-hub/variables.tf:156-159` |
| CMP-8 | GCP has no backup vault. The Cloud SQL `backup_location` default can place backups outside `allowed_regions`. | `modules/gcp/data/cloud-sql/main.tf:129-130` |
| CMP-9 | No regulatory breach-notification procedure exists for GDPR (72 h), DORA (4 h / 72 h / 1 month), NIS2 (24 h / 72 h) or HIPAA (60 days). | `docs/runbooks/incident-response.md` |

### System design and operability

| ID | Finding |
|---|---|
| ARC-4 | The IP plan runs out at about 6 GCP environments and 14 AWS workload accounts per region. The IPAM pool has no allocation rules and is shared org-wide, so any account can drain it. GKE secondary ranges are not in the plan. |
| ARC-5 | The C2 hub-peering fix needs a manual second `gcp-network-hub` run per environment, which `add-environment.md` does not mention. Two roots derive the spoke name separately, so a mismatch fails silently. Peering remains the default, with a 25-peering limit and no count validation. |
| ARC-6 | AWS interface endpoints, resolver rules and DNS Firewall serve only the egress VPC. The Route 53 Profile association passes a VPC ARN, which is not a valid profile resource (SUSPECTED apply failure). Spoke traffic to AWS APIs goes through firewall and NAT, which costs data-processing charges. |
| ARC-7 | Onboarding one AWS account takes about nine sequential steps with two manual hand-offs. tfc-admin (1,440-line `main.tf`) and aws-organization are single-state choke points. |
| ARC-8 | Everything is single-region. No RTO or RPO is stated anywhere. Aurora and Backup have no cross-region copy. |
| ARC-9 / ADO-7 | Application services live in platform workspaces. All teams in one environment queue behind one state that also owns the network. |
| ARC-10 | The `starter` profile gives hub-attached spokes no egress. |

### Delivery and supply chain

| ID | Finding |
|---|---|
| CICD-3 | Policy sets are VCS-sourced from `main`. A PR that deletes `destroy_guard.rego` takes effect on merge. CODEOWNERS uses `@your-org/*` placeholders, so GitHub ignores it. |
| CICD-4 | GitHub environments have no protection rules and no branch policy, although workflow comments say they are branch-restricted. Three environments do not exist yet, and GitHub auto-creates them unprotected on first use. |
| CICD-5 | Four-eyes on TFC applies is team-based. An approver can author, merge and confirm their own change. Production speculative plans are off, so no reviewer sees a plan before merge. |
| CICD-6 | Promotion is not artifact promotion. Every workspace tracks `main`, and modules are relative paths. A module change reaches dev and prod at the same commit. |
| CICD-7 | `v0.1.0` is a lightweight, unsigned tag. 291 of the last 300 commits are unsigned. There is no SBOM or provenance attestation, and no tag ruleset. The apply workflow fails open on commit match (`terraform-apply.yml:166-170`). |

### Terraform craft

| ID | Finding |
|---|---|
| IAC-1 | "Production" is decided three ways. GCP roots treat an omitted `is_production` as false. tfc-admin and aws-network match the key `prod`/`production`. `envs/gcp/workload/main.tf:145` matches the substring `prod`, which also matches `nonprod`. An env keyed `prod` without the flag gets the approver gate in TFC but no admin containment and no VPC-SC precondition on GCP. |
| IAC-2 | The fork's real `config/landing-zone.yaml` is never schema-validated (`Makefile:333-336` checks only examples and fixtures). Terraform reads it through `try()`, so a typo such as `is_prodution: true` silently becomes the default. |

### Adoption

| ID | Finding |
|---|---|
| ADO-5 | `aws-bootstrap.md` never mentions `spoke_attachments`, so a fresh AWS estate has workload VPCs with no routing. |
| ADO-6 | `gcp-guardrails` is missing from the GCP stand-up docs. The scaffolder sets `break_glass_group`, so the operator believes containment is on, but the deny policy is never applied. |
| ADO-8 | No IdP integration: no SCIM to IAM Identity Center and no Workforce Identity Federation. |
| ADO-9 | The SaaS layer has no Supabase PITR, network restrictions or SSL enforcement, and no Vercel deployment protection or log drains. |
| ADO-10 | Bus factor is 1: 690 of 712 commits come from one person. 78% of commits carry an AI co-author trailer. 341 commits landed in the last 30 days, and a breaking change landed 3 days after `v0.1.0`. |
| ADO-11 | CI is red on `main`. Correction: the live README badges are accurate. The CHANGELOG and README release-please text is what misleads. |
| ADO-12 | Common enterprise capability is missing: EKS, Lambda, data platform, Vertex/Bedrock, Azure, service mesh, Backstage templates, AWS CUR. |
| ADO-13 | The minimum HCP Terraform tier and the resources-under-management cost are not stated. The security model needs teams and policy sets, which the Free tier does not provide. |

## Part 3: Medium and Low findings (summary)

- **Security:** SEC-9 (the tfc-apply boundary does not cover `UpdateAssumeRolePolicy`, `CreatePolicyVersion` or group-policy actions on brownfield roles); SEC-10 (one person can bind `principalSet://…/*`; correction: the wildcard binding needs `setIamPolicy` on the service account, not `workloadIdentityPoolAdmin`); SEC-11 (`TFC_TOKEN_DRIFT` is a plan-capable token created by hand); SEC-12 (`npm ci` sees `POSTGRES_URL`; KMS alias retargeting is not denied).
- **Compliance:** CMP-10 (the tag policy cannot require tags; no data-classification key on AWS); CMP-11 (Supabase and Vercel regions are not checked against `allowed_regions`; no subprocessor register, BAA or exit plan); CMP-12 (GCP keys sit in the admin project with SOFTWARE protection); CMP-13 (no TFC audit-trail export); CMP-14 (`Developer` = PowerUserAccess can be assigned to prod); CMP-15 (no FIM; SCC tier not activated; correction: SCC tier activation has no Terraform API, so the fix is documentation only); CMP-16 (no MFA control for Identity Center or Google; correction: the AWS console-without-MFA alert exists at `security-notifications/main.tf:61` (CIS 4.2), and the remaining gap has no Terraform API); CMP-17 to CMP-20 (stale matrix citations, stale SECURITY.md lines, wrong PCI retention text, a mixed EU/US region default in the stage).
- **Architecture:** ARC-11 (prod and non-prod route to each other through inspection); ARC-12 (GCP hybrid: DEFAULT BGP advertisement, no DNS forwarding); ARC-13 (an enforced prod VPC-SC perimeter blocks the TFC service accounts); ARC-14 (drift and state backup depend on GitHub cron, with a hand-kept workspace list and two drift paths; correction: HCP health assessments are on by default, at `envs/tfc-admin/variables.tf:173` and `main.tf:1172`); ARC-15 (no TGW, firewall or VPN alarms on AWS); ARC-16 (Cloud Run has no probes, `min_instance_count = 0` in prod, ECS autoscaling off); ARC-17 (cost-allocation tags not enforced); ARC-18 to ARC-21 (ARC-18: the SCP quota is 10,240 characters and the RCP quota 5,120 (AWS docs, checked 2026-11-12). The defect was the RCP asserted against 10,240; fixed in 6bbcffcc (per-type plan precondition; worst case scp-deny-tamper 6,485, rcp-data-perimeter 2,811); and ARC-19 to ARC-21: per-zone GCP subnets; no IPv6; resolver endpoints always created, about USD 365 per month).
- **Delivery:** CICD-8 to CICD-18 (live required checks out of date; secret scanning and push protection off on a public repo; OPA skips unknown values; `destroy_guard` misses backup vaults, Object Lock, BigQuery datasets, DNS zones and registries; harden-runner in audit mode on secret-holding jobs, where `release.yml` and `drift-detection.yml` already block egress (CICD-12); CICD-16 is valid but Low, because only a writer can create a branch; tool versions outside update automation; `make ci` not at parity with CI).
- **Terraform craft:** IAC-3 (no per-module versioning); IAC-4 (9 `any` inputs with hand-kept key allowlists; the 3 network-hub inputs have no allowlist at all); IAC-5 (no real-cloud evidence); IAC-6 (Renovate has never run, so 275 lockfiles go stale); IAC-7 (oversized roots); IAC-8 (four spellings of deletion protection; 112 booleans outside the `enable_`/`create_` convention); IAC-9 (tfc-admin silently drops dynamic-credential variables when a contract output is renamed); IAC-10 to IAC-14 (polish).
- **Adoption:** ADO-14 to ADO-28 (the scaffolder invents group names and reports "ok"; `make install` misses `check-jsonschema`; the checklist omits the aws CLI and `gh`; there is no minimum AWS footprint, so every estate creates 8 accounts against a default quota of 10 (ADO-20; correction: the first stand-up fits the quota at 9 of 10 accounts, and the third workload account fails); most presets need `-var-file`, which VCS-driven runs never see; README module tables and root counts are wrong (ADO-23; correction: `README.md:42` is correct, and only the mermaid diagram and `bootstrap.md:13` are wrong); stale VPN docs; no AWS `make plan-*` targets; no `gcp-guardrails` deploy tag; the security contact is not live).

## Part 4: Estimated idle cost (USD per month, single region, list prices, no workloads)

| Profile | AWS | GCP | Total |
|---|---|---|---|
| Default (`production`) | about 1,450 to 2,000 | about 100 to 200 | **about 1,550 to 2,200** |
| `starter` (spokes currently have no egress, ARC-10) | about 690 to 900 | about 80 to 150 | **about 770 to 1,050** |

Each extra AWS workload account adds about USD 60 to 150 per month, plus data charges. At 50 accounts and 10 GCP environments, the estate costs about USD 5,000 to 10,000 per month before any workload runs. Gating the resolver and interface endpoints and the second NAT would bring a real starter estate to about USD 250 to 400.

## Part 5: What holds up

- AWS org-level preventive controls: the deny-tamper SCP, an RCP with TLS enforcement, centralized root management, and a region SCP that exempts only break-glass.
- AWS logging and detection: an org CloudTrail with log file validation and KMS; an Object Lock COMPLIANCE log archive; GuardDuty with runtime and malware protection; Security Hub (FSBP, CIS v3, NIST r5); Inspector; Macie.
- GCP identity: WIF bindings use workspace ID plus run phase; per-stage plan and apply SAs. KMS tag planting (an earlier High) is closed.
- Terraform craft: 0 schema errors against the locked providers, 1,323 validations, 100 `moved` blocks, write-only arguments and ephemeral values for secrets, and a CI-enforced UPGRADING guide.
- GitHub Actions YAML: 100% SHA-pinned, `permissions: {}` by default, no `pull_request_target`, OIDC everywhere, and a fail-closed `Validation Summary`.
- OPA policy tests exercise deny paths: `destroy_guard` has 39 tests, and `tfc_admin_guard` has 42.

## Part 6: Remediation plan, in order

**Wave 1: make the claims true (days, code and docs only)**

1. Retitle README as a "reference landing zone, pre-production". Remove "fully-tested" and the misleading badges (ADO-1, ADO-11).
2. Fix the quick-start paths: ADO-2 (strip identity keys from `dev.tfvars.example`), ADO-3 (queue the first run in TFC), ADO-4 (generate the variable reference), ADO-5, ADO-6.
3. Correct the control matrix, `SECURITY.md` and `landing-zone-conformance.md` overclaims: CMP-1, CMP-2, CMP-4, CMP-17, CMP-18.

**Wave 2: fix the Critical code defects (one to two weeks)**

1. ARC-1: default to explicit-CIDR IPAM allocation, and register the hub CIDRs in the pool.
2. ARC-2: point spoke DNS peering at the DNS-anchor VPC, or add the hub VPC to the zone's visibility, with a plan assertion.
3. ARC-3: use AZ IDs from a config key, or from `data.aws_availability_zones`.
4. SEC-1 and SEC-7: derive `secret_bearing_projects` from every workspace that holds a sensitive variable, and push the SaaS bridge from `saas-<name>`.
5. SEC-2: anchor the OPA allowlist to the exact path. Parse HCL and JSON instead of grepping. Add a provider allowlist. Document OPA as an apply-time control only.
6. CMP-1 and CMP-2: add Backup `copy_actions` to a locked vault, point restore testing at real recovery points, and expose retention through config.
7. IAC-1 and IAC-2: one production rule (a required boolean), and schema-validate the real config file.

**Wave 3: prove it (weeks; needs funding)**

1. Codify GitHub governance with the `integrations/github` provider: a ruleset with required review, `enforce_admins`, environments, tag protection, secret scanning (CICD-1, CICD-3, CICD-4, CICD-7).
2. Turn CI green on `main`, and set `RELEASE_PLEASE_TOKEN`.
3. Fund one sandbox per cloud. Run `sandbox-e2e.yml` with two environments and two AWS workload accounts in a non-`eu-west-2` region. Make a green nightly run a release criterion. This step is the only thing that changes the "never applied" verdict.
4. Add a second maintainer with merge rights, and enforce author-not-approver on production applies (CICD-5).

**Wave 4: widen the market (quarters)**

1. Per-team application stacks (ADR 0015), IdP integration, EKS, a second region with stated RTO and RPO, framework mappings for PCI, HIPAA and DORA, and a SaaS hardening layer.

After Waves 1 and 2, the reviewers expect the score to reach about 6.5. After Wave 3, they expect about 8. Wave 3 is the gate for any claim of "production-grade".

## Corrections after planning (2026-11-11)

Planners read the code behind each finding. These lines record every change made to this report. Finding IDs are unchanged.

- CMP-7: the production egress gate already exists, so alert-only Network Firewall egress is not a production gap. Evidence: `envs/aws/network/config.tf:83`, `modules/aws/stages/network-hub/main.tf:409-423`.
- CMP-16: the AWS console-without-MFA alert exists. Identity Center MFA and Google 2-Step Verification have no Terraform API. Evidence: `modules/aws/security/security-notifications/main.tf:61` (CIS 4.2).
- CMP-15: SCC tier activation has no Terraform API, so the fix is documentation only. Evidence: `docs/moai/plans/2026-11-11-dd-score-max/README.md`.
- SEC-1: PR speculative plans also leak the token, not only CLI plans. Evidence: `envs/tfc-admin/main.tf:807`.
- SEC-3: the escalation is the self-grant of `iam.denyAdmin`. Deleting alerts only removes detection. With `enable_pam`, `organization-apply` holds `privilegedaccessmanager.admin`. Evidence: `modules/gcp/stages/bootstrap/service_accounts.tf:84,103`.
- SEC-10: the wildcard binding needs `setIamPolicy` on the service account, not `workloadIdentityPoolAdmin`. Evidence: `docs/moai/plans/2026-11-11-dd-score-max/ws3-trust-model.md`.
- IAC-4: 9 `any` inputs, not 11. The 3 network-hub inputs have no allowlist at all. Evidence: `docs/moai/plans/2026-11-11-dd-score-max/ws1-truth-and-config.md`.
- ADO-3: `aws-bootstrap.md:146` already documents local mode. Only the step 2 command is wrong. Evidence: `docs/runbooks/aws-bootstrap.md:146,255`.
- ADO-11: the live badges are accurate. The CHANGELOG and README release-please text misleads. Evidence: `CHANGELOG.md`, `README.md`.
- ADO-20: the first stand-up fits the quota (9 of 10 accounts). The third workload account fails. Evidence: `docs/moai/plans/2026-11-11-dd-score-max/ws1-truth-and-config.md`.
- ADO-23: `README.md:42` is correct. Only the mermaid diagram and `docs/runbooks/bootstrap.md:13` are wrong. Evidence: `README.md:42`.
- CICD-12: `release.yml` and `drift-detection.yml` already block egress. Evidence: `.github/workflows/release.yml`, `.github/workflows/drift-detection.yml`.
- CICD-16: valid but Low, because only a writer can create a branch. Evidence: `docs/moai/plans/2026-11-11-dd-score-max/ws5-governance-and-proof.md`.
- ARC-14: HCP health assessments are on by default. The remaining gap is the hand-kept GitHub drift list and two drift paths. Evidence: `envs/tfc-admin/variables.tf:173`, `envs/tfc-admin/main.tf:1172`.
- ARC-18: the SCP quota is 10,240 characters and the RCP quota 5,120 (AWS docs, checked 2026-11-12). The defect was the RCP asserted against 10,240; fixed in 6bbcffcc (per-type plan precondition; worst case scp-deny-tamper 6,485, rcp-data-perimeter 2,811). Evidence: `modules/aws/governance/organization-policy/tests/plan_assertions.tftest.hcl`.
- "CI unfunded": this report does not state it, but the owner premise is contradicted. GitHub Actions ran 9 workflows on `c08f3c4f`. The cost question is HCP Terraform and the sandbox clouds. Evidence: `docs/moai/plans/2026-11-11-dd-score-max/ws5-governance-and-proof.md` (D10).
- Formatting: the regex in SEC-2 / CICD-2 now escapes `|` inside the table cell (markdownlint MD056).

## Status after Phase 1 (2026-11-12)

The findings above are not rewritten. This table records where each Critical stands after Phase 1 of [the remediation plan](../moai/plans/2026-11-11-dd-score-max/README.md). "Closed in code" means the change is in the repository and the mock tests pass. The sandbox has not proved any of it yet; [known-gaps](../known-gaps.md) lists what the sandbox must show.

| Finding | Status | Evidence commits | What still needs the sandbox |
|---|---|---|---|
| ARC-1 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | e048a0e5, 773bbb10, c46cd8a6, 7552344e | A plan of each `aws-workload-<env>` against its real state shows no VPC change, and a real explicit-CIDR IPAM allocation. |
| ARC-2 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | 081741f7 | A GCP spoke resolves the internal root zone through the DNS peering zone. |
| ARC-3 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | afdfd566, 2ae3ae98 | A real apply of the AWS network and workload roots in a region other than `eu-west-2`. |
| SEC-1 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | c413fc96, 471580f9 | An HCP Terraform run shows the platform team has `runs = read` and no speculative plan on secret-bearing workspaces. |
| SEC-2 / CICD-2 | closed with residual (OPA runs after the plan; the CI gate runs the PR's own copy; credential-file arguments are not checked) | 6e96972c, 2ebfbd5d, 662c2f88, 80904327, 01b380b0, 1e60440a, 2b10b687 | A real plan with the policy set attached, and a CODEOWNERS review that covers the policy files and the gate script. |
| CICD-1 | open, deferred to Phase 3 (needs owner decisions O1 and O3: GitHub organization and a second maintainer) | none | Branch protection or rulesets with required reviews on the real repository. |
| CMP-1 | closed as opt-in (default unchanged by owner decision D3; production scaffold turns it on) | fa272f03, 8db40b86, e3ee13cc, 2a083476, 65e66bc7, ee8e14c8, f33eb411 | A real copy job, a restore test and a vault notification in a sandbox organization. |
| CMP-2 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | 592eb803, 6f970724, b2ef36f3 | A real apply that sets the GCP audit bucket and the AWS log-archive Object Lock default from the config value. |
| IAC-1 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | 76c5acda, cda9ac25 | A tfc-admin plan against a real HCP Terraform organization. |
| IAC-2 | closed in code (mock-tested; sandbox proof pending, see known-gaps) | 16504431, 0b06e492 | None beyond a CI run on a fork with a real `config/landing-zone.yaml`. |
| ADO-1 to ADO-4 | closed in Phase 0 | Phase 0 commits up to 5da21f7a | None. |
| New Critical found in Phase 1: the GCP delegated folder IAM grant used one `hasOnly()` condition with more than the 10 roles Google allows | closed in code (mock-tested; sandbox proof pending, see known-gaps) | 78b16978 | A real `gcp-organization` apply binds every chunk, and a `gcp-projects` apply grants the workload and network roles. |
| ARC-18 | closed in code | 6bbcffcc | None. |

## Status after Phase 2 (2026-11-12)

Phase 2 fixed the High and Medium findings in code. Every item below is mock-tested only; the sandbox proof for each is listed in [known gaps](../known-gaps.md). Statuses: closed in code; closed as opt-in (the control exists but is off by default or tied to the regulated class); closed with residual (a documented remainder); open.

| Finding | Status | Evidence |
|---|---|---|
| SEC-3 | closed with residual (PAM, principal access boundary and alert-deletion paths in known gaps) | 477dfe0a |
| SEC-4 | closed with residual (infrastructure roles such as compute.admin stay delegable) | ba9432de, 34114e47 |
| SEC-5 | closed in code | 62973bf2 |
| SEC-6 | closed in code (operator updates the phase-0 stack) | 8fd70cb5 |
| SEC-7 | closed with residual (SaaS secrets stay in `saas-*` state, a provider limit) | 4fb91e28, cd47a75e |
| SEC-8 | closed in code (time-boxed waiver) | dcc0863a, a4d9c923 |
| SEC-9 | closed in code (opt-out flag) | 9e07c1a5 |
| SEC-10 | closed with residual (workload SAs keep workloadIdentityPoolAdmin) | d4225640 |
| SEC-11 | closed with residual (token made by hand; secret-bearing workspaces rely on health assessments) | c4af2f78, a217bbd4, 5e3610f4 |
| SEC-12 | closed in code | a49d0536, 9ccfa83b, 9e07c1a5 |
| CMP-3 | closed in code | efe97c28, d7c37c8b |
| CMP-4 | closed as opt-in (required for regulated; production warns) | 3f8e1561 |
| CMP-5 | closed in code | 1f5fbf35, 8dc2f6e5 |
| CMP-6 | closed in code (non-production warns) | 6025f937, 1d9f1344 |
| CMP-7 | closed as opt-in (regulated class; the resource-org endpoint mode is PREVIEW) | 9f45fa29, 395fb63a |
| CMP-8 | closed in code (region pin); vault opt-in or regulated, PREVIEW | 34114e47 |
| CMP-9 | closed in docs and config | 8674fd0a, e76f67d6 |
| CMP-10, ARC-17 | closed in code (GCP); AWS required-tag reporting opt-in | d89ddfc1 |
| CMP-11 | closed in code | 9ef5ff35 |
| CMP-12 | closed as opt-in (HSM opt-in; CMEK required for regulated) | 9981e815 |
| CMP-13 | closed as opt-in (needs the token, the environment and Standard or Premium) | cdb77124 |
| CMP-14 | closed in code | e0ba1e7c |
| CMP-15, CMP-16 | closed in docs (no Terraform API) | 0b9f49b6 |
| CMP-20 | closed with residual (organization stage `allowed_regions` default) | 9d805ef9 |
| ARC-4 | closed as opt-in (pool growth and OU share; GKE ranges documented, not provisioned) | 9c3fd7ac, cd4703f9 |
| ARC-5 | closed with residual (second gcp-network-hub run stays manual, documented) | b31d1d59 |
| ARC-6, ARC-21 | closed in code (spoke traffic to endpoints stays inspected, a DECISION item) | 40192b15, 2c07f8bb, 0fa8fe3e, a55976b4 |
| ARC-8 | closed with residual (RTO/RPO stated as design targets; still single region) | 9da7bda3 |
| ARC-10 | closed in code | 87961023 |
| ARC-11 | closed in code | d1fc970f, 98a2a02c |
| ARC-12 | closed in code | 9e3066c9, e16f85e8 |
| ARC-13 | closed in code | a4d9c923 |
| ARC-14 | closed with residual (GitHub fallback list) | c4af2f78, a217bbd4, 5e3610f4 |
| ARC-15 | closed with residual (no Network Firewall alarm, reasoned in known gaps) | b0804b6a |
| ARC-16 | closed in code | 4e3ee57a, 43177c96 |
| CICD-10, CICD-11, CICD-12 | closed in code | 304cbd30, 3e04b888, b3c9f5f0 |
| CICD-13, IAC-6 | closed as opt-in (Renovate app not installed; the heartbeat fails on schedule until it is) | 25697446 |
| CICD-16, CICD-18 | closed in code | 339f0d21 |
| CICD-17 | closed with residual (attestation, no admission enforcement) | e49c982f |
| IAC-3 | closed with residual (one SemVer for all modules, by policy) | 2558a84b |
| IAC-4 | closed in code | 201451f4 |
| IAC-8 | closed for deletion-protection names only | b94fb051 |
| IAC-9, IAC-10, IAC-11, IAC-14 | closed in code | 8a5601c0, 612d278d, e9f84053, 451e58da |
| ADO-5, ADO-6, ADO-13 to ADO-27 | closed | 589eb907, a8a94b89, b6807416, 4e357a48, 745c40b4, 9039361e, 01210777, 3eebcd39, 9375d6b4, 6b35939b, c96a94ef, 5cac96b5, 3f6f64e6, ea50c61f, 87c9a965, d226f7ee |
| CICD-1, CICD-3 to CICD-9 | open, Phase 3 (needs owner decisions O1 and O3) | none |
| ARC-7, ARC-9, ADO-7 | open, Phase 5 (ADR 0015 and 0016) | none |
| ARC-19, ARC-20 | open (per-zone GCP subnets, IPv6) | none |
| IAC-5, IAC-7, ADO-8 to ADO-12 | open (real-cloud proof, oversized roots, scope and governance; Phases 3 to 5) | none |
