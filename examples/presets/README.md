# Cost presets

Ready-to-use `-var-file` presets that cut the landing-zone idle baseline for
non-production environments. The default roots ship a production-grade, always-on
security and inspection footprint (about USD 1,500/month on AWS before any
workload, see [`docs/audit/2026-11-04-finops-deep-dive.md`](../../docs/audit/2026-11-04-finops-deep-dive.md)).
These presets address finding F2 (no cheap on-ramp) by giving a documented,
lower-cost footprint for dev, sandbox, and throwaway environments.

| Preset | Root | What it changes | Approx saving |
|---|---|---|---|
| `nonprod-aws-network.tfvars` | `envs/aws/network` | `az_count = 1`, `enable_network_firewall = false` | ~USD 800/mo |
| `nonprod-aws-security.tfvars` | `envs/aws/security` | `enable_security_lake = false`, `enabled_security_services = []` | ~USD 70-300/mo |

## Usage

```bash
terraform -chdir=envs/aws/network plan \
  -var-file=../../../examples/presets/nonprod-aws-network.tfvars

terraform -chdir=envs/aws/security plan \
  -var-file=../../../examples/presets/nonprod-aws-security.tfvars
```

In Terraform Cloud, set these as workspace variables on the non-prod workspaces
instead of a local `-var-file`.

## Warning

Do not use these presets for production. They remove inline traffic inspection
(Network Firewall), cross-AZ redundancy (`az_count = 1`), and two security
services (Macie, Inspector). Keep the defaults for any production environment.
Deeper cuts (AWS Config `record_all_supported`, GuardDuty EBS malware) require
module-level overrides; see the cost table in
[`docs/architecture/aws-landing-zone.md`](../../docs/architecture/aws-landing-zone.md).
