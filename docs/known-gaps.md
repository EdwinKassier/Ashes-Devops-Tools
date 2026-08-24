# Known Gaps & Preview Features

A single, honest inventory of things that are **not yet done, not yet validated,
or deliberately deferred**. This exists so `CLAUDE.md` can stay a doc of
always-true authoring rules instead of a running bug list, and so a new
maintainer has one place to see what's aspirational vs load-bearing.

Status legend: **OPEN** (a real gap to fix) · **PREVIEW** (code shipped, opt-in,
default-off, not yet validated against a real apply) · **BLOCKED** (waiting on an
upstream/provider capability) · **DECISION** (needs a human call before action).

## OPEN — validate before relying on

- **A1 — CloudTrail KMS grant condition.** `modules/aws/security/cloudtrail-org`
  scopes the log-service KMS grant with `aws:SourceOrgID`, but AWS documents
  `aws:SourceArn` (the trail ARN) as the CloudTrail KMS-key-policy condition
  (`aws:SourceOrgID` is documented for the S3 *bucket* policy). If CloudTrail does
  not emit `SourceOrgID` on its KMS calls, log delivery fails. Only mock-tested.
  **Validate on a real org and switch CloudTrail to `aws:SourceArn` before
  relying on it.** Ref: <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-kms-key-policy-for-cloudtrail.html>

## MODERNIZATION — latest-best-practice gaps (2026 review)

From a 2026 gap analysis of both landing zones against the current AWS SRA and
Google enterprise-foundations / FAST guidance. Both clouds already adhere
closely (see [`landing-zone-conformance.md`](architecture/landing-zone-conformance.md));
these are the specific lags. `SAFE-CONFIG` = a default-off, opt-in code change
that passes `validate` + mock tests; `BEHAVIOR-CHANGING` = needs a real apply or
architectural change and is documented here rather than rushed.

AWS:

- **A5 — single-region backups, no cross-region / air-gapped copy** (MEDIUM,
  BEHAVIOR-CHANGING). `modules/aws/backup/backup-org-policy` writes recovery
  points to one region; there is no `copy_actions` stanza or Logically
  Air-Gapped destination vault. Latest AWS Backup guidance makes cross-region /
  cross-account copy the resilience baseline. Add a `copy_actions` destination +
  second-region vault (needs a real apply). Ref:
  <https://aws.amazon.com/blogs/storage/aws-backup-2025-year-in-review-advancing-recovery-resilience/>
- **A6 — log-analytics primary lags the June-2026 SRA** (MEDIUM, SAFE-DOC done /
  re-plumb BEHAVIOR-CHANGING). The June-2026 SRA names **CloudWatch Unified Data
  Store** the preferred analytics *primary* and Security Lake secondary; this
  zone keeps the S3 WORM archive as the immutable sink (still valid) and treats
  CloudWatch as an out-of-band `awscc` enhancement (A4). Doc framing corrected;
  actually re-plumbing log routing needs a real apply.
- **A7 — Config conformance packs are an empty bring-your-own hook** (MEDIUM,
  SAFE-DOC done / opt-in SAFE-CONFIG). `modules/aws/security/config-org` ships
  the aggregator + pack *resource* but no bundled pack. Optionally ship an
  `Operational-Best-Practices` pack reference defaulting off.

GCP:

- **G6 — Organization Policy custom constraints** — ✅ **SHIPPED opt-in**
  (`custom_org_constraints` on `envs/gcp/organization` → `stages/organization` →
  `org-policy`, default `[]`, mock-tested). CEL resource-shape guardrails now
  wire through to the org node. Remaining follow-ups: migrating the existing
  boolean/list constraints to the `*.managed.*` namespace and adding
  `gcp.restrictNonCmekServices` are still open. Ref:
  <https://docs.cloud.google.com/resource-manager/docs/custom-constraints>
- **G7 — host firewall uses legacy VPC firewall rules, not network firewall
  policies** (HIGH, BEHAVIOR-CHANGING). `modules/gcp/network/network-firewall`
  creates `google_compute_firewall` (legacy per-VPC rules with network tags);
  `stages/host` instantiates it for all tier-to-tier rules. Google directs new
  builds to global/regional **network firewall policies** with IAM-governed
  secure tags. Migration changes rule evaluation → real apply. Ref:
  <https://docs.cloud.google.com/firewall/docs/firewall-policies-overview>
- **G8 — audit-log bucket WORM lock** — ✅ **SHIPPED opt-in**
  (`enable_audit_bucket_lock` on `envs/gcp/organization` → `stages/organization`
  → `cloud-audit-logs`, default `false`, mock-tested). When enabled it applies a
  **locked** retention policy of `audit_log_retention_days` (irreversible — for
  compliance regimes that require tamper-proof retention). Default preserves the
  prior operator-correctable behaviour.
- **G9 — IAM Deny policies** — ✅ **SHIPPED opt-in**. New leaf module
  `modules/gcp/iam/deny-policy` (its own mock tests) wired into
  `stages/organization` at the org node via `iam_deny_policies` (on
  `envs/gcp/organization`, default `[]`). Coarse allow-independent backstop that
  blocks sensitive permissions regardless of roles (deny before allow). Inert
  until populated. Ref: <https://docs.cloud.google.com/iam/docs/deny-overview>
- **G10 — SCC is notification-only; no posture service or tier** (MEDIUM,
  BEHAVIOR-CHANGING). `modules/gcp/governance/scc` wires only Pub/Sub findings
  notification. The security posture service (drift detection) needs SCC Premium
  activated org-wide (a paid, out-of-band apply). A `google_securityposture_posture`
  definition could be added as opt-in scaffolding once a tier exists. Target
  **Premium** — the Enterprise tier sunsets 2027-05-21. Ref:
  <https://docs.cloud.google.com/security-command-center/docs/service-tiers>
- **G11 — VPC-SC dry-run-first default** — ✅ **SHIPPED**. Flipped the default
  of `vpc_sc_enable_dry_run` (hub, via `envs/gcp/organization` + `network-hub`)
  and the per-perimeter `enable_dry_run` (host stage) and the workload perimeter
  (`envs/gcp/workload`) from enforce to **dry-run**, matching Google's
  "start in dry-run, promote after validating violation logs" guidance. **Action
  for operators:** promote to enforcement (`vpc_sc_enable_dry_run = false`) once
  the violation logs are clean — dry-run gives no exfiltration protection, so do
  not leave a production perimeter in dry-run. Ref:
  <https://docs.cloud.google.com/vpc-service-controls/docs/dry-run-mode>
- **KMS Autokey / HSM-for-sensitive** (LOW, SAFE-CONFIG, future). No Cloud KMS
  Autokey; CMEK defaults to `SOFTWARE` protection (HSM is per-key selectable).
  Autokey (GA 2024, dedicated-project storage GA 2026) and HSM-by-default for
  audit/SCC keys are maturity improvements, not deficiencies.
- **Flat folder tree** (LOW, BEHAVIOR-CHANGING, documented divergence). Folders
  are parented directly at the org (one per env + shared), not under a
  prod/nonprod grouping layer. Deliberate simplification for a smaller org;
  a grouping layer would let tier-level guardrails inherit by folder.

## PREVIEW — opt-in, default-off, not yet validated (mock-tested only, no on-path coverage)

Enable only after validating in a real/test org. Each defaults to prior behaviour.

- **G3 — bootstrap SA privilege split** (`enable_privilege_split`,
  `modules/gcp/stages/bootstrap`). **Self-declared INCOMPLETE**: fully activating
  the split also requires WIF-binding the resman SA and switching downstream
  impersonation. Do **not** enable as-is.
- **G4 — dedicated logging project** (`logging_project_id`,
  `modules/gcp/stages/organization`). Also needs cross-project CMEK grant wiring.
- **G5 — VPC-SC perimeter expansion** (`vpc_sc_additional_restricted_services`,
  `vpc_sc_ingress_identities`, `modules/gcp/stages/network-hub`). Set the ingress
  identity BEFORE expanding services or an enforced apply is blocked.
- **A3 — dedicated Identity Center account** (`identity_account_id`,
  `modules/aws/stages/security`). Point at a real dedicated identity account.
- **A4 — CloudTrail CloudWatch Logs + CIS alarms** (`enable_cloudwatch_logs`,
  `modules/aws/security/cloudtrail-org`). See A1: supply a `logs.*`-granted CMK
  via `cloudwatch_logs_kms_key_arn`, and note the break-glass alarm lives in a
  different account.

## Capability parity (2026 review)

A capability-table audit found several `—` cells that were **real missing
modules**, not true "not applicable". Closed by adding modules on the lagging
side (all mock-tested, secure defaults):

- **Load balancing** — added `modules/aws/network/load-balancer` (ALB/NLB) ↔ GCP `network/internal-lb`.
- **API gateway** — added `modules/aws/network/api-gateway` (API Gateway v2) ↔ GCP `network/api-gateway`.
- **CDN / edge** — no new module; corrected a **doc mis-mapping**: AWS CloudFront already lives in `modules/aws/security/edge-security`, not `—`.
- **Private CA** — added `modules/gcp/governance/private-ca` (CAS) ↔ AWS `data/private-ca`.
- **Scheduled backups** — added `modules/gcp/backup/backup-plan` (snapshot schedules) ↔ AWS `backup/*`.
- **Metrics / dashboards** — added `modules/aws/ops/cloudwatch` (alarms + SNS + dashboard) ↔ GCP `monitoring/*`.
- **Image registry** — added `modules/aws/data/ecr` ↔ GCP `artifact-registry`.
- **Hybrid VPN** — added `modules/aws/network/vpn` (Site-to-Site, IKEv2/AES-GCM, TGW or VGW) ↔ GCP `network/vpn` (HA-VPN).
- **Fleet / patch management** — added `modules/gcp/ops/os-config` (VM Manager patch deployments) ↔ AWS `ops/systems-manager`.

**Remaining `—` cells are intentional asymmetries, not gaps:**

- **GCP IPAM** — Google has no distinct IPAM product; CIDR planning is per-project subnets. AWS IPAM has no GCP analogue to modularize.
- **Firebase** (`modules/gcp/firebase/project`) — GCP-specific; no AWS equivalent (Amplify is a different, niche product).
- **NAT / VPC flow logs** — on AWS these are attributes of the `network/vpc` module (native), whereas GCP exposes discrete `network/nat` and `network/vpc-flow-logs` modules. Same capability, different modularization; not a missing module.
- **GCP service-quotas** — GCP quota management (consumer overrides) differs enough that no parity module is warranted today; AWS `governance/service-quotas` has no clean GCP mirror.

## BLOCKED — waiting on provider capability

- **S1 — Supabase new API keys.** The `supabase/supabase` provider (`~> 1.0`)
  does not yet expose `sb_publishable_`/`sb_secret_` on `supabase_apikeys`; the
  module uses the legacy JWT keys, which Supabase deprecates end-2026. Expose the
  new keys as outputs once the provider supports them.
- **S4 — Vercel write-only secret values (`value_wo`).** Requires vercel provider
  **5.x** (pinned `~> 4.0`, 4.8.2 rejects `value_wo`) **and Terraform ≥ 1.11**.
  Once the Vercel major bump lands, move env-var values to `value_wo` and retire
  the SHA256 drift-hack. (GCP/Supabase secrets can adopt write-only sooner — the
  Terraform floor was raised off 1.9.8, and the google provider already supports it.)

## DECISION — needs a human call

- **Behaviour-changing security defaults** (not applied, would change posture):
  packet-mirroring default mirrors all traffic; vpc-peering exports public-IP
  subnet routes; the shared VPC-endpoint policy is `Action="*"`.
- **tfsec → Trivy PR gate.** tfsec is EOL (Aqua → Trivy). Trivy already runs
  post-merge; promoting it to the PR gate is a scanner swap that may surface new
  findings — validate what Trivy reports before flipping the gate.
- **`host` stage decomposition.** `modules/gcp/stages/host` (~2,000 LOC) is
  large-but-cohesive; a targeted split (firewall / egress / advanced sub-stages)
  is optional maintainability work, not a bug.
- **Toolchain currency automation.** Dependabot tracks GitHub Actions only
  (terraform-ecosystem intentionally omitted — provider majors broke `validate`).
  Consider Renovate for grouped, compatibility-aware provider bumps.
