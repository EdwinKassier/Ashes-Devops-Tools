# Brutal Best-Practice Audit — Ashes DevOps Tools

**Date:** 2026-11-04
**Branch:** `claude/repo-audit-best-practices-11531b`
**Scope:** Full repository. Terraform GCP + AWS + Supabase + Vercel landing zone. 98 modules, 10 deployable roots, ~33.4k lines of Terraform, 207 test suites.
**Standard applied:** Latest (2025/2026) system design, infrastructure and Terraform/DevOps best practice. AWS SRA, Google enterprise foundations/FAST, CIS. Adversarial posture: assume a claim is false until proven at the source.
**Method:** Five independent deep-dive audits (architecture, Terraform hygiene, security, CI/CD and state, testing and docs), each verified at `file:line`. The four most severe claims were re-verified by hand against source. This is a fresh external audit. It is deliberately distinct from the in-repo self-audit at `docs/audit/2026-09-09-due-diligence-audit.md`.

---

## 1. The one-paragraph verdict

This is a top-decile Terraform **specification** of a multi-cloud landing zone. It is not yet a landing zone. The code hygiene is genuinely senior-grade, the identity model is keyless and modern, the org guardrails are enforced by default on both clouds, and `known-gaps.md` is more honest than most production platforms. But three facts sit under all of that. First, it has never been applied to a real cloud account. All 207 tests use `mock_provider` (774 plan runs, 21 apply runs, every one mocked), and the repo's own prior audit confirms "no live cloud plan/apply was performed". Second, it was produced in rapid solo bursts (167 commits across two days, 2026-07-08 and 2026-07-09; one author for 371 of 371 commits). That is generation velocity, not operation history. Third, several headline security controls ship inert: VPC Service Controls default to dry-run (no exfiltration protection), IAM deny policies ship empty, Config conformance packs ship empty, CMEK is opt-in, and the audit-log WORM lock is off by default. The central risk is the distance between how production-ready this reads and how little of it is proven. Judged as a boilerplate template it is excellent. Judged as a platform an organisation can adopt and operate safely today, it is unproven and carries two structural footguns that can make it un-recoverable.

### Scorecard

| Dimension | Grade | One line |
|---|---|---|
| Terraform code hygiene | A | Top-decile. Rich types, real cross-field validations, zero copy-paste, docs in sync, clean fmt. |
| Identity and federation | A | Keyless WIF/OIDC everywhere. SA-key creation org-blocked. No long-lived keys. |
| Org guardrails (default-on) | A- | CIS-aligned org policies and SCPs enforced by default on both clouds. |
| Honesty of documentation | A- | `known-gaps.md` discloses unvalidated and inert items candidly. Rare and valuable. |
| CI/CD supply chain | B+ | 100% SHA-pinned, least-privilege tokens, blocking scanners. Undercut by a fail-open gate. |
| Test assurance | B | Tests are genuine, not theater, but 100% mock and the critical roots are untested. |
| Security trust model | B- | Strong baseline defanged by a god-principal, dry-run VPC-SC, and manufactured scanner green. |
| Architecture / blast radius | B- | Correct provider-selection core, wrapped around a monolithic GCP state and brittle coupling. |
| Proven in production | F | Never applied. Assurance is 100% static and mock. This is the headline. |

---

## 2. The meta-finding that frames everything

**M0 — The entire repository is unproven against reality, and the unproven parts are exactly the ones mock tests cannot cover.**

Evidence:

- Every test is `mock_provider`. 197 of 201 module test files mock the provider. 774 of 795 `run` blocks are plan-only. The 21 `apply` runs are still against mocked providers. Source: test-suite census and `docs/known-gaps.md:104` ("mock-tested only, no on-path coverage").
- The prior in-repo audit states plainly: "no live cloud plan/apply was performed" (`docs/audit/2026-09-09-due-diligence-audit.md:160`).
- The repo is full of placeholders consistent with never-deployed: `your-tfc-org-name` (`examples/dev.tfvars:23`), `organizations/123456789` (`examples/vpc-sc/main.tf:13`), `example.com` account emails (`envs/aws/organization/variables.tf:48-53`). This is correct for a template, and the `my-org` rejection validations are a nice touch. It is listed here only as corroboration that no real org has run this.

Why this is the top finding: for infrastructure code, "validates and mock-tests green" is not "works". The items that a mocked plan provably cannot catch are the ones most likely to fail on first real apply:

- **A1 (CloudTrail KMS condition).** The CloudTrail KMS grant uses `aws:SourceOrgID`, but AWS documents `aws:SourceArn` for the KMS key policy. If CloudTrail does not emit `SourceOrgID` on its KMS calls, log delivery fails closed. Still OPEN (`docs/known-gaps.md:14-20`). A mock cannot catch this. A real apply would.
- **Provider authentication and WIF/OIDC trust.** Only exercised at real init/apply.
- **The `vault-secrets` provisioner chain.** `npm ci` plus Node scripts at apply time, outside the Terraform graph, with a destructive reconcile step. Runtime-only behaviour.
- **IAM-at-apply and eventual-consistency ordering** across the ~12-15 workspace bootstrap.

Recommendation: run one real end-to-end apply in a throwaway organisation for each cloud before this is described as anything other than a reference template. Treat the first real apply as the actual test suite. Until then, every "A" grade above is a grade for the specification, not the system.

---

## 3. Findings, ranked by real severity

### HIGH

**H1 — The CI/CD automation identity is a god-principal exempt from every tamper guardrail. (verified at source)**

- AWS: the Terraform run role is listed in `ArnNotLike` on both `DenyLeaveOrganization` and `DenyDisableSecurityServices` (`modules/aws/governance/organization-policy/policies/scp-deny-tamper.json:9-42`). That means the pipeline identity can `cloudtrail:StopLogging`, `cloudtrail:DeleteTrail`, `guardduty:DeleteDetector`, `config:StopConfigurationRecorder`, `securityhub:DisableSecurityHub`, `macie2:DisableMacie`, and leave the organisation, with no SCP backstop.
- GCP: a single `terraform-admin` service account holds org-wide `roles/iam.securityAdmin` (which allows `setIamPolicy`, so it can grant itself anything) plus `orgpolicy.policyAdmin`, `accesscontextmanager.policyAdmin`, `logging.admin`, `securitycenter.admin` (`modules/gcp/stages/bootstrap/main.tf:155-214`).
- The only control gating these identities is OIDC/WIF trust. The privilege split that would reduce it (`enable_privilege_split`, G3) is self-declared incomplete, "Do not enable as-is" (`docs/known-gaps.md:108-111`).

Impact: a single pipeline compromise (a malicious merge to `main`, a poisoned Action, a leaked TFC run) yields an identity that can dismantle every detective and preventive control in both clouds. There is no second-person control in the tamper path. Fix: remove the run role from the `DenyDisableSecurityServices` and `DenyLeaveOrganization` exemptions (Terraform never needs to disable logging; only break-glass should be exempt), complete the GCP privilege split, and make branch protection plus required review the documented control of record for the WIF trust.

**H2 — The "fail-closed" merge gate fails OPEN. (verified at source)**

`terraform-plan.yml:248` sets the required `summary` gate's `needs` to `[fmt, docs, validate, lint, meta-lint, security, test]`. The `discover` job is deliberately absent. The gate loop (`:281`) fails only on `result == "failure" || "cancelled"`, never `"skipped"`. The `validate` job has `needs: discover` and a matrix fed from `fromJson(needs.discover.outputs.roots)` (`:99-103`).

Failure scenario: if `discover` fails or emits `[]` (a transient checkout issue, a `scripts/terraform-roots.sh` error), the `validate` matrix is skipped, `needs.validate.result == "skipped"`, the gate does not treat that as failure, and the summary reports green. A pull request then merges with `terraform validate` having run on zero of ~180 roots, while the job comment claims it "covers the whole validate matrix". Fix: add `discover` to `summary.needs`, treat `skipped` as failure for `discover` and `validate`, and assert the discovered root set is non-empty.

**H3 — The GCP control plane is a single monolithic state. (blast radius)**

`envs/gcp/organization/main.tf` composes four stage modules into one state and one workspace: `bootstrap` + `organization` + `projects` + `network-hub` (`:74-150`). That single `gcp-organization` state owns the admin project, the Terraform SA, GitHub/TFC WIF, folders, org policy, KMS, audit logging, billing, the hub VPC, and every host project for every environment. The AWS side is properly layered (org → security → network → identity → shared-services → backup → workload). The GCP side is not.

Impact: one bad apply, one state corruption, or one lock loss on `gcp-organization` can take out the control plane for prod, uat and dev at the same time. This is below Google's own enterprise-foundations blueprint, which splits bootstrap / org / environments / networks / projects into separate states precisely to shrink this radius. Fix: peel `bootstrap` and `projects` (host projects) out of `gcp-organization` into their own roots, so per-environment project state is not co-located with org-policy state.

**H4 — Cross-root dependencies are unenforced, and providers configure themselves from remote state. (un-teardownable)**

Downstream AWS roots set their provider `role_arn` directly from an upstream data source, for example `role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"]` (`envs/aws/security/providers.tf:16`, same pattern across network, identity, backup, shared-services, workload). The documented ordering model is "apply order plus remote-state reads, not cross-root `depends_on`" (`ARCHITECTURE.md:162`).

Impact: the only guard against mis-ordering is a plan-time "no outputs" error. Worse, because provider configuration depends on a data source, renaming any output key in `aws-organization` breaks all six downstream roots at provider init. They cannot even `destroy`. Teardown becomes brittle, and there is no drift signal that an upstream contract changed until the next downstream apply fails. Fix: add a CI contract test that asserts the cross-root output key set does not shrink, document the teardown trap, and consider passing role ARNs as explicit workspace variables rather than provider-time data lookups, so a provider can always initialise.

### MEDIUM

**M1 — Scanner "green" is partly manufactured. (security theater)**

- `tfsec` is end-of-life (Aqua folded it into Trivy) and is still the PR-blocking static-analysis gate (`reusable-security.yml:16-45`, pinned `tfsec 1.28.6`). Its rule set no longer advances.
- The tfsec floor is set to MEDIUM, and `.tfsec.yml` itself records that a full AWS-enabled scan reports zero findings because the AWS ruleset is thin. So tfsec provides near-zero real AWS coverage.
- AWS posture therefore rides on about 40 inline `checkov:skip` directives. Several suppress genuinely reduced controls, not graph false-positives: CloudFront with access logging off, geo-restriction "none", and no security-headers policy (`modules/aws/security/edge-security/main.tf:97-153`); a plain HTTP listener permitted on the load balancer (`modules/aws/network/load-balancer/main.tf:120`); CMK encryption opt-in on Network Firewall (`modules/aws/network/network-firewall/main.tf:22-71`).
- Trivy exists but runs only post-merge and only at CRITICAL/HIGH (`security-scan.yml:36-67`).

Impact: a reader who sees "CI security gate green" overestimates enforced coverage. The gate is real, but its forward coverage is softer than the pinning suggests. Fix: promote Trivy to the PR gate and reconcile its findings, then raise the edge-security, load-balancer and network-firewall secure options to default-on. The repo already tracks the Trivy promotion as a DECISION (`docs/known-gaps.md:164-166`); it is overdue.

**M2 — VPC Service Controls ship defanged, and the enforced path has a total-wildcard hole.**

The perimeter default was flipped to dry-run (`docs/known-gaps.md:86-93`, "dry-run gives no exfiltration protection"). Separately, the opt-in automation ingress policy is a total wildcard: `access_level = "*"`, `resources = ["*"]`, `service_name = "*"`, `method = "*"` (`modules/gcp/stages/network-hub/main.tf:91-97`). Impact: in the shipped state the data-exfiltration perimeter is advisory only. If an operator enables enforcement but sets `vpc_sc_ingress_identities` (the documented way to stop the perimeter blocking TFC), that identity gets an all-services, all-methods, all-resources hole through the perimeter. Combined with H1, a compromised automation identity exfiltrates unimpeded. Fix: scope the ingress policy to the specific services and methods automation needs, and document a hard "promote to enforced before production" gate.

**M3 — A pattern of inert controls: capabilities that provide zero protection as shipped.**

Multiple security modules exist but default to off or empty, so the control is present in the capability table and absent in effect:

- IAM deny policies ship empty, "inert until populated" (`docs/known-gaps.md:73-78`).
- Config conformance packs ship as an empty bring-your-own hook (`docs/known-gaps.md:46-49`).
- Audit-log WORM lock is opt-in, default off (`docs/known-gaps.md:67-72`).
- CMEK is opt-in across several modules; the default is an AWS-owned or GMEK key (prior audit M3).
- Cloud Armor's default rule is `allow` over `src_ip_ranges = ["*"]`, so a policy with no custom rules is allow-all except preconfigured WAF (`modules/gcp/network/cloud-armor/main.tf:7-22`).
- The shared VPC-interface-endpoint policy is `Action = "*"` and `Principal = "*"`, org-scoped only (`modules/aws/network/vpc-endpoints/main.tf:29-42`).

Impact: an adopter who stands this up with defaults gets far less protection than the module inventory implies. Fix: flip the secure options to default-on and require callers to opt down, or ship a conformance pack that fails when they are off.

**M4 — Operability tax is high, and the riskiest surface is out-of-band and unversioned.**

The bootstrap honestly documents a large manual surface: a phase-0 org plus bootstrap OIDC identity, a phase-0.5 org-wide CloudFormation StackSet for default-VPC deletion, a manual IAM Identity Center console gate, and manual creation and role-trusting of each downstream TFC workspace (the `tfe` provider was deliberately refused to preserve provider purity). Across AWS (7 layers) plus GCP (org plus N workload workspaces) plus SaaS, a real deployment is roughly 12-15 hand-created TFC workspaces, each with its own OIDC trust, none of it in code. Impact: the per-workspace trust wiring is exactly what drifts and what no one audits. The honest "2-4 hours, high risk" self-assessment assumes an operator who already holds the whole model. This plus 98 modules at SRA rigor is a platform-team workload, carried by one author. Fix: codify the workspace and trust provisioning (a dedicated `tfe`-only bootstrap root or an in-repo script), or reduce the workspace count.

**M5 — The most critical roots have zero tests.**

Root-level tests exist only under `envs/aws/*` (6 of 7). These have none: `envs/gcp/organization` (the GCP control plane), `envs/gcp/workload`, `envs/saas`, and `envs/aws/organization` (the AWS org root everything depends on). The irony: the newer AWS roots got contract tests; the mature, primary GCP control-plane roots did not. Root assembly and remote-state wiring is exactly what breaks after a reorg, and the CHANGELOG shows a recent reorg that rewrote every `source` path. The "every module ships at least two suites" claim is true for `modules/` and silently excludes `envs/`. Fix: add `root.tftest.hcl` contract tests to the 4 untested roots, mirroring the AWS root-test pattern.

**M6 — Security-critical policy assertions check substring presence, not structure.**

33 policy assertions use `can(regex("token", resource.policy))`, versus 12 using structural `jsondecode`. For example `can(regex("aws:SourceOrgID", aws_s3_bucket_policy.this.policy))` proves the string appears somewhere in the document, not that it scopes the right statement, principal or action (`modules/aws/data/log-archive-bucket/tests/plan_assertions.tftest.hcl`). Impact: a refactor that moves `SourceOrgID` onto the wrong statement, or drops it from one of several grants, still passes. For org-wide log-delivery and KMS grants that is the exact bug class you most want caught. Fix: for the highest-stakes policies, `jsondecode` and assert at statement granularity.

**M7 — The security-to-workload audit-logging contract is hand-typed strings.**

`envs/aws/workload/main.tf` reads remote state only from `aws-organization` and `aws-network`. The security-layer values it needs (`log_archive_bucket_name`, `config_role_arn`, `kms_key_arn`) are plain `var.` inputs it calls a "cross-root naming contract that MUST match" (`variables.tf:75`), not read from `aws-security` state. Impact: flow logs, Config snapshots and Session Manager logs point at a bucket, role and key by hand-typed string. Rename or rotate any of them in `aws-security` and every workload silently keeps the stale value. Logging failures of this kind surface only at an audit. This is precisely the drift the remote-state pattern was meant to eliminate, left manual where it matters most. Fix: add an `aws-security` remote-state read and source these from it.

**M8 — TFC token scope is self-contradictory.**

`terraform-apply.yml:78-83` documents `TFC_TOKEN` as read-only, "does not trigger or modify any run". But `drift-detection.yml:164-184` does `POST /runs` to create a speculative plan, which requires queue-plan (write). One secret cannot satisfy both. Either drift silently 403s and never detects drift, or the release token is over-privileged against its own stated safety rationale. Fix: split into a read-only release token and a scoped queue-plan drift token, and correct the comment.

**M9 — The `vault-secrets` module is the largest runtime-fragility surface.**

`modules/supabase/vault-secrets/main.tf:29-86` drives three `null_resource` plus `local-exec` provisioners (`npm_install` then `bootstrap` then `reconcile`) that shell out to Node at apply time. Provisioners are outside the Terraform graph, do not roll back, require Node 18+ on PATH, and re-run on trigger-hash change with no plan-time visibility. The `reconcile` step deletes any managed vault row absent from `var.secrets`, so an accidentally-empty map is destructive (guarded only by a `VAULT_ALLOW_EMPTY_DESIRED` escape hatch). To the module's credit the choice is forced (no native Supabase Vault resource), triggers are correctly hashed, and the namespace is regex-scoped. It remains the one place a routine apply can do real damage. Fix: keep it quarantined in its own workspace; replace with a provider resource when upstream ships one.

### LOW / noted

- **L1 — "Multi-cloud" is oversold.** AWS and GCP have zero cross-cloud connectivity. The advertised cross-cloud remote-state wiring is entirely commented-out example code (`envs/saas/main.tf:55-79`). The honest description is three independent zones sharing a repo and conventions. That is good for the provider-selection thesis (it proves no hidden coupling) but the "multi-cloud landing zone" framing flatters it. Rename it "independent per-cloud zones, pick any subset".
- **L2 — No global address plan.** GCP hub is `10.0.0.0/16`; AWS uses its own IPAM supernet; nothing reconciles them. Fine while they are islands, a guaranteed overlap the day anyone adds the already-scaffolded VPN modules. Publish one global CIDR allocation now.
- **L3 — `make count` is wrong.** It reports "deployable roots: 3" because the formula is `find envs -mindepth 1 -maxdepth 1` (the cloud-group dirs), not the 10 real roots one level deeper (`Makefile:93`). The verification tool contradicts the correct docs. A maintainer may "fix" the right number to match the broken tool.
- **L4 — Google provider pin spans a full major** (`>= 6.0, < 8.0`, 105 files), while locks are on 7.x. Finish the 6-to-7 migration and tighten to `~> 7.0`. Tracked debt, not a surprise.
- **L5 — Drift detection default coverage is 2 of about 12 workspaces** (`drift-detection.yml:105`: `gcp-organization`, `gcp-workload-dev`). Every AWS guardrail workspace is unmonitored unless an operator sets a variable. Someone disabling GuardDuty by hand is exactly what this should catch, and by default it does not.
- **L6 — Local and CI pipelines have diverged.** `make validate-all` runs `terraform validate` on every root with no `configuration_aliases` skip, while CI inlines that skip in YAML (`terraform-plan.yml:120-127`). So `make ci` fails locally on the cross-account AWS modules CI passes. The alias skip is also a substring grep, so a comment containing the string disables validation for a whole root.
- **L7 — Release provenance is loose.** The release job publishes a GitHub Release when the latest TFC run is `applied`, without checking that run corresponds to the tagged commit (`terraform-apply.yml:91-168`). A tag can mint a "deployed" release for an unrelated apply.
- **L8 — `active-providers.sh` is stale after the reorg**, reporting only `saas` because it searches `envs` at depth 1 (roots now live at depth 2). An operator helper gives a false "only saas is active" picture.
- **L9 — The in-repo self-audit is marketing.** `docs/audit/2026-09-09-due-diligence-audit.md` grades itself A-/B and declares all 22 findings "resolved the same day". Resolving 22 findings in one day is a signal that some fixes were documentation edits rather than behaviour changes (several explicitly were). A self-audit that lives in the audited repo and scores itself is a sales document, not independent assurance.

---

## 4. What is genuinely strong (state these plainly)

These are verified, not courtesy notes.

- **Code hygiene is top-decile.** 1021 of 1021 variables carry a type and a description. 494 validation blocks, every one with an error message, including real cross-field invariants (a mutual-exclusivity XOR in `cloud-armor`, conditional-on-enable org-id checks in `secrets-baseline`). Zero `type = any`. Zero copy-paste modules by checksum. `terraform fmt -check` is clean. 204 committed multi-platform lock files. Module READMEs are 100% in sync with `terraform-docs`.
- **Identity is fully keyless.** WIF on GCP and OIDC/assume-role on AWS, no long-lived cloud keys anywhere, and `iam.disableServiceAccountKeyCreation` enforced org-wide. This is excellent and above most production platforms.
- **Org guardrails are enforced by default on both clouds.** GCP enforces a CIS-aligned set (deny external IP, restrict public IP, uniform bucket access, public-access prevention, shielded VM, OS Login, restrict VPC peering, allowed-domains). AWS ships SCP deny-tamper, region restriction, an RCP data perimeter, declarative IMDSv2/public-access-block, and GuardDuty/SecurityHub/Config/Macie/Inspector on by default.
- **Supply chain is strong.** Every `uses:` across 6 workflows is a full 40-character SHA pin. terraform-docs and the tfsec binary are checksum-verified before use. Scanners are actually blocking (`soft_fail: false`). Drift detection is real: it triggers a genuine TFC speculative plan, reads change counts off the plan object, and opens de-duplicated labelled issues.
- **The provider-selection thesis is correct and verified.** "Cloud selection is which workspaces you apply" holds. Each root declares only its own provider, the `saas` root declares no aws/google providers, and the remote-state reads are genuinely credential-free. It is the minimal correct answer to a real Terraform constraint, not over-engineering.
- **The tests are genuine assurance, not box-ticking.** Boundary validations test real edges (accept-min, accept-max, reject by exactly one second). Policy JSON is core-evaluated and really asserted (`kms:ViaService` absent, per-service-principal grants present). Integration tests use `override_module` plus apply to assert real TGW routing contracts. The tautology rate is about 6 of 558 conditions.
- **The honesty is real and rare.** `known-gaps.md` is a candid ledger that labels dry-run VPC-SC, the endpoint wildcard, the incomplete privilege split and the CloudTrail KMS dealbreaker as open gaps rather than hiding them. This made the audit faster and should be stated in any data room.

---

## 5. The single biggest risk

The combination of M0, H3 and H4. This repository reads as production-ready, has never been applied, crams the GCP control plane into one monolithic state, and couples downstream roots at the provider layer through remote-state outputs. One careless apply or one renamed output key on an org root cascades to every downstream root, cannot be cleanly destroyed, and surfaces only at the next apply. There is no automated contract test or ordering guard to catch it, and the identity that would run that apply (H1) is also the identity that can dismantle every guardrail. At scale, that is the recipe for a landing zone that becomes both un-recoverable and un-teardownable, discovered on the day it matters most.

---

## 6. Recommended priorities

**Before anyone calls this production-ready:**

1. Run one real end-to-end apply per cloud in a throwaway organisation. Validate A1 (CloudTrail KMS condition) on real infrastructure. This is the real test suite (M0).
2. Remove the Terraform run role from the SCP tamper exemptions and complete the GCP privilege split (H1).
3. Fix the fail-open merge gate: add `discover` to `summary.needs` and treat `skipped` as failure (H2).

**Structural, before scaling adoption:**

4. Split the GCP control plane along the same seams as AWS (H3). Add a cross-root output-contract CI test and document the teardown trap (H4).
5. Promote Trivy to the PR gate and retire the EOL tfsec gate; flip the inert secure defaults to default-on (M1, M3).
6. Promote VPC-SC out of dry-run for production and scope the automation ingress (M2).

**Sprint-sized:**

7. Add root contract tests to the 4 untested roots; upgrade the highest-stakes policy assertions to structural (M5, M6).
8. Source the workload audit-logging contract from `aws-security` remote state (M7). Split the TFC token (M8).
9. Codify the workspace-and-trust bootstrap; widen default drift coverage to the AWS guardrail workspaces (M4, L5).

**Cleanup:**

10. Fix `make count`, `active-providers.sh`, the local/CI validate divergence, the full-major provider pin, release provenance, and the global CIDR plan (L2-L8).

---

## 7. Scope and caveats

- Static and gate-reading audit. No live cloud plan or apply was performed (correct: the repo forbids local apply, and TFC executes). Runtime behaviour of the provisioner chain and of the OPEN/PREVIEW items is unverified by design, which is itself finding M0.
- The four most severe findings (H1, H2, H3, H4) and L3 were re-verified by hand at the source after the deep-dives reported them. Line numbers reflect branch `claude/repo-audit-best-practices-11531b` on 2026-11-04.
- "Top-decile" and the A grades describe the specification. They are not a statement that the system works, because the system has not yet run.
