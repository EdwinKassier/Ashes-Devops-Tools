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
