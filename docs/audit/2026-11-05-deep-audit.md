# Deep Audit — 2026-11-05

Scope: the whole repository on `main` at commit `8cdb47a`, after this cycle's
remediation (GCP state decomposition, Trivy gate, contract tests, FinOps
right-sizing, provider pin). Method: four independent expert reviews run in
parallel (IaC craftsmanship, security and compliance, CI/CD and operability,
system design and fast-start developer experience), each reading first-party
code, then cross-checked against the source by hand. The known gap "never
applied to a real cloud" (finding M0 from the prior audit) is not repeated here.

Lens: an industry expert clones this to stand up an enterprise software company
quickly, then operate it for years.

---

## The three structural verdicts

Three findings sit above the list. Each is a pattern, not a line.

### 1. An immaculately governed empty house

The repository builds the org, network, security, IAM and billing foundations at
a level most enterprises never reach. It does not build a place to run a product.

Confirmed by direct search of every first-party `.tf`:

- **One** application-runtime resource exists (an internal security Lambda in
  `modules/aws/security/incident-response/main.tf`). There is no module that runs
  a container or function for an application team. `modules/gcp/stages/workload`
  and `modules/aws/stages/workload` create a project or a spoke VPC and stop.
- **Zero** managed application datastores (no Cloud SQL, RDS/Aurora, Redis,
  DynamoDB, ElastiCache). The only product database in the repo is Supabase.
- **Zero** application delivery pipelines. The six workflows build, scan and gate
  Terraform. None builds an image, pushes to the (already-present) ECR / Artifact
  Registry modules, or deploys a service.
- Application observability is absent: no SLO, service monitoring, tracing/APM,
  log-based metrics, or paging integration. The one app dashboard
  (`modules/gcp/monitoring/compute-dashboard`) charts a Cloud Run service the repo
  gives you no way to deploy.

Zero-to-governed-empty-org is a day or two of applies. Zero-to-shipping-a-product
is weeks of unshipped platform work the adopter must build: the runtime, the
pipeline, the data layer, ingress, and a promotion flow. That is the hardest and
most opinionated part, and it is exactly what a "spin up fast" kit exists to
provide.

### 2. The posture looks hardened; a buyer taking the defaults ships one that is not

The primitives are correct and the dangerous defaults are off. A fast-start buyer
takes defaults. The result looks locked down and is not. All verified in source:

- GCP VPC-SC ships in **dry-run at every caller** (`stages/host`,
  `stages/network-hub`, the workload tfvars example). Dry-run logs and blocks
  nothing. The dashboard says "VPC-SC configured"; exfiltration protection is zero.
- The GCP audit-log bucket is **not immutable** by default
  (`cloud-audit-logs/variables.tf:38`, `enable_bucket_lock = false`).
- Org-wide **CMEK is not enforced**: `restrictNonCmekServices` exists as a preset
  but is not wired into the organization stage's policy set (0 references).
- CIS control-plane **alarms are off** (`enable_cloudwatch_logs` default false),
  the **secrets baseline** is off, and the **privilege split** is off and marked
  PREVIEW.

"Documented in known-gaps.md" is not a compensating control. This directly
challenges a call made in this cycle's remediation, which kept these opt-in to
avoid blind-flipping breaking or irreversible changes. Both views are right about
different things. The reconciliation is below (see "The defaults decision").

### 3. The GCP automation identity can remove every guardrail, and the whole Terraform Cloud layer is built by hand

- **GCP has no containment for its admin identity.** The `terraform-admin` service
  account is granted org-wide `roles/iam.securityAdmin`, `roles/orgpolicy.policyAdmin`,
  `roles/accesscontextmanager.policyAdmin`, `roles/logging.admin` and
  `roles/securitycenter.admin` (`modules/gcp/stages/bootstrap/main.tf:101-105`).
  `iam.securityAdmin` can set IAM policy anywhere, so the SA can grant itself any
  role. The only backstop (an org-node IAM deny policy) defaults to empty
  (`stages/organization/variables.tf:249`). This SA is impersonable by GitHub
  Actions, Terraform Cloud and the human admin. One poisoned action dependency on
  `main`, or one TFC run compromise, can disable every org policy, delete the
  VPC-SC perimeters, and delete the audit sinks. AWS does this right
  (`scp-deny-tamper.json` denies the run role from disabling security services);
  GCP has no equivalent.
- **Terraform Cloud is unmanaged.** There is no `tfe` provider anywhere. All 13
  roots plus a workspace per environment, their VCS wiring, and their OIDC /
  assume-role trust are created and maintained by hand in the UI. That layer is
  unversioned, unreviewed, and invisible to the drift tooling the repo is proud
  of. "Fast" becomes hours of console clicking per cloud. "For years" becomes
  config rot nobody can diff.

---

## Consolidated findings

Severity is for the stated goal (stand up an enterprise company fast, operate it
for years), not generic risk. `[lens]` marks the originating review.

### Critical

| # | Finding | Evidence | Fix |
|---|---|---|---|
| C1 | No application runtime, delivery pipeline, or managed data layer `[system]` | 1 app-runtime resource, 0 app datastores, 0 deploy workflows across all first-party `.tf` | Ship opinionated runtime modules (Cloud Run / GKE-Autopilot, ECS-Fargate / Lambda), a build-scan-push-deploy reference pipeline, and `cloud-sql`/`rds-aurora` + cache + queue modules wired to the existing VPC and registry primitives |
| C2 | GCP `terraform-admin` SA is an uncontained org-god; CI or WIF compromise is full org takeover `[security]` | `stages/bootstrap/main.tf:101-105`; `iam_deny_policies` default `[]` (`stages/organization/variables.tf:249`); no GCP SCP equivalent | Ship a default-on org-node IAM deny policy (deny `orgpolicy.*`, `accesscontextmanager.*`, `logging.*.delete`, `resourcemanager.*.setIamPolicy` to all but a named break-glass principal); finish and default-enable the resman/admin split; separate the CI-impersonable SA from the privileged SA |
| C3 | The entire Terraform Cloud workspace layer is manual and unversioned `[cicd]` | No `tfe` provider in repo; `aws-bootstrap.md:94-98`, `bootstrap.md:181` state it is a manual step; ~20+ workspaces by hand | Add a thin `tfc-admin` root using the `tfe` provider (its own workspace, so provider-optionality holds) that declares all workspaces, variable sets and dynamic-credential config from the same `environments`/`accounts` maps |
| C4 | No `allowed_account_ids` guard on any AWS provider in an org that mints accounts `[iac]` | `envs/aws/security/providers.tf:8-10`; repo-wide grep for `allowed_account_ids` = 0 | Add `allowed_account_ids = [var.management_account_id]` to each default provider and per cross-account alias; fail fast on a wrong-account credential |

### High

| # | Finding | Evidence | Fix |
|---|---|---|---|
| H1 | Unsafe-but-documented defaults: a default apply is not hardened `[security]` | VPC-SC dry-run at every caller; `enable_bucket_lock=false`; `restrictNonCmekServices` unwired; CIS alarms, secrets baseline, privilege split all off | Provide one "production hardening" preset that flips every safe-to-enable control on together; keep only the irreversible WORM lock as an explicit opt-in (see "The defaults decision") |
| H2 | GitHub WIF provider can trust the whole issuer; bindings are branch-agnostic `[security]` | `modules/gcp/iam/workload-identity/main.tf:35,54-56` (null `attribute_condition` when org and bindings empty); repo bindings match all refs | Make `attribute_condition` mandatory (precondition); fold a `ref` match into the condition so branch scoping does not depend only on the SA binding |
| H3 | `modules/gcp/stages/host` is a 756-line, 74-variable god-module every workload instantiates `[iac]` | 33 module calls, 16 `enable_*` toggles in one stage | Decompose into composable sub-stages (host-network, host-edge-security, host-dns, host-connectivity) so consumers opt into surface area |
| H4 | `environments` map duplicated verbatim across 4 GCP roots with no validation `[iac]` | Identical object in `bootstrap`, `organization`, `projects`, `network-hub` variables.tf; "keep in sync" is prose only; no `validation` | Source the map once (TFC variable set or shared tfvars); require only the fields each root uses; validate CIDR/region at the source |
| H5 | Workflows are misnamed and the docs describe behaviour they lack `[cicd]` | `terraform-apply.yml` is "Release Metadata" and never applies; `terraform-plan.yml` runs `validate -backend=false` and never plans; `CI_SECRETS.md:12,18` claim it "drives real applies" | Rename the workflows and correct `CI_SECRETS.md`; the real apply and plan are TFC-driven |
| H6 | No real plan is a required gate; "all checks passed" is false confidence `[cicd]` | Repo CI validates with `-backend=false` only; the TFC plan check is not in `BRANCH_PROTECTION.md:9-24` | Require the TFC run checks in branch protection for prod-gating roots, or post the plan into the PR |
| H7 | QUICK_START is broken for the first GCP apply after the state split `[cicd]` | `QUICK_START.md:134-135` applies `-target=module.bootstrap` against `gcp/organization`, which no longer holds that module | Rewrite §4 to apply `envs/gcp/bootstrap` first (two-phase, `terraform_admin_email=null`), matching `bootstrap.md` and the file's own §5 table |
| H8 | Drift detection is blind to every AWS guardrail by default `[cicd]` | `drift-detection.yml:118` default is GCP-only; AWS org/security/network and all prod workloads only covered if an operator sets `TFC_DRIFT_WORKSPACES` | Self-discover the matrix from applied roots, or ship an AWS-inclusive default guarded by existence checks |
| H9 | SaaS is a disconnected island, not an integrated tier `[system]` | `modules/saas/stages/saas-workload` composes Supabase + Vercel with no network, DNS, secret or IAM tie-in to AWS/GCP | Decide the integration story (Supabase as primary DB behind the runtime, or document SaaS as an explicitly standalone track) and wire it |
| H10 | No environment-promotion model; "self-service" is Terraform code-surgery `[system]` | No GitHub `environment:` gates or approvals; `examples/` ships only `dev.tfvars`; onboarding a team means hand-editing `envs/gcp/workload/main.tf` | Add promotion gates (GitHub environments + required reviewers) and a data-driven team/project registry so adding a workload is config, not code |

### Medium

- **Cross-root contract tests are circular `[iac]`.** `envs/gcp/workload/tests/root.tftest.hcl:32-50` hand-writes the `environment_config` shape it then asserts, so a producer rename passes unchanged. These tests cannot catch the failure mode they advertise. Derive the mock from the producer output, or add a producer-side shape test that fails in lockstep. (This weakens a deliverable from this cycle's remediation.)
- **No app-layer secret store for GCP; Supabase secrets land in state `[security/system]`.** No GCP Secret Manager module exists. `modules/supabase/vault-secrets/main.tf` passes plaintext values through Terraform state and runner env. Add a GCP Secret Manager module; drive the Supabase reconcile from a secret reference, not a state-resident value.
- **Break-glass principal is an unmanaged, unmonitored string `[security]`.** Every SCP exempts `break_glass_role_arn`, but the repo never creates, scopes, or alarms on it. Manage it in-repo with a tight trust policy and a mandatory alarm on its assumption.
- **No observability of the control plane itself `[cicd]`.** No alert on a failed TFC apply, a stalled audit-log sink, or an org-policy/SCP mutation. Ship a control-plane dashboard and alert set.
- **No broken-apply recovery runbook `[cicd]`.** Guidance is roll-forward only. Add a runbook for TFC state rollback, `-target` convergence, and taint-vs-import.
- **No H3 state-migration tooling for existing adopters `[iac]`.** The split is a cross-state move with no `removed{}`+import or script shipped. Add migration stanzas and a runbook step.
- **Image registries and ingress primitives are orphaned `[system]`.** ECR/Artifact Registry and the LB/API-gateway/CDN modules have no producer or consumer and no "service + ingress + cert + DNS" golden path. They light up only once C1 lands.
- **13-root apply ordering is enforced only by runtime remote-state errors `[cicd]`.** No sequencing wrapper or DAG. A wrong order gives a cryptic error. Add a `make stand-up-aws`/`stand-up-gcp` sequencer.
- **Drift check conflates real drift with un-applied config and can time out `[cicd]`.** `plan-only + refresh` flags merged-but-unapplied commits as drift; the 10-minute poll ceiling can fail large org plans. Document the caveat; make the ceiling configurable.
- **CMEK protection defaults to SOFTWARE, not HSM, for governance keys `[security]`.** `modules/gcp/governance/kms/main.tf:25`. Default governance keys to HSM.

### Low

- Root "pass-through tax": `envs/saas` re-declares and forwards ~32 variables one-to-one `[iac]`.
- SaaS co-locates both providers in one root, softening the "any combination" claim for that layer `[iac]`.
- Lock-file platform discipline is inconsistent (roots 3-platform, modules single-platform) vs the documented "dual-platform" standard `[iac]`.
- AWS organization root ships apply-ready defaults with placeholder `example.com` account emails `[iac]`.
- Dependabot excludes Terraform providers, so provider CVEs are never surfaced `[cicd]`.
- CODEOWNERS is a bus-factor of one, which makes the "CODEOWNERS review + 1 approval" gate unenforceable without bypass `[cicd]`.
- Release-tag protection example omits the `aws-*`/`saas/*` tags the apply workflow acts on `[cicd]`.
- RCP data perimeter covers only 5 services (s3, sts, kms, sqs, secretsmanager) `[security]`.
- Green scanners suppress the exact WORM/CMEK checks an auditor inspects; track these as risk-accepted items in a Statement of Applicability `[security]`.

---

## The defaults decision (an honest correction)

This cycle's remediation deliberately kept VPC-SC in dry-run, the WORM lock off,
and the inert controls opt-in, on the reasoning that you should not blind-flip
breaking or irreversible defaults in a template. The security review is right that
this reasoning fails the stated goal: a buyer standing up a company fast takes the
defaults and ships an org that looks hardened and is not.

Both are correct about different risks. The reconciliation:

- Add one `production_hardening = true` preset (a root variable or a committed
  `prod.tfvars`) that flips every safe-to-enable control on together: VPC-SC
  enforced, CIS alarms on, CMEK enforcement wired, secrets baseline on, privilege
  split on, HSM governance keys.
- Default-on the org-node IAM deny policy that contains the admin SA (C2). This is
  additive and reversible, so it does not carry the "breaking default" risk.
- Keep only the **irreversible** audit-bucket WORM lock as an explicit opt-in,
  because a locked retention policy cannot be undone. Document it in the hardening
  preset as the one switch the operator must set deliberately.

This keeps the "do not blind-flip irreversible things" principle while making the
hardened posture the easy default, not a scavenger hunt through known-gaps.md.

---

## What is genuinely strong

Do not let the above obscure the quality of the foundation.

- **AWS security design is audit-grade.** `scp-deny-tamper.json` correctly does not
  exempt the Terraform run role from disabling security services, so a pipeline
  compromise cannot kill CloudTrail/GuardDuty/Config. The log-archive bucket is
  real WORM (Object Lock COMPLIANCE, versioning, SSE-KMS, 4x public-access block,
  TLS-deny). Org CloudTrail is CMK-encrypted, multi-region, with log-file
  validation. RCP adds PrincipalOrgID and confused-deputy denies.
- **Supply chain is strong.** Every GitHub Action is full-SHA pinned; no static
  cloud keys in CI (GCP WIF + AWS TFC dynamic credentials); Trivy (blocking) +
  Checkov + GitLeaks gates; terraform-docs download is checksum-verified; release
  provenance verifies the applied run's commit equals the tag before publishing.
- **IaC idioms are modern and consistent.** 273 `for_each` uses with essentially
  no index-fragile `count`-over-list; structural tests that assert real planned
  attributes plus `expect_failures` validation suites; remote-state outputs carry
  "keep stable" contract warnings; no cross-root `depends_on` hacks; real
  scaffolding templates under `templates/`.
- **GCP org policies are enforced by default and CIS-aligned** (SA key creation
  and upload disabled, public-access prevention, uniform bucket-level access,
  Shielded VM, external-IP deny, domain-restricted sharing, resource locations).
- **Documentation and day-2 breadth are rare.** 18 runbooks, architecture docs, a
  cross-cloud capability table, and a candid known-gaps register. A competent team
  can reach a governed org without the authors.
- **Fail-closed CI aggregator** treats a skipped matrix leg as failure, closing the
  empty-matrix merge hole, and gives branch protection one stable context.

---

## Remediation roadmap (ordered by leverage)

1. **Contain the GCP admin identity (C2).** Default-on org IAM deny policy;
   finish the privilege split. Smallest change, removes the worst escalation path.
2. **Codify the Terraform Cloud layer (C3).** One `tfc-admin` root. Turns "hours
   of console clicking, config rot" into reviewable code. Highest leverage for both
   "fast" and "for years".
3. **Ship the `production_hardening` preset and default-safe guardrails (H1,
   plus the defaults decision).** Make hardened the easy default.
4. **Fix the correctness-and-confidence layer (C4, H5, H6, H7).** Account guard,
   workflow renames, require the TFC plan check, fix QUICK_START §4. Cheap; removes
   active foot-guns.
5. **Build the missing platform (C1).** Runtime modules, a reference delivery
   pipeline, a managed data layer, an ingress golden path, app observability, and
   a promotion model (H9, H10). This is weeks of work and the real product gap.
6. **Harden the seams (H3, H4, contract tests, migration tooling).** Decompose the
   host god-module, single-source `environments`, make the contract tests bind
   producer to consumer, ship the state-migration path.

---

## Remediation status (updated 2026-11-05)

Resolved since this audit was written, verified locally (CI runners are unfunded,
so `terraform test`, `checkov`, and `make docs-check` are the gate):

| # | Finding | How it was resolved |
|---|---------|---------------------|
| C1 | No application runtime, delivery pipeline, data layer | Runtime modules (Cloud Run, GKE Autopilot, ECS Fargate), data modules (Cloud SQL, RDS Aurora, Secret Manager), an SLO module, the `app-ingress` front door, a reference delivery pipeline, and the `deploying-a-service.md` golden path. All opt-in and secure by default. |
| C2 | Uncontained GCP `terraform-admin` SA | Opt-in org-node IAM deny policy plus privilege-split guidance. |
| C3 | Manual Terraform Cloud workspace layer | `tfc-admin` root and `modules/tfc/workspace` codify all workspaces with the `tfe` provider. |
| C4 | No `allowed_account_ids` guard | `allowed_account_ids` added to the AWS providers; management-account guard on the organization root. |
| H3 | 756-line host god-module | Split by concern into parallel `*.tf` files (file-level, not a re-parenting), proven behavior-identical by a declaration-inventory diff. |
| H10 | No promotion model; onboarding is code-surgery | Data-driven `service_teams` registry (a team is a map entry) and [promotion.md](../runbooks/promotion.md). |
| M-iac | Circular cross-root contract tests | Producer-side shape test binds `environment_config` keys at `gcp-projects`. |
| M-sec | No GCP app-secret store | `modules/gcp/data/secret-manager`; the golden path reads secrets by reference. |
| M-ops | No broken-apply recovery runbook | [apply-recovery.md](../runbooks/apply-recovery.md). |

Still open: **H9** (SaaS integration needs an architecture decision), **M3**
(break-glass role management and alarm), control-plane self-observability, AWS and
GKE delivery-pipeline parity, and CODEOWNERS (a repo-ownership change).

---

## Bottom line

This is one of the stronger landing-zone codebases a reviewer will see. The
governance, AWS security design, supply-chain rigor, test discipline and
documentation are above what most enterprises achieve, and the author plainly
knows the 2026 idioms.

Judged against its own promise, it is not yet a company-starter kit. It is a
beautifully guarded shell with the lights on and no rooms to live in. An expert
who clones it today gets a governed empty org in a day or two, then faces weeks of
unshipped platform work (runtime, pipeline, data, ingress, promotion) plus a
security posture that looks hardened but is not by default, a GCP automation
identity that can erase its own guardrails, and a Terraform Cloud layer assembled
by hand. None of this is unfixable. The foundation is real. The building has not
been started.
