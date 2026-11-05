# Production Hardening Runbook

The landing zone ships several controls **opt-in and default-off**. This is
deliberate: some are irreversible, some need content you must supply, and the
repo has never been applied, so defaulting them on would be unsafe. This runbook
is the checklist to turn them on for a production environment, and the inverse
(cost right-sizing) for non-production.

Each item names the variable, the file, and the apply-time risk. Validate each on
a real organization before relying on it (see the main audit finding M0).

## 1. VPC Service Controls: promote from dry-run to enforced (audit M2)

The perimeter ships in **dry-run** (`vpc_sc_enable_dry_run = true`). Dry-run gives
**no exfiltration protection** — it only logs what enforcement *would* block.
Google's guidance is to start in dry-run and promote only after the violation
logs are clean. Do not leave a production perimeter in dry-run.

Promotion steps:

1. Apply with the dry-run default and let real traffic run for a representative
   period (at least one full business cycle).
2. Review the dry-run violation logs in Cloud Logging
   (`protoPayload.metadata.dryRun = true`). Every entry is a request that
   enforcement would block.
3. For each legitimate violation, add the identity or service to the ingress
   policy **before** flipping. Set `vpc_sc_ingress_identities` on
   `envs/gcp/organization` to the specific automation identities, and scope the
   ingress to the services they need (do not leave it as the default wildcard;
   see audit finding M2).
4. When the logs show only expected blocks, set `vpc_sc_enable_dry_run = false`
   (hub, via `envs/gcp/organization`), the per-perimeter `enable_dry_run` on the
   host stage, and the workload perimeter on `envs/gcp/workload`.
5. Apply and confirm no legitimate traffic breaks. Keep the dry-run logs for one
   more cycle as a rollback signal.

**Staging later changes on an enforced perimeter.** Once enforced, you no longer
have to drop back to dry-run to trial a change. The vpc-sc module renders the
enforced `status` and a separate dry-run `spec` when any `dry_run_*` override is
set (`dry_run_restricted_services`, `dry_run_ingress_policies`,
`dry_run_egress_policies`). Root knobs: `vpc_sc_dry_run_restricted_services`
(`envs/gcp/workload`) and `vpc_sc_dry_run_additional_restricted_services`
(`envs/gcp/network-hub`). Validate the delta's dry-run violations, then copy it
into the enforced input and clear the override.

**Prod guard.** `envs/gcp/workload` (check `vpc_sc_enforced_in_prod`) and
`envs/gcp/network-hub` (check `hub_vpc_sc_enforced_when_prod_present`) emit a plan
**warning** when a production-like environment (name contains `prod`) has no
perimeter or a dry-run one. It warns rather than fails so the dry-run rollout
above stays possible.

## 2. Inert controls to enable for production (audit M3)

These ship off because enabling them changes posture in ways that need a real
apply or a human decision. Enable them per environment, highest-value first.

| Control | Enable with | File | Apply-time risk |
|---|---|---|---|
| IAM Deny policies (GCP) | populate `iam_deny_policies` | `envs/gcp/organization` → `modules/gcp/iam/deny-policy` | Ships empty (inert). Define deny rules carefully: a deny applies before allow and can block legitimate automation. Test in a non-prod org first. |
| Config conformance packs (AWS) | supply a pack to `config-org` | `modules/aws/security/config-org` | Adds per-evaluation cost and may surface many findings at once. Start with one AWS-managed Operational-Best-Practices pack. |
| CMEK (AWS/GCP) | pass a key ARN/name at the module boundary | per module (e.g. `ecr`, `network-firewall`, `cloud-storage`) | Without a key, encryption falls back to an AWS-owned key or GMEK. Supplying a CMK is safe; requiring it can break a module that is not given one. |
| **Audit-log WORM lock (GCP)** | `enable_audit_bucket_lock = true` | `envs/gcp/organization` → `cloud-audit-logs` | **IRREVERSIBLE.** A locked retention policy cannot be shortened or removed. Enable only for a compliance regime that requires tamper-proof retention, and only once the retention period is final. This is why it is **not** default-on. |
| AWS CloudTrail → CloudWatch Logs + CIS alarms | `enable_cloudwatch_logs = true` | `modules/aws/stages/security` | Supply a `logs.*`-granted CMK via `cloudwatch_logs_kms_key_arn`. See audit A1/A4. |

The WORM lock is the one item that must stay opt-in: an irreversible default in a
template is a footgun, so the best-practice choice is to keep it off and enable it
deliberately.

## 3. Non-production cost right-sizing (audit F5, F2)

For dev, sandbox, and throwaway environments, cut the always-on cost with the
presets in [`examples/presets/`](../../examples/presets/):

- Network: `nonprod-aws-network.tfvars` (`az_count = 1`, `enable_network_firewall = false`).
- Security: `nonprod-aws-security.tfvars` (`enable_security_lake = false`, `enabled_security_services = []`).

Deeper cuts, now exposed as `envs/aws/security` root variables (FinOps F5):

- `config_record_all_supported = false` — Config is most expensive in record-all mode.
- `guardduty_enable_ebs_malware_protection = false` — agentless EBS malware scanning.

Both are in `examples/presets/nonprod-aws-security.tfvars`.

Keep the full posture for production. See the cost model in
[`docs/audit/2026-11-04-finops-deep-dive.md`](../audit/2026-11-04-finops-deep-dive.md).

## Contain the automation identity (audit C2)

The GCP `terraform-admin` service account holds org-wide roles (orgpolicy,
accesscontextmanager, logging, iam.securityAdmin). It is impersonable by GitHub
Actions and Terraform Cloud. A compromise of CI or the WIF trust therefore lets
an attacker remove the guardrails and erase the audit trail. Unlike AWS (where an
SCP denies the run role from disabling security services), GCP has no equivalent
by default. Two controls, applied together:

### 1. Per-stage identities (the structural fix, default on)

Every TFC workspace runs as its own service account, split by run phase
(Cloud Foundation Fabric FAST pattern): `<prefix>-<stage>-plan` (read-only) and
`<prefix>-<stage>-apply` (only the roles that stage manages) for bootstrap,
organization, projects and network-hub, plus `<prefix>-wl-<env>-plan|apply` with
**no org-level roles** (gcp-projects grants them their env folder only). WIF
bindings key on `workspace:run_phase` (or the immutable workspace ID), so a PR's
speculative plan can only ever obtain a read-only identity. The phase-0
`terraform-admin` SA is used by humans for the first gcp-bootstrap apply only.
The GitHub Actions pool is off by default (`enable_github_wif = false`, kept off by
`examples/presets/prod-gcp-bootstrap.tfvars`). See `docs/runbooks/bootstrap.md`.

### 2. Deny-policy backstop (audit C2/C3)

`enable_admin_containment = true` (gcp-organization; **on** in
`examples/presets/prod-gcp-organization.tfvars`) adds an org-node IAM deny policy
`contain-admin-identity` with two rules. Both deny `principalSet://goog/public:all`
and exempt only `containment_exempt_principals` (your break-glass group).

| Rule | Scope | Denied permissions |
|---|---|---|
| 1 | Whole org (no condition) | `logging` `sinks.update`, `sinks.delete`, `exclusions.create/update/delete`, `buckets.delete`; `accesscontextmanager` `servicePerimeters.update/delete/replaceAll/commit`, `policies.delete` |
| 2 | Resources tagged `containment/protected`: the audit bucket, its access-log bucket and the audit CMEK keyring (keys and versions inherit the tag) | `storage` `buckets.delete`, `buckets.setIamPolicy`, `objects.delete`; `cloudkms` `cryptoKeyVersions.destroy`, `cryptoKeys.setIamPolicy` |

IAM deny conditions can match **only resource tags**, so rule 2 uses a tag to
reach the audit bucket rather than every bucket in the org.

These permissions are **not** in Google's deny-supported list, so the policy can't
include them. Each one has an alert instead:

- `iam.denypolicies.update` / `iam.denypolicies.delete`: a deny policy can't
  protect itself. The `deny_policy_change` alert covers this.
- `orgpolicy.policy.set`: this one is deliberately left open. Terraform uses it on
  every baseline change. The `org_policy_change` alert covers it.

**Operational consequence.** Terraform legitimately calls `sinks.update` and
`servicePerimeters.update`. Once containment is on, any change to any logging
sink, exclusion or VPC-SC perimeter in the org fails with a deny for the
automation SA. That includes workload perimeters and flow-log sinks. Run such
changes as a break-glass principal, or add a dedicated, tightly held change
identity to `containment_exempt_principals`. Creating sinks and perimeters is
still allowed. The deny policy is applied by the automation SA itself, and
`iam.denypolicies.*` can't be denied. The real fix for both is still the privilege
split (step 1) plus the `deny_policy_change` alert.

The preset ships the placeholder
`principalSet://goog/group/break-glass@REPLACE-ME.invalid`. Variable validation
rejects it, along with `your-domain`, `example.com` and `.invalid`, so a copied
preset fails loudly until you set your real group. VALIDATE ON A NON-PROD ORG
FIRST. Confirm that a no-change plan/apply succeeds and that a sink update is
denied for the SA, then promote.

### 3. Dedicated logging project (audit G4/C3)

Set `logging_project_id` and `logging_project_number` (gcp-organization). The
following then move out of the admin project into that project:

- the org audit bucket
- the BigQuery audit dataset
- the audit CMEK keyring (`<prefix>-audit-cmek`)
- the control-plane alerts

**The logging project must not be owned by the Terraform admin/automation SA.**
That means no `roles/owner`, `roles/editor`, `roles/storage.admin` or
`roles/cloudkms.admin` at project level. Otherwise the audited identity can purge
its own trail. Create the project out-of-band, or from a separate identity, and
grant the SA only the narrow roles it needs.

Decide this before the first apply. KMS keys can't be deleted, so moving the audit
keys later leaves orphaned keys behind.

### 4. Audit bucket immutability (audit M-4)

On by default:

- Object Versioning on both audit buckets
- a 30-day soft-delete window (`audit_soft_delete_retention_days`, 7-90 days, or 0
  to disable)

Together these mean a deleted or overwritten audit object stays recoverable. The
WORM lock (`enable_audit_bucket_lock`) remains opt-in because it is
irreversible. GCS doesn't allow Object Versioning and a retention policy on the
same bucket, so enabling the lock turns versioning off on the audit bucket. The
locked retention policy is the stronger control, and soft delete stays on.

## Control-plane alerting (audit Security High)

`enable_control_plane_alerting` defaults to `true` (gcp-organization). It wires
`modules/gcp/monitoring/control-plane` into the organization stage, in the audit
project (the logging project if set, otherwise the admin project). An aggregated
org sink, `org-control-plane-to-monitoring`, routes org and folder Admin
Activity/Policy logs into that project, because those entries are never stored in
any project. Log-match alerts fire on:

- org/folder IAM changes
- org policy changes
- VPC-SC changes
- sink and exclusion changes
- custom role changes
- deny policy changes
- KMS key-version destroy
- audit-config changes
- any action by `break_glass_user` / `break_glass_principal_emails` (CRITICAL)

Set `alert_notification_emails` and/or `alert_notification_channels`. With neither,
the alerts still fire but nobody is notified, and a plan-time check warns.

## Break-glass (audit M3, both clouds)

The break-glass principal that the GCP containment and every AWS SCP exempt is a
standing backdoor around the guardrails. Manage it deliberately: a tight trust
policy, no standing credentials, and a mandatory alarm on its use (a CloudTrail /
EventBridge rule on AWS `AssumeRole` of the break-glass role; on GCP the
`break_glass_use` control-plane watch above). Review its scope on every access.
