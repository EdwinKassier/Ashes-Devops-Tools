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

Deeper cuts that are currently module-level overrides (surface them at the root
if you need them routinely):

- `record_all_supported = false` in `modules/aws/security/config-org` (Config is
  the most expensive in record-all mode).
- `enable_ebs_malware_protection = false` in `modules/aws/security/guardduty-org`.

Keep the full posture for production. See the cost model in
[`docs/audit/2026-11-04-finops-deep-dive.md`](../audit/2026-11-04-finops-deep-dive.md).
