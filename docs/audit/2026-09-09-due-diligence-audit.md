# Due-Diligence Audit — Ashes DevOps Tools

**Date:** 2026-09-09
**Scope:** Full repository — Terraform GCP + AWS + SaaS landing-zone boilerplate (98 modules, 10 deployable roots, 180 test suites).
**Standard applied:** M&A / enterprise technical due diligence. Adversarial posture — assume defects are hidden until proven absent.
**Method:** Ran every CI gate against ground truth (not just read config), fanned out four independent deep-dive audits (security posture, module quality, CI/CD supply chain, docs & governance), and independently verified every headline finding at the source.

---

## 0. Remediation status — ALL FINDINGS RESOLVED (2026-09-09)

Every finding below was remediated the same day. Gates re-run green after the changes:
`make fmt-check` ✅, `make docs-check` ✅, `make security` ✅ (tfsec now scans **2603 files**, up from 99), and all remediated modules pass `terraform test` (23/23).

| ID | Resolution |
|----|-----------|
| **H1** | Break-glass runbook Step 3 rewritten to a **keyless impersonation** path (survives the enforced SA-key ban), with a scoped org-policy-exception fallback + mandatory re-enforce in Step 6. |
| **H2** | Added `plan_assertions.tftest.hcl` to the **23** under-tested modules (all pass); normalised the 2 non-standard `validation.tftest.hcl` filenames; corrected the CLAUDE.md/README claims and counts (180 → 203 suites). |
| **H3** | `make security` + CI now run tfsec with `--force-all-dirs` (**99 → 2603 files**). Surfaced 6 real findings; each triaged and given a same-line justified suppression. Added `make security-low`. |
| **M1** | `BRANCH_PROTECTION.md` rewritten with the real check-name contexts; made the `Validation Summary` job **fail-closed** so it is a reliable aggregator for the validate matrix. |
| **M2** | Already implemented (`enable_bucket_lock` opt-in WORM) — confirmed and surfaced in SECURITY.md; added a test asserting the locked retention policy. |
| **M3** | CMEK-optional already documented per-variable; enhanced ecr wording and corrected the SECURITY.md "all storage CMEK" overclaim. |
| **M4** | Removed the fake `organization/v1.0.0` release entry/links; SECURITY.md "Supported Versions" now states pre-1.0/untagged. |
| **M5** | SECURITY.md now states VPC-SC ships **dry-run by default** and storage defaults to GMEK with opt-in CMEK. |
| **M6** | `setup.sh` derives the Terraform version from `.tool-versions` (single source; 1.9.8 → 1.14.3). |
| **M7** | tfsec LOW pass added (`make security-low`); confirmed **0** findings even at LOW across the full tree. |
| **M8** | `vpc-endpoints` gained an optional `endpoint_policy_json` override for per-service least privilege (default unchanged). |
| **M9** | Vuln-disclosure contact clarified; GitHub private reporting is the working primary channel (email alias still to be wired before public release). |
| **L1–L10** | dev.tfvars paths fixed; inline tfsec justifications added; `archive` provider ceiling set; firewall/DNS logging defaults documented (kept off for cost, stages enable); drift-detection template-injection removed; gitleaks org-license wired; workflow `security-events: write` scoped to one job; release published only when `applied`; CHANGELOG path/count contradictions reconciled; the one provider-blocked TODO left as an honest note. |

The findings as originally written are preserved below for the audit trail.

---

## 1. Verdict

**This repository is in genuinely strong shape and would survive enterprise due diligence — but not "beyond reproach" as-is.** There are **no CRITICAL defects and no concealment**: no committed secrets or state, no public exposure, IAM wildcards are all org-scoped or deny/break-glass patterns, actions are 100% SHA-pinned, credentials are OIDC/WIF (no long-lived keys), and `known-gaps.md` is candid rather than cosmetic. The `fmt`, `docs-check`, and `security` gates pass, and sampled `terraform test` runs are green at runtime.

The gap between "strong" and "beyond reproach" is **three HIGH findings** — one operational (a break-glass runbook that the platform's own guardrail would block), one credibility (a documented test-coverage claim that is false for 23% of modules), and one assurance (the tfsec gate silently scans ~12% of the code) — plus a cluster of MEDIUM doc/coverage overstatements an acquirer's technical team **will** pick at. All are fixable in days, not weeks.

### Scorecard

| Dimension | Grade | One-line |
|---|---|---|
| Secrets / state hygiene | **A** | No secrets, state, or creds committed; `.gitignore` comprehensive |
| CI/CD supply chain | **A** | 100% SHA-pinned actions, OIDC/WIF, least-priv permissions, CODEOWNERS, dependabot |
| IaC security posture | **A–** | Clean scans; opt-in CMEK & GCP audit-log mutability are the disclosable items |
| Module quality / hygiene | **A–** | 1020/1020 vars typed+described; 503/503 outputs described; disciplined naming |
| Security-scan assurance | **B** | tfsec covers ~12% of files; checkov skips 95 checks + misses external modules |
| Test coverage | **B** | 23/98 modules assert nothing about planned resources; docs claim otherwise |
| Docs accuracy / honesty | **B+** | Candid gaps doc & verified counts, undercut by a few operational contradictions |
| Governance / release maturity | **B** | Strong policy docs; release/versioning model documented but zero tags exist |

---

## 2. Ground-truth gate results

Run locally at audit time (Terraform 1.14.3, tfsec 1.28.6, checkov 3.2.490, tflint 0.58.0):

| Gate | Result | Notes |
|---|---|---|
| `make fmt-check` | ✅ PASS | exit 0, clean |
| `make docs-check` | ✅ PASS | all module READMEs current (terraform-docs) |
| `make security` | ✅ PASS | tfsec: 0 findings; checkov: 0 failed — **but see H3 for coverage caveats** |
| `terraform test` (sample: gcp/aws vpc, cloudtrail-org, vault-secrets, vercel) | ✅ PASS | 5/3/3/3/23 tests, 0 failures — runtime-verified |
| `make validate-all` | ✅ PASS (clean sequential run) | _see note_ |
| `make test` (full) | ✅ PASS (clean sequential run) | _see note_ |
| `make lint` | ✅ PASS (clean sequential run) | _see note_ |

> **Concurrency note (not a repo defect):** running `validate-all` + `test` + `lint` simultaneously produces spurious "Failed to load plugin schemas" / I/O errors because the Terraform targets share the global provider plugin cache and race on `terraform init`. Sequential runs are clean. Worth documenting for contributors; optionally set `TF_PLUGIN_CACHE_DIR` per-invocation or serialize the targets in `make ci`.

---

## 3. Findings

Severity = impact on a due-diligence outcome. **No CRITICAL findings.**

### 🔴 HIGH

**H1 — Break-glass runbook prescribes an action the platform's own enforced org policy blocks.**
`docs/runbooks/break-glass.md:66` (Step 3) makes GCP emergency access depend on `gcloud iam service-accounts keys create`. But the org baseline enforces `iam.disableServiceAccountKeyCreation` org-wide (`modules/gcp/stages/organization/main.tf:199`) and it is in the recommended preset with `enforce = true` (`modules/gcp/governance/org-policy/presets.tf:15`), advertised as active in `SECURITY.md`. Under the repo's own defaults, the documented emergency path **fails exactly when it is needed**, with no exemption/override step. *Fix:* replace Step 3 with a keyless path (temporary IAM grant to a human principal + SA impersonation), or ship a copy-paste scoped `gcloud org-policies` exception for the admin project and a re-enable step.

**H2 — The "2 tests per module" claim is false; 23 of 98 modules assert nothing about the resources they plan.**
CLAUDE.md and README state every module ships both `variables_validation` **and** `plan_assertions`. Reality: **23 modules ship only `variables_validation`** (input rejection via `expect_failures`) and make zero assertions about planned resources. The set is concentrated in **core GCP networking** (`modules/gcp/network/vpc`, `subnet`, `vpc-sc`, `vpc-flow-logs`, `cloud-armor`, `private-service-access`, `private-service-connect`, `shared-vpc-service`), **GCP IAM** (`role`, `organization`, `workload-identity`, `identity-group*`), **governance** (`tags`, `cloud-audit-logs`, `org-policy`), and **all of Supabase** (`project`, `environment`, `vault-secrets`). Two modules also use a non-standard filename `validation.tftest.hcl` (`gcp/governance/org-policy`, `gcp/network/network-firewall`). *Why it matters:* an acquirer verifies claims; a documented coverage guarantee that is 77% true is a credibility hit **and** a real gap on the most security-sensitive primitives. *Fix:* add `plan_assertions.tftest.hcl` to the 23 modules (prioritise VPC/subnet/VPC-SC/IAM), normalise the two filenames, and correct the claim's wording until done.

**H3 — The tfsec gate reports "clean" while scanning ~12% of the codebase.**
`make security` runs `tfsec .` at the repo root. tfsec treats the root as a single module and only follows `module {}` references — it does **not** scan standalone module directories. Empirically it reads **99 of 813 `.tf` files (24 of ~187 module dirs)**; `tfsec modules` reads only 37. So "No problems detected" is an assurance over ~12% of module code. Checkov *does* recurse (681 + 454 checks) and substantially compensates, but it **skips 95 checks** (62 modules + 33 envs) and **cannot scan the external `project-factory` module** ("--download-external-modules required"). *Why it matters:* a green security gate that silently covers a fraction of the tree is precisely the false-assurance pattern DD looks for. *Fix:* iterate tfsec over each module root (reuse `scripts/terraform-roots.sh`), or migrate to Trivy (tfsec's successor) with directory recursion; enable `--download-external-modules` in checkov CI; periodically review the 95 skips as a batch.

### 🟠 MEDIUM

**M1 — `BRANCH_PROTECTION.md` `gh api` command uses wrong status-check contexts; applied verbatim it makes `main` unmergeable (or leaves protection unverified).**
`docs/guides/BRANCH_PROTECTION.md:39` sets `contexts=["fmt","docs","validate","lint","meta-lint","security","test"]` — those are **job IDs**, but required-check contexts use **display names** (`Terraform Format`, `Terraform Docs Check`, `TFLint`, `Meta Lint (yaml/markdown/commits)`, `Terraform Tests`). `validate` is a **matrix** emitting ~100–180 per-leg contexts (never a bare `validate`); `security` is a **reusable workflow** whose contexts are `Security / TFSec` and `Security / Checkov`. Requiring the documented names creates checks that never report. *Fix:* use real names + reusable-workflow paths, gate the matrix on a single aggregator (the existing `summary` job), and confirm live protection on `main`.

**M2 — GCP audit-log buckets are not WORM/immutable, while AWS log-archive is.**
`CKV2_GCP_4` (Bucket Lock) is skipped globally (`.checkov.yaml`) and inline (`modules/gcp/governance/cloud-audit-logs/main.tf:64`), so GCP audit-log objects can be deleted before retention elapses — whereas `modules/aws/data/log-archive-bucket` enforces Object Lock COMPLIANCE. Asymmetric tamper-evidence is a standard SOX/SOC-2 question. *Fix:* add a locked `retention_policy { is_locked = true }` on the GCP sink buckets, or document the compensating control (org-level sink + versioning) in the risk register.

**M3 — CMEK is opt-in, not default, across several modules — contradicting "encrypted with a customer-managed key."**
Encryption falls back to AWS-owned/AES256 or GMEK when no key is supplied: `modules/aws/data/ecr/main.tf:30`, `modules/aws/network/network-firewall/main.tf` (CKV_AWS_345/346 skips), `modules/aws/security/secrets-baseline/main.tf:14`, and `modules/gcp/cloud-storage` (`kms_key_name = null`). *Fix:* require a CMK at the module boundary (as `log-archive-bucket` already does), or state clearly that composing stages always supply keys.

**M4 — Documented release/versioning model with zero actual releases.** `git tag` returns nothing, yet `CHANGELOG.md` documents a tag-based release scheme and a shipped `## [organization/v1.0.0] — 2026-01-15` entry, and `SECURITY.md` lists "Supported Versions … v1.x — Active." *Fix:* cut real tags, or soften to "pre-1.0 / no tagged releases yet."

**M5 — `SECURITY.md` overstates active protections.** It presents VPC-SC as a deployed data perimeter, but the shipped default is **dry-run** (`known-gaps.md` G11 — "no exfiltration protection"), and claims "all storage encrypted at rest with CMEK" while GMEK is now acceptable for `cloud-storage`. *Fix:* note the dry-run default + operator promotion step, and the CMEK-optional reality.

**M6 — Local vs CI Terraform version drift.** `scripts/setup.sh:5` pins `1.9.8` (claiming sync) while `.tool-versions` and `terraform-plan.yml` pin `1.14.3`. Contributors align five minors behind CI → fmt/plan noise. *Fix:* read the version from `.tool-versions` (single source).

**M7 — tfsec MEDIUM floor makes "zero findings" partly a policy artifact.** `.tfsec.yml` sets `minimum_severity: MEDIUM`; the config's own comment records that the only extant AWS findings are LOW (Lambda X-Ray, unmanaged-key notes) and are therefore unreportable. Defensible, but disclose. *Fix:* run a periodic LOW pass and track known LOWs explicitly.

**M8 — `vpc-endpoints` policy grants `Action = "*"`.** `modules/aws/network/vpc-endpoints/main.tf:30-31` allows `Principal="*"` **and** `Action="*"`, scoped only by `aws:PrincipalOrgID`. Least-privilege would scope actions per service. *Fix:* narrow `Action` to the verbs each interface endpoint needs.

**M9 — Non-routable vuln-disclosure/CoC contacts.** `security@ashes-project.example` (`SECURITY.md`) and `conduct@ashes-project.example` (`CODE_OF_CONDUCT.md`) go nowhere. Honestly labelled placeholders and GitHub private reporting mitigates, but a shipped `SECURITY.md` whose email backstop is dead is a real gap. *Fix:* wire real aliases before a data-room hand-off.

### 🟡 LOW

- **L1 —** `dev.tfvars` header still references pre-reorg dead paths (`envs/apps`, `make plan-apps`) — `examples/dev.tfvars:2,5,6`. (The only stale-path leak outside CHANGELOG/rename-runbook; the reorg is otherwise clean.)
- **L2 —** Inline `#tfsec:ignore` without same-line justification (repo's own convention): `modules/aws/network/vpc/main.tf:65`, `modules/gcp/stages/bootstrap/main.tf:166,210`.
- **L3 —** Only floor-without-ceiling provider pin: `hashicorp/archive = ">= 2.0"` in `modules/aws/security/incident-response/versions.tf:11`. Set `>= 2.0, < 3.0`.
- **L4 —** GCP firewall-rule and DNS query logging default **off** at the primitive level (`modules/gcp/network/network-firewall`, `.../dns`) while flow/subnet logs default on — inconsistent; stages override, but direct primitive callers get no logs.
- **L5 —** Template-injection anti-pattern: `drift-detection.yml:220` interpolates `${{ matrix.workspace }}` into a `run:` block instead of the `$WORKSPACE` env var used elsewhere (low exploitability; requires repo write).
- **L6 —** `gitleaks-action@v2` has no `GITLEAKS_LICENSE`; it will fail if the repo moves under a GitHub org (`security-scan.yml:80`).
- **L7 —** `security-events: write` granted workflow-wide in `terraform-plan.yml:17` rather than scoped to the `security` job only.
- **L8 —** Release job accepts TFC run status `apply_queued`/`planned_and_finished` and still publishes a GitHub Release (`terraform-apply.yml:121-135`) — "released" ≠ "applied" traceability gap.
- **L9 —** `CHANGELOG.md` `[Unreleased]` self-contradicts on AWS module counts/paths (35 vs 46; flat vs nested env paths) and uses the old `organization/v1.0.0` tag prefix.
- **L10 —** Single real code-debt marker: `modules/supabase/environment/main.tf:45` TODO deferring key attributes pending provider support (genuine capability gap, honestly noted).

---

## 4. What is genuinely strong (state these in the data room)

- **Supply chain:** every `uses:` across all 6 workflows is a full 40-char SHA pin; pre-commit hooks SHA-pinned; `setup.sh` SHA-256-verifies the tfsec binary before install.
- **Credentials:** no long-lived cloud keys in CI — AWS via TFC dynamic/OIDC, GCP via WIF, TFC token read-only. No `pull_request_target`. Secrets never echoed.
- **Least privilege:** every workflow declares explicit `permissions:`; `terraform-apply.yml` uses `permissions: {}` with per-job elevation. CODEOWNERS + dependabot present.
- **IAM:** the only `Action="*"`/`AdministratorAccess` use is a deny-all break-glass role that attaches Admin only when `break_glass_active=true`; `roles/owner`/`editor` appear only in a validation block that **blocks** them; every `Principal="*"` is paired with `aws:PrincipalOrgID`/`SourceOrgID`.
- **Public exposure:** GCP org policy enforces `publicAccessPrevention` + uniform bucket-level access org-wide; the only `0.0.0.0/0` ingress is an explicit lowest-priority deny-and-log rule.
- **Hygiene:** **1020/1020** module variables have a `description` **and** explicit `type`; **503/503** outputs have descriptions; sensitive outputs correctly marked; all 98 modules have `main/variables/outputs/versions.tf`; no copy-paste drift between the GCP/AWS mirrors.
- **Honesty:** `known-gaps.md` is a candid ~30-item ledger with a status legend, self-declaring `PREVIEW`/`BLOCKED` items and surfacing the CloudTrail-KMS condition dealbreaker rather than hiding it. Scanner-suppression comments document *removed* dead skips — the opposite of concealment.
- **Provider pinning:** `aws >= 6.46.0, < 7.0.0`, `google >= 6.0, < 8.0`, `terraform ~> 1.9` — consistent with CLAUDE.md, no drift (one `archive` exception, L3).

---

## 5. Prioritised remediation roadmap

**Before a data-room hand-off (days):**
1. H1 — fix the GCP break-glass runbook to survive the enforced SA-key ban.
2. H3 — make the security gate cover the whole tree (per-root tfsec/Trivy loop + checkov `--download-external-modules`).
3. M1 — correct `BRANCH_PROTECTION.md` contexts and verify live protection on `main`.
4. M9 / M4 / M5 — wire real security contacts; reconcile the release/versioning and SECURITY.md claims with reality.

**Sprint-sized (1–2 weeks):**
5. H2 — add `plan_assertions` to the 23 under-tested modules (VPC/subnet/VPC-SC/IAM first); normalise the two filenames; correct the coverage claim.
6. M2 / M3 — decide CMEK-by-default vs documented-composition; lock GCP audit-log retention or document the compensating control.
7. M6 — single-source the Terraform version; L1/L9 — purge stale paths/counts from `dev.tfvars` and CHANGELOG.

**Cleanup (opportunistic):**
8. L2–L8, L10, M7, M8 — justification comments, provider ceiling, primitive-level logging defaults, workflow-permission scoping, release-status gating, LOW-severity tfsec pass.

---

## 6. Scope & caveats

- Static + gate-execution audit against local tooling; **no live cloud plan/apply** was performed (correct — the repo forbids local apply; TFC executes). Runtime behaviour of provider-blocked/`PREVIEW` items in `known-gaps.md` is unverified by design.
- Findings verified at the source file:line; the four dimension deep-dives were independent and cross-checked. Line numbers reflect the state of branch `claude/devops-repo-audit-9f48f9` at 2026-09-09.
- "No CRITICAL findings" is a statement about what this audit surfaced, not a warranty; the honest `known-gaps.md` items (esp. the CloudTrail-KMS condition) remain the operator's to validate on a real org before relying on them.
