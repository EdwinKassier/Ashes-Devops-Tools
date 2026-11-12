# Presets

Ready-to-use overlays. Each preset sets only a handful of toggles. A local plan
takes them with `-var-file`. **VCS-driven HCP Terraform runs never see a
`-var-file`**, so for those, copy the preset's variables into
`config/tfc-workspaces.yaml` under the workspace name; tfc-admin writes them as
workspace variables on its next apply (see
[below](#the-same-presets-in-configtfc-workspacesyaml)). `prod-gcp-workload` also
has a YAML twin that the config file can name directly (see
[Presets from `config/landing-zone.yaml`](#presets-from-configlanding-zoneyaml-no--var-file)).
How a preset combines with your own tfvars depends on its root:

- **Most roots** take plain variables, so a preset is applied IN ADDITION to your
  own tfvars (a later `-var-file` wins per variable).
- **`envs/gcp/organization` and `envs/aws/security`** take their tuning inputs as
  one object (`gcp_overrides` / `aws_overrides`). A `-var-file` sets the whole
  object, so a preset's override object REPLACES yours: stacking it after your
  own tfvars drops every key of yours it does not repeat. Do not stack these
  presets. Copy their keys into your own `<section>_overrides` instead.

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
| `regulated-gcp-workload.tfvars` | `envs/gcp/workload` | Applied automatically to a `compliance_class: regulated` environment: VPC-SC enforced, Cloud Armor + OWASP rules, every flow logged, 365-day flow-log retention ([Regulated environments](../../docs/architecture/regulated-environments.md)) |
| `prod-aws-security.tfvars` | `envs/aws/security` | `aws_overrides`: CloudWatch Logs + CIS alarms, full Config/GuardDuty |

```bash
terraform -chdir=envs/gcp/network-hub plan \
  -var-file=your.tfvars \
  -var-file=../../../examples/presets/prod-gcp-network-hub.tfvars
```

`scripts/check-consistency.sh` (run in CI) fails if a preset sets a variable its root
does not declare, or if any doc references a preset that does not exist.

### The same presets in `config/tfc-workspaces.yaml`

```yaml
workspaces:
  gcp-network-hub:            # prod-gcp-network-hub.tfvars
    vpc_sc_enable_dry_run: false
  aws-network:                # nonprod-aws-network.tfvars (a non-production estate)
    az_count: 2
    enable_network_firewall: false
  gcp-bootstrap:              # prod-gcp-bootstrap.tfvars: the local phase-0 apply reads tfvars,
    enable_github_wif: false  # so this entry matters only once gcp-bootstrap runs remotely
    enable_pam: true
    enable_phase0_admin_impersonation: false
    enable_scoped_access_policies: true
    enable_legacy_org_access_policy_grants: false
    enable_org_level_folder_iam_delegation: false
    guardrail_owner_mode: separate
    guardrail_owner_members: ["group:REPLACE-guardrail-owners@your-domain.invalid"]
```

tfc-admin writes a scalar as a plain string variable and a list or map as an HCL
variable, so `guardrail_owner_members` reaches the root as a list. Leave out the
preset's `tfc_workspace_ids`: tfc-admin sets it on `gcp-bootstrap` itself (an
entry in this file replaces the derived value).

`gcp_overrides` (gcp-organization) and `aws_overrides` (aws-security) are object variables:
put **all** of your keys in one entry, because the workspace variable replaces the whole
object. tfc-admin rejects entries for the security-only `gcp-guardrails` workspace.
`scripts/check-consistency.sh` fails if an entry in this block, in
`config/tfc-workspaces.example.yaml` or in a committed `tfc-workspaces.yaml` names a
variable its workspace's root does not declare.

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
| `regulated-gcp-workload.yaml` | `envs/gcp/workload`, applied last to every environment with `gcp.environments.<env>.compliance_class: regulated` (you do not list it) |

The other presets have no YAML twin yet. `envs/gcp/network-hub` and the other
plain-variable roots still take them with `-var-file`. For `envs/gcp/organization`
and `envs/aws/security`, copy the preset's keys into your own `gcp_overrides` /
`aws_overrides` (see the top of this page): their override object replaces yours. Each `.yaml` mirrors its `.tfvars`
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
