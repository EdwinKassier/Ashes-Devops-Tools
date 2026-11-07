# Presets

Ready-to-use `-var-file` overlays. Each preset sets only a handful of toggles and
is applied IN ADDITION to your own tfvars, so you keep full control. In Terraform
Cloud, set the same values as workspace variables instead of a local `-var-file`.

`envs/gcp/organization` and `envs/aws/security` take their tuning inputs as one
object (`gcp_overrides` / `aws_overrides`). A `-var-file` sets the whole object,
so their presets replace your own override object rather than merging with it:
copy the preset's keys into your own `gcp_overrides` / `aws_overrides` instead.

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
| `prod-gcp-bootstrap.tfvars` | `envs/gcp/bootstrap` | Keeps the GitHub WIF pool off (`enable_github_wif = false`); per-stage identities are default |
| `prod-gcp-organization.tfvars` | `envs/gcp/organization` | `gcp_overrides`: `enable_cmek_org_policy`; WORM lock left commented |
| `prod-gcp-network-hub.tfvars` | `envs/gcp/network-hub` | VPC-SC enforced (`vpc_sc_enable_dry_run = false`) |
| `prod-gcp-workload.tfvars` | `envs/gcp/workload` | Environment VPC-SC enforced, Cloud Armor + OWASP rules |
| `prod-aws-security.tfvars` | `envs/aws/security` | `aws_overrides`: CloudWatch Logs + CIS alarms, full Config/GuardDuty |

```bash
terraform -chdir=envs/gcp/network-hub plan \
  -var-file=your.tfvars \
  -var-file=../../../examples/presets/prod-gcp-network-hub.tfvars
```

`scripts/check-consistency.sh` (run in CI) fails if a preset sets a variable its root
does not declare, or if any doc references a preset that does not exist.

### Presets from `config/landing-zone.yaml` (no `-var-file`)

VCS-driven Terraform Cloud runs never see a local `-var-file`. A preset that has a
YAML twin (`<name>.yaml`) can instead be named in the committed config, and its
root applies it on every run:

```yaml
presets: [prod-gcp-workload]        # every workspace of the preset's root
gcp:
  workload:
    presets_by_environment:         # gcp-workload-<env> only
      prod: [prod-gcp-workload]
```

Precedence: an explicit variable (tfvars or TFC variable) > preset > config file >
built-in default. A listed preset applies only in the root its `root:` key names;
other roots ignore it. A preset name with no `.yaml` twin fails the plan.

| YAML twin | Honoured by |
|---|---|
| `prod-gcp-workload.yaml` | `envs/gcp/workload` (top-level `presets` or `gcp.workload.presets_by_environment`) |

The other presets have no YAML twin yet, so `envs/gcp/network-hub`, `envs/aws/security`
and the rest still take them with `-var-file`. Each `.yaml` mirrors its `.tfvars`
exactly: `envs/gcp/workload/tests/presets.tftest.hcl` fails when the two disagree.
Prefer `presets_by_environment` for hardening presets, so dev is not enforced
along with prod.

Read each preset's comments first: some controls have prerequisites (CMEK keys
before CMEK enforcement, clean dry-run logs before VPC-SC enforcement, a
logs-granted KMS key for CloudWatch Logs).

## Cost presets (audit F2)

Cut the always-on footprint for dev, sandbox, and throwaway environments (the
default AWS footprint is about USD 1,500/month before any workload, see
[`docs/audit/archive/2026-11-04-finops-deep-dive.md`](../../docs/audit/archive/2026-11-04-finops-deep-dive.md)).

| Preset | Root | What it changes | Approx saving |
|---|---|---|---|
| `nonprod-aws-network.tfvars` | `envs/aws/network` | `az_count = 2` (the minimum), `enable_network_firewall = false` | ~USD 800/mo |
| `nonprod-aws-security.tfvars` | `envs/aws/security` | `aws_overrides`: `enable_security_lake = false`, `enabled_security_services = []`, `config_record_all_supported = false`, `guardduty_enable_ebs_malware_protection = false` | ~USD 70-300/mo |

```bash
terraform -chdir=envs/aws/network plan \
  -var-file=../../../examples/presets/nonprod-aws-network.tfvars
```

## Warning

Do not use the cost presets for production. They remove inline traffic inspection
(Network Firewall), a third AZ (`az_count = 2`, the minimum the Resolver endpoints allow), two security services
(Macie, Inspector), and reduce Config/GuardDuty coverage. Keep the defaults, and
add the hardening presets, for any production environment.
