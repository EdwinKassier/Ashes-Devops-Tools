# Presets

Ready-to-use `-var-file` overlays. Each preset sets only a handful of toggles and
is applied IN ADDITION to your own tfvars, so you keep full control. In Terraform
Cloud, set the same values as workspace variables instead of a local `-var-file`.

There are two families: cost presets (cut the non-production idle baseline) and
hardening presets (flip the safe production controls on together).

## Production hardening presets (audit H1)

The default roots ship the dangerous controls OFF so a first apply never breaks
or locks state. That means a default apply is NOT fully hardened. These overlays
turn the safe controls on together, so hardening is one `-var-file`, not a hunt
through the docs. The one irreversible control (audit-log WORM lock) stays a
commented, deliberate opt-in. See [`docs/runbooks/production-hardening.md`](../../docs/runbooks/production-hardening.md).

| Preset | Root | Turns on |
|---|---|---|
| `prod-gcp-bootstrap.tfvars` | `envs/gcp/bootstrap` | `enable_privilege_split` (PREVIEW) |
| `prod-gcp-organization.tfvars` | `envs/gcp/organization` | `enable_cmek_org_policy`; WORM lock left commented |
| `prod-gcp-network-hub.tfvars` | `envs/gcp/network-hub` | VPC-SC enforced (`vpc_sc_enable_dry_run = false`) |
| `prod-aws-security.tfvars` | `envs/aws/security` | CloudWatch Logs + CIS alarms, full Config/GuardDuty |

```bash
terraform -chdir=envs/gcp/network-hub plan \
  -var-file=your.tfvars \
  -var-file=../../../examples/presets/prod-gcp-network-hub.tfvars
```

Read each preset's comments first: some controls have prerequisites (CMEK keys
before CMEK enforcement, clean dry-run logs before VPC-SC enforcement, a
logs-granted KMS key for CloudWatch Logs).

## Cost presets (audit F2)

Cut the always-on footprint for dev, sandbox, and throwaway environments (the
default AWS footprint is about USD 1,500/month before any workload, see
[`docs/audit/2026-11-04-finops-deep-dive.md`](../../docs/audit/2026-11-04-finops-deep-dive.md)).

| Preset | Root | What it changes | Approx saving |
|---|---|---|---|
| `nonprod-aws-network.tfvars` | `envs/aws/network` | `az_count = 1`, `enable_network_firewall = false` | ~USD 800/mo |
| `nonprod-aws-security.tfvars` | `envs/aws/security` | `enable_security_lake = false`, `enabled_security_services = []`, `config_record_all_supported = false`, `guardduty_enable_ebs_malware_protection = false` | ~USD 70-300/mo |

```bash
terraform -chdir=envs/aws/network plan \
  -var-file=../../../examples/presets/nonprod-aws-network.tfvars
```

## Warning

Do not use the cost presets for production. They remove inline traffic inspection
(Network Firewall), cross-AZ redundancy (`az_count = 1`), two security services
(Macie, Inspector), and reduce Config/GuardDuty coverage. Keep the defaults, and
add the hardening presets, for any production environment.
