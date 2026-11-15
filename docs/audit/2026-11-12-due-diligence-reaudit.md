# Due-diligence re-audit after Phase 2 (2026-11-12)

This is Task M3 of the [score plan](../moai/plans/2026-11-11-dd-score-max/README.md). Six independent reviewers read the code at commit `0ecad6d7` (branch `claude/enterprise-devops-audit-949b65`, 152 commits ahead of `main`, not merged). They used the same lenses as the [original audit](2026-11-11-due-diligence-audit.md). They got the code, not the plan, and read the earlier audit only at the end, to label each finding NEW or KNOWN. The lead re-checked every Critical.

## Verdict

**Overall: 6.0 / 10, up from 5.0, but 1.2 below the Phase 2 forecast of 7.2.**

The code is clearly better. Scanners are clean, the docs are mostly true, and the AWS network and identity design is careful. But the re-audit found new defects that mocks cannot catch, and the change-management gap (no review on `main`) is unchanged. Not ready for enterprise due diligence as a production foundation. Defensible as a reference design that a buyer forks and proves in a sandbox.

Three things hold the score down:

1. **Nothing is proven on a real cloud.** One new Critical (ARC-1) would stop the first GCP network apply. Mock tests load the provider schema but not the API rules.
2. **No change is reviewed.** One person writes and merges everything, and CI on `main` is red. Code on this branch cannot fix that. Phase 3 (owner decisions O1 and O3) can.
3. **New trust paths around HCP Terraform.** Fixing the known paths exposed others: unreviewed applies through API uploads, and an admin guard that ignores agent pools, VCS branches and run variables.

## Scorecard

| Lens | 2026-11-11 | Forecast after Phase 2 | Re-audit | Change from 2026-11-11 | Against forecast |
|---|---|---|---|---|---|
| Security | 6.0 | 8.0 | 6.0 | 0.0 | -2.0 |
| Compliance readiness | 4.5 | 7.0 | 6.0 | +1.5 | -1.0 |
| System design | 4.8 | 7.5 | 6.0 | +1.2 | -1.5 |
| Operability | 4.5 | 6.5 | 5.5 | +1.0 | -1.0 |
| Terraform craft | 7.5 | 8.5 | 7.6 | +0.1 | -0.9 |
| Delivery and supply chain | 4.5 | 6.0 | 5.0 | +0.5 | -1.0 |
| Adoption readiness | 3.5 | 5.0 | 4.5 | +1.0 | -0.5 |
| Documentation accuracy | 5.0 | 9.0 | 7.0 | +2.0 | -2.0 |
| **Overall (mean)** | **5.0** | **7.2** | **6.0** | **+1.0** | **-1.2** |

Seven of eight lenses land more than 0.5 below the forecast. Plan Step 4 therefore applies: the gaps below become tasks before Phase 3 (see [Gap tasks](#gap-tasks-before-phase-3)).

### Why the forecast missed

- **The forecast assumed the known findings were the whole list.** About half of the re-audit's High and Critical findings are NEW. Fresh reviewers looked at areas the first audit did not reach (PSC naming, StackSets, agent pools, gateway endpoint policies, GCP log sinks).
- **Security stayed at 6.0.** The Phase 1 and 2 fixes closed the first audit's paths. The reviewer found an equal number of new ones in the HCP Terraform layer and the AWS management account.
- **Documentation accuracy reached 7.0, not 9.0.** 32 of 40 sampled claims are true, and the count and link gates pass. The false ones cluster in the quick start and AWS bootstrap, which every adopter reads first.

## Critical findings (lead-verified)

| ID | Finding | Lead verdict | Status |
|---|---|---|---|
| ARC-1 | The GCP Private Service Connect endpoint name breaks Google's rule, so the hub and every environment network apply fail | CONFIRMED | NEW |
| SEC-1 | An approver alone can apply code nobody reviewed on control-plane workspaces | PLAUSIBLE (needs one HCP Terraform test) | KNOWN in part |
| CICD-1 | No change is reviewed before it reaches `main` | CONFIRMED (live settings) | KNOWN, Phase 3 |

**ARC-1.** `modules/gcp/stages/net-hub/main.tf:175-182` and `modules/gcp/stages/net-spoke/main.tf:203-211` name the endpoint `"${var.network.name}-psc"` (for example `hub-vpc-core-psc`). Both are on by default. Google's documentation (checked 2026-11-12) says: "The name must be a string of 1-20 characters, containing only lower-case letters and numbers" and "must start with a letter". The forwarding rule fails at the first real apply. The module also reserves the address with neither an IP nor an internal range (`modules/gcp/network/private-service-connect/main.tf:33-43`); Google needs one of the two. Fix: derive a compliant name with a validation, require an address or internal range per environment, and prove it in the sandbox.

**SEC-1.** `envs/tfc-admin/main.tf:782-788` gives the approvers team `runs = "apply"` on every control-plane and production project (`:945-950`). The security team has the same on guardrails (`:765-771`). The CLI refuses `terraform apply` on a VCS-connected workspace, but the API accepts an uploaded configuration version. An approver could upload code, queue a run and confirm it, with no pull request, CODEOWNERS or plan-time gate seeing it. No policy reads the run source (`grep input.run policies/` finds nothing). Known-gaps names CLI uploads only for `removed` blocks. Fix: a mandatory, non-overridable OPA rule that denies non-VCS runs on control-plane and production workspaces, after checking the input field name on a real run.

**CICD-1.** Live `main` protection has no required reviews and `enforce_admins=false`. The required checks do not include `Validation Summary`. The last 30 pull requests were authored and merged by one person with no human review, and #599 merged with 6 failing checks. HCP Terraform plans from `main`, so an unreviewed merge is a production change. Fix: Phase 3 (codified rulesets and a second maintainer, owner decisions O1 and O3).

**Downgraded:** SEC-2, which the reviewer rated Critical, is now High (PLAUSIBLE). The StackSets are `SERVICE_MANAGED` (`modules/aws/iam/tfc-oidc-baseline/main.tf:686`), and no SCP or boundary statement covers `cloudformation:*` on `stack/StackSet-*`. The gap in code is real. But the escalation needs a direct `UpdateStack` to reuse the `stacksets-exec-*` role. It is not established that a service-managed stack instance records that role. Prove it on a sandbox account or add the deny anyway (it is cheap).

## High findings

| ID | Finding | Evidence | Status |
|---|---|---|---|
| SEC-2 | Member `tfc-apply` may escape its boundary by updating a StackSet stack | No `cloudformation:*` deny in the boundary or `scp-deny-tamper` | PLAUSIBLE, NEW |
| SEC-3 | `tfc_admin_guard.rego` ignores `execution_mode`/agent pools, workspace `vcs_repo` branch, `working_directory`, `project_id`, and `TFC_*`/`TF_CLI_ARGS*` written through `var.workspace_variables` | `policies/opa-destructive/tfc_admin_guard.rego`; `envs/tfc-admin/main.tf:680,714` | VERIFIED, NEW (also CICD-7) |
| SEC-4 | Phase-0 `tfc-mgmt-apply` is unbounded `AdministratorAccess` in the management account and can rewrite its own trust and the break-glass role | `templates/aws/bootstrap/phase0-management.yaml` | VERIFIED, NEW |
| SEC-5 | `organization-apply` holds unconditional org `folderIamAdmin`; its `securityAdmin` condition fails open on resource types without `modifiedGrantsByRole` | `modules/gcp/stages/bootstrap/service_accounts.tf` | VERIFIED, KNOWN, severity raised |
| ARC-2 | S3 and DynamoDB gateway endpoints carry no policy, so S3 traffic skips the production egress allowlist; the example allowlist also admits `.amazonaws.com` | `modules/aws/network/vpc/main.tf:166-174` (lead-checked) | VERIFIED, NEW |
| ARC-3 | The IP plan holds 14 workload VPCs per AWS region and 6 GCP environments; spoke subnet size is fixed | `docs/architecture/cidr-plan.md`; `modules/aws/stages/workload/variables.tf:117-121` | VERIFIED, KNOWN in part |
| ARC-4 | GCP production egress has no fail-closed gate like AWS `production_egress_enforced` | `modules/gcp/stages/net-spoke/main.tf:31-33` | VERIFIED, KNOWN, severity raised |
| ARC-5 | Single region; no DR network or standby; RTO and RPO are targets only | `docs/runbooks/disaster-recovery.md`; ADR 0009 Proposed | VERIFIED, KNOWN |
| ARC-6 / ADO-05 | 45 breaking commits since v0.1.0; UPGRADING Unreleased is about 2,800 lines; the sandbox upgrade log is empty | `UPGRADING.md` | VERIFIED, NEW as stated |
| IAC-1 | GCP subnet CIDRs come from discovered zones and no root can pin them; a zone change replaces in-use subnets | `modules/gcp/stages/net-spoke/main.tf:26`; `modules/gcp/stages/environment/main.tf:70-78` (lead-checked: no `explicit_zones` under `envs/`) | VERIFIED, NEW |
| CMP-01 | DET-05 "automated incident response" is a log-only stub (`TODO`) that the control matrix shows as On | `modules/aws/security/incident-response/files/isolate.py:33-35` (lead-checked) | VERIFIED, NEW |
| CMP-02 | GCP firewall, Cloud Armor, load balancer and NAT logs stay in each project's 30-day `_Default` bucket | `modules/gcp/governance/cloud-audit-logs/main.tf:197,316` | VERIFIED, NEW |
| CMP-11 | The CloudTrail KMS condition `aws:SourceOrgID` is unproven; if wrong, the org trail delivers nothing | `modules/aws/data/kms-key/main.tf:77-81` | SUSPECTED, KNOWN (A1), severity raised |
| CICD-2 | CODEOWNERS lists platform OR security on `/policies/`, `/envs/tfc-admin/` and `/.github/`, so a platform engineer alone satisfies review of the guardrails | `.github/CODEOWNERS` | VERIFIED, NEW |
| CICD-3 | Policy sets are sourced from `main`; a rego edit takes effect on merge | `envs/tfc-admin/main.tf:1522-1545` | VERIFIED, KNOWN |
| CICD-4 | Four-eyes is not enforced on production applies; the author can confirm | `envs/tfc-admin/main.tf:782` | SUSPECTED, KNOWN |
| CICD-5 | Environment protection exists only in workflow comments; live environments have no reviewers or branch policy | live `gh api` | VERIFIED, KNOWN |
| ADO-01 | The quick-start commit `config: landing zone` is rejected by the repo's own commitizen hook | `README.md:65`, `docs/guides/QUICK_START.md:108`, `scripts/init-landing-zone.sh:562` (lead-checked) | VERIFIED, NEW |
| ADO-02 | Docs disagree on whether the AWS organization is made by hand; the code creates it | `CLAUDE.md:294`, `QUICK_START.md:292` against `docs/runbooks/aws-bootstrap.md:54` | VERIFIED, NEW |
| ADO-03 | The example writes `role/break-glass`; the phase-0 stack creates `OrganizationBreakGlass` | `config/landing-zone.example.yaml:362`; `phase0-management.yaml:231` (lead-checked) | VERIFIED mismatch, effect SUSPECTED, NEW |
| ADO-04 | CI on `main` fails on real gates (Checkov, Trivy, yamllint), not only unfunded ones | `gh run list --branch main` | VERIFIED, KNOWN in part |
| ADO-06 | Bus factor 1; 85% of commits on `main` are AI co-authored | `git log` | VERIFIED, KNOWN |

Medium and Low findings are in the [appendix](#appendix-medium-and-low-findings).

## Tool results at `0ecad6d7`

| Gate | Result |
|---|---|
| `terraform fmt -check -recursive` | Pass |
| tflint 0.62.0, 15 roots and 8 modules | 0 issues |
| checkov 3.3.17, modules / envs | 1,432 / 872 passed, 0 failed; 4 parse errors not reported by CI |
| trivy 0.70.0, CI flags | 0 Critical or High; some newer checks need 0.72+ |
| `opa test policies/` (OPA 1.22.2) | 288 / 288 pass, about 185 deny-path |
| zizmor 1.31.1 offline | 0 findings (the directory walk misses `examples/app-delivery/*.example.yml`; named directly they are clean) |
| actionlint 1.7.12 | 0 findings |
| `make count-check`, `make links` | Pass (126 modules, 15 roots, 350 suites; 1,542 links) |
| `scripts/check-matrix-paths.sh` | Pass |
| Tests | 358 suites, 3,106 runs, 1.4% weak asserts |

## Industry readiness (compliance lens)

| Segment | Verdict | Main blocker |
|---|---|---|
| Startup SOC 2 | Ready with work | Vendor change evidence (CICD-1); IR stub (CMP-01) |
| Retail, media, telecom | Ready with work | GCP edge-log retention (CMP-02) |
| AI/ML | Ready with work | No AI service controls; GCP residency defaults |
| Fintech PCI DSS 4.0.1 | Ready with heavy work | GCP firewall and WAF logs; no CDE segmentation; internal HTTP (CMP-13) |
| Banking (DORA, FCA/PRA, SOX ITGC) | Not supported as shipped | GCP backups not segregated (CMP-07); standing production admin (CMP-04); UK and US notification rows missing |
| Healthcare HIPAA | Ready with work | BAAs; retention coverage |
| US public sector | Not supported | No FIPS, GovCloud or Assured Workloads (stated) |
| EU sovereignty | Not supported | No sovereign partition; HCP and GitHub in the US |
| EU GDPR | Ready with work | EU-only GCP regions and log location (CMP-06) |

## Adopter verdicts (adoption lens)

| Persona | Verdict | Manual steps | First governed estate |
|---|---|---|---|
| Startup (SaaS + small AWS, SOC 2) | Adopt with work | About 25 | 1 to 2 weeks |
| Fintech, AWS only | Adopt with work; budget one sandbox apply first | About 30 | 2 to 4 weeks |
| Enterprise, GCP + AWS, 50 teams | Do not adopt as system of record yet; use as reference design | 40+ | 6 to 10 weeks |

## Cost estimate (architecture lens, idle, list prices, USD per month)

| Profile | Estimate | Main lines |
|---|---|---|
| AWS production (default) | 2,200 to 3,200 | Network Firewall about 580; Route 53 Profile about 550 (price not verified, ARC-12); Security Lake, Config, GuardDuty, Macie |
| AWS starter | 900 to 1,300 | Route 53 Profile is about half |
| GCP default | 250 to 600 | NAT, PSC, DNS, KMS, logs |
| HCP Terraform Standard | 1,400 to 2,800 | Assumes 3,000 to 6,000 managed resources; not counted |

## Genuinely strong

- AWS Transit Gateway design: explicit association and propagation, appliance mode, per-spoke blackhole isolation, and a fail-closed production egress gate.
- Phase-split identities on both clouds. A plan can never mint apply credentials, and production refuses name-bound bindings.
- Typed cross-root contracts, plan-time guards (CIDR overlap, peering limit, 10-role `hasOnly` chunking, policy-size quotas) and clean scanners.
- Docs label defaults honestly and name an evidence command per control. Legal notification deadlines are correct.
- Workflows: every action SHA-pinned, `permissions: {}` defaults, egress blocked on every job that holds a secret.

## Gap tasks before Phase 3

Plan Step 4 requires these before the next phase. Grouped by size. The lens each one lifts is in brackets.

**Phase 2b: code an agent can do (about 1 to 2 days)**

1. ARC-1: compliant PSC endpoint name, address or internal range, validation and test. [design, operability]
2. ADO-01, ADO-02, ADO-03, ADO-07, ADO-08, ADO-10, ADO-12, ADO-13: quick start and AWS bootstrap corrections; `chore(config): landing zone`; `role/OrganizationBreakGlass`. [docs, adoption]
3. SEC-1: OPA rule denying non-VCS runs on control-plane and production workspaces (field name confirmed in a sandbox run before the rule is mandatory). [security, delivery]
4. SEC-3 and CICD-7: extend `tfc_admin_guard` to execution mode, agent pools, workspace VCS settings, project moves and `TFC_*`/`TF_CLI_ARGS*` variables; apply the reserved-name pattern to `var.workspace_variables`; change it to an allowlist (SEC-6). [security]
5. SEC-2 and SEC-4: deny `cloudformation` stack writes on `stack/StackSet-*` outside the StackSet role and break-glass; an inline deny in the phase-0 template on self-trust and break-glass edits. [security]
6. ARC-2: gateway endpoint policy on `aws:ResourceOrgID` with an AWS-owned bucket exemption; remove `.amazonaws.com` from the example allowlist. [design, compliance]
7. IAC-1: pass `explicit_zones` through the environment and network-hub stages and config; require it when `is_production`. [craft, design]
8. CMP-01: relabel DET-05 as Scaffold or implement cross-account isolation. CMP-02: org sink for firewall, request and NAT logs. CMP-09: correct SECURITY.md. [compliance, docs]
9. ARC-4: GCP production egress gate with a waiver object; CMP-05: make `audit_store_waived` an object with reason and expiry. [design, compliance]
10. CICD-2: security-team-only CODEOWNERS lines on guardrail paths. CICD-8: destroy guard types and `deletion_protection` true to false. [delivery]

**Owner and funding (Phases 3 and 4, unchanged)**

- CICD-1, CICD-3 to CICD-5: codified rulesets, protected environments, policy-release branch and a second maintainer (O1, O3).
- ADO-04: green CI on `main` (fix the yamllint, Checkov and Trivy failures there, or merge this branch).
- One funded sandbox apply per cloud. It is the only way to settle ARC-1, SEC-1, SEC-2, CMP-11 and the IPAM and Route 53 Profile behaviour.

**Design work (Phase 5 or WS7)**

- ARC-3 (enterprise IP plan and configurable spoke size), ARC-5 (second region), ARC-6 (release cadence and a breaking-change freeze until v0.2), ARC-7 and ARC-8 (environment onboarding without hand-offs; per-area config files), IAC-2 (split `envs/tfc-admin/main.tf`).

## Appendix: Medium and Low findings

**Security.** SEC-6 env-var denylist gaps (`TERRAFORM_CONFIG`, `LD_PRELOAD`, `NODE_OPTIONS`, `GIT_*`, `BASH_ENV`). SEC-7 non-production speculative plans run before the CI gate; `terraform_remote_state` `hostname` unchecked (KNOWN). SEC-8 platform team holds `runs = "plan"` on the control plane by default. SEC-9 app-deploy WIF binds the GitHub environment name with no ref. SEC-10 AWS OIDC subjects are name-based, not workspace-ID based. SEC-11 audit keyring tag removable (KNOWN).

**Compliance.** CMP-04 the production permission-set guard restricts `Developer` but not `PlatformAdmin`. CMP-06 GCP `allowed_regions` default mixes EU and US; log buckets stay `global`. CMP-07 GCP backups not segregated or cross-region. CMP-08 `compliance.frameworks` sets only retention floors. CMP-10 no rows for FCA SUP 15, the US 36-hour banking rule or NYDFS 500.17. CMP-12 HIPAA 164.312(c)(1) mapped to log WORM instead of data integrity. CMP-13 internal ALB serves HTTP by default. CMP-14 CloudFront default certificate floor; noncurrent log versions never expire; framework names unvalidated in Terraform; GuardDuty EBS scan is on-finding only.

**Architecture.** ARC-7 new environments need manual multi-root hand-offs. ARC-8 every config edit plans every workspace. ARC-9 GCP peering-group quotas unguarded beyond the peering count. ARC-10 ECS bootstrap image from `public.ecr.aws` not in the egress allowlist. ARC-11 AZ IDs unset by default. ARC-12 Route 53 Profile missing from the cost table. ARC-13 GCP environment zones not visible from the hub or on-premises. ARC-14 IPv6 is cosmetic. ARC-15 Cloud NAT `AUTO_ONLY` addresses; hub Cloud Armor policy unattached. ARC-16 HCP Terraform cost unestimated.

**Terraform craft.** IAC-2 `envs/tfc-admin/main.tf` is 1,689 lines with a 1,050-line `locals` block. IAC-3 mocks prove schema, not API acceptance; `interface_services` unvalidated. IAC-4 `try(tostring(...), null)` silently drops wrong-typed config. IAC-5 some suites echo inputs; 171 policy asserts use regex or `strcontains`. IAC-6 checkov parse errors unreported; trivy pin below 0.72. IAC-7 fork-the-monorepo versioning (KNOWN).

**Delivery.** CICD-6 the sandbox E2E label gate is bypassable by any writer. CICD-9 wildcard cloud domains in egress allowlists (KNOWN). CICD-10 release fails open with no ingress commit (KNOWN). CICD-11 no SBOM, signing or tag protection (KNOWN). CICD-12 Renovate not installed; Dependabot has no cooldown (KNOWN). CICD-13 to CICD-17: unhashed `pip install`; terraform-docs checksum from the same origin; example delivery workflows without harden-runner; zizmor misses `*.example.yml`; docs bot pull requests get no required checks. OpenSSF Scorecard estimate after merge: about 5.5; only live settings move it above 7.

**Adoption.** ADO-09 no minimal AWS footprint in the scaffolder (9 accounts against a default quota of 10). ADO-11 nine TFC team inputs and scattered operator steps with no single checklist. ADO-14 terminology: TFC, Terraform Cloud and HCP Terraform used interchangeably; phase names differ by cloud. Capability gaps for the enterprise persona: no EKS, Azure, AI/ML services, data platform, IdP integration, service mesh, developer portal, AWS cost export or active-active primitives.

## Status after Phase 2b (2026-11-13)

This section records what the Phase 2b commits (`87a134cc..17419a04`) did with the findings above. It does not change the findings. Scores are not re-estimated here: the next independent re-audit sets them. "Closed in code" means the code and its mock or OPA tests do what the gap task asked; nothing below is proven on a real cloud or a real HCP Terraform run.

| Finding | Status | Evidence commits | Still needs the sandbox (or a decision) |
|---|---|---|---|
| ARC-1 | Closed in code (mock tests only) | `30e35ce1`, `e3d0254e`, `51f5121b` | A first real hub and environment network apply that creates the PSC endpoint with the derived name and address |
| SEC-1 | Closed with residual: `tfc_vcs_run_only` reads `input.run`, is PREVIEW and sits in the overridable set. On `gcp-guardrails` one security engineer can upload, override and apply alone | `413b836b`, `248dbb85`, `d7f1aee2` | Read `run.commit_sha` on a VCS, a UI-queued and an API-upload run; then move the rule to the hard-gate set |
| SEC-3 / CICD-7 | Closed in code | `11c540ec`, `188b1333`, `1cc09a71`, `efbb885e` | The variable set walk needs `input.plan.configuration`: one tfc-admin plan that creates and attaches a variable set |
| SEC-6 | Closed with residual: a denylist; `HOME` and `XDG_CONFIG_HOME` are not blocked | `0ac83941`, `188b1333` | None (a design limit, in known-gaps) |
| SEC-2 | Closed in code. Deny-tamper SCP 5,068 characters with defaults (quota 10,240); `tfc-apply` boundary 5,423 of 6,144. That Control Tower writes its stacks as `AWSControlTowerExecution` is inferred from the Control Tower guide | `5443e62f`, `954137ea`, `c01ba9d8` | Apply the SCP and boundary in a sandbox organization; on a Control Tower estate, confirm the writer role |
| SEC-4 | Closed with residual: `tfc-mgmt-apply` keeps `AdministratorAccess` in the management account | `a1c3d006`, `71567bcd` | Deploy the phase-0 stack and confirm the self-tampering and member-pivot denies |
| ARC-2 | Closed with residual: PREVIEW; DynamoDB with `aws:ResourceOrgID` is unproven; the regional ECR and Secrets Manager names in the egress allowlist admit any account | `7bd63597`, `3ac8fc38` | The production gateway endpoint checks in known-gaps (ECR pulls, `dnf`, SSM patching, DynamoDB in and outside the organization) |
| IAC-1 | Closed in code | `6be6c490`, `e4e36996`, `d7f1aee2` | A plan with pinned zones on an existing network that shows no subnet change |
| ARC-4 | Closed with residual: production runs on an expiring waiver until the hub Secure Web Proxy is proven | `24093f1e`, `e4e36996`, `d7f1aee2` | Prove the Secure Web Proxy (PREVIEW), then drop the waivers |
| CMP-01 | Closed by relabel: DET-05 is a scaffold; the isolation handler is not built | `3484f15c` | None until the handler is built |
| CMP-02 | Closed with residual: the network log sink is on only for regulated or framework estates; LOG-06 is PREVIEW | `2a0d462a`, `22a050f0`, `6badb3a7` | One org sink apply that delivers to the audit bucket; check the legacy sink identity case |
| CMP-05 | Closed | `ba7a4c05`, `e4e36996` | None |
| CMP-09 | Closed | `3484f15c` | None |
| CMP-12 | Closed | `3484f15c` | None |
| CICD-2 | Closed with residual: `envs/tfc-admin`, the `.github` workflows and the config files (and the waivers in them) are still satisfied by a platform approval alone | `35d83965`, `a39285d5`, `17419a04` | Real teams and required code-owner review on the default branch (Phase 3) |
| CICD-8 | Closed (OPA unit tests only) | `e152ef02` | One update that turns `deletion_protection` off in the sandbox |
| ADO-01, ADO-02, ADO-03, ADO-07, ADO-08, ADO-10, ADO-12, ADO-13 | Closed. ADO-08: the order (enable Identity Center after the delegated administrator registration) is unproven | `be02aa4d`, `851ec83b`, `51f5121b` | ADO-08: the AWS bootstrap order on a real organization |

**Still open: owner, funding or design work**

- CICD-1, CICD-3 to CICD-5: codified rulesets, protected environments, a policy release branch and a second maintainer (owner decisions O1 and O3, Phase 3).
- ADO-04: CI on `main` is still red until this branch merges or `main` is fixed.
- ADO-06: bus factor 1.
- ADO-09 (minimal AWS footprint) and ADO-11 (one operator checklist).
- SEC-5: `organization-apply` org-level `folderIamAdmin` and the fail-open `securityAdmin` condition.
- ARC-3 (IP plan size), ARC-5 (second region) and CMP-11 (the CloudTrail `aws:SourceOrgID` condition, sandbox).
- ARC-6 / ADO-05 got worse: `git log v0.1.0..HEAD --oneline | grep -c '!:'` now counts 57 breaking commits (45 at the re-audit), and `UPGRADING.md` has 3,218 lines, 3,134 of them under Unreleased (about 2,800 at the re-audit). The sandbox upgrade log is still empty.

**Tool results now**

- `opa test policies/` (OPA 1.22.2): 403 / 403 pass (288 at the re-audit).
- `terraform test`: 3,220 runs in 145 directories, 0 failed, at `a39285d5`. The later commits change only docs, config example comments, scaffold fixtures, CODEOWNERS, the scaffolder test and one variable description.
- `make count`: 126 modules, 15 roots, 350 test suites.
