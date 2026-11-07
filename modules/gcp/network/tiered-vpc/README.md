# tiered-vpc

Shared network building block: one custom-mode VPC with a three-tier zonal
subnet layout (public, private, database) and the baseline tier firewall. It is
the network core of the [`net-hub`](../../stages/net-hub/),
[`net-spoke`](../../stages/net-spoke/) and
[`dns-anchor`](../../stages/dns-anchor/) compositions.

It reproduces the network core of the deprecated
`stages/host` (removed) module resource for resource (same names,
same CIDR maths), which is what lets callers migrate with `moved` blocks and no
replacement.

## What it creates

- A custom-mode VPC with the default internet route deleted on create, and
  optionally the project enabled as a Shared VPC host.
- Per zone, one subnet in each tier, all with VPC flow logs on. The private and
  database tiers have Private Google Access; the private tier takes optional
  GKE secondary ranges.
- Tier firewall rules: API Gateway to public, public to compute, compute to
  database, Google health-check probes, IAP SSH/RDP (optional), a database-tier
  egress deny, and a logged lowest-priority deny-all ingress.
- A `prevent_destroy` guard when `deletion_protection = true`.

## CIDR layout

With empty `subnet_cidrs`, each tier is carved from `cidr_block` with
`cidrsubnet(cidr_block, 8, n)`: public at offset `i`, private at `16 + i`,
database at `32 + i`, where `i` is the zone index. A `/16` therefore yields one
`/24` per zone and tier.

`zones` is required and explicit: the composing stage owns zone discovery, so
the subnet `for_each` keys never depend on a data source read in this module.
Changing the zone set re-derives the CIDRs and replaces subnets.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Tiered VPC - shared network building block

One custom-mode VPC with a three-tier zonal subnet layout (public, private,
database) and the baseline tier firewall rules. It is the common foundation
of the `stages/net-hub`, `stages/net-spoke` and `stages/dns-anchor`
compositions, and it reproduces the network core of the deprecated
`stages/host` module resource-for-resource (same names, same CIDR maths),
so callers can migrate onto it with `moved` blocks and no replacement.

Zones are an explicit, required input: zone discovery stays with the
composing stage so the subnet `for_each` keys never depend on a data source
read inside this module.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	cidr_block =
	name =
	project_id =
	region =
	zones =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules


- database_subnets - ../subnet
- firewall_apigateway_to_public - ../network-firewall
- firewall_compute_to_database - ../network-firewall
- firewall_database_deny_egress - ../network-firewall
- firewall_deny_all - ../network-firewall
- firewall_health_checks - ../network-firewall
- firewall_iap_ssh_rdp - ../network-firewall
- firewall_public_to_compute - ../network-firewall
- private_subnets - ../subnet
- public_subnets - ../subnet
- vpc - ../vpc


## Resources

The following resources are created:


- resource.google_compute_network_firewall_policy.tier (modules/gcp/network/tiered-vpc/main.tf#L435)
- resource.google_compute_network_firewall_policy_association.tier (modules/gcp/network/tiered-vpc/main.tf#L443)
- resource.google_compute_network_firewall_policy_rule.tier (modules/gcp/network/tiered-vpc/main.tf#L452)
- resource.terraform_data.deletion_protection_guard (modules/gcp/network/tiered-vpc/main.tf#L56)
- resource.terraform_data.subnet_cidr_count_guard (modules/gcp/network/tiered-vpc/main.tf#L68)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | The VPC CIDR block (e.g. 10.0.0.0/16). Per-tier subnets are carved from it unless subnet\_cidrs is set. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC network. Also the prefix of every subnet, firewall rule and guard derived by this module. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID that owns the VPC (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region of the zonal subnet layout (e.g. us-central1). | `string` | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | Zones of the subnet layout; one subnet per tier is created per zone, keyed by zone name. Pin these for production: changing the zone set re-derives the CIDRs and replaces subnets. | `list(string)` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Create a prevent\_destroy guard that blocks any plan destroying the VPC and subnet stack, and enable VPC deletion protection. | `bool` | `false` | no |
| <a name="input_firewall"></a> [firewall](#input\_firewall) | Baseline tier firewall settings: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database. api\_gateway\_source\_ranges (the CIDRs API Gateway traffic arrives from) and database\_egress\_target\_service\_accounts apply only to the network firewall policy (firewall\_mode both / policy); the API Gateway policy rule is created only when api\_gateway\_source\_ranges is non-empty. | <pre>object({<br/>    enable_logging                          = optional(bool, true)<br/>    enable_iap_access                       = optional(bool, true)<br/>    compute_tier_ports                      = optional(list(string), ["8080", "8443", "3000"])<br/>    database_ports                          = optional(list(string), ["3306", "5432", "6379"])<br/>    api_gateway_source_ranges               = optional(list(string), [])<br/>    database_egress_target_service_accounts = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_firewall_mode"></a> [firewall\_mode](#input\_firewall\_mode) | How the baseline tier firewall is enforced. legacy: tag-based VPC firewall rules (default). both: the VPC rules plus one global network firewall policy whose rules select tiers by subnet CIDR (the migration step). policy: the network firewall policy only; the VPC rules are removed. See docs/runbooks/gcp-firewall-policy-migration.md. | `string` | `"legacy"` | no |
| <a name="input_firewall_policy_enforcement_order"></a> [firewall\_policy\_enforcement\_order](#input\_firewall\_policy\_enforcement\_order) | Network firewall policy enforcement order on the VPC: BEFORE\_CLASSIC\_FIREWALL or AFTER\_CLASSIC\_FIREWALL. null derives it from firewall\_mode: policy sets BEFORE\_CLASSIC\_FIREWALL; legacy and both leave it unset (API default AFTER\_CLASSIC\_FIREWALL). Updates the network in place. | `string` | `null` | no |
| <a name="input_flow_logs"></a> [flow\_logs](#input\_flow\_logs) | Subnet VPC flow-log settings applied to every tier (flow logs are always on). | <pre>object({<br/>    aggregation_interval = optional(string, "INTERVAL_5_SEC")<br/>    sampling             = optional(number, 0.5)<br/>  })</pre> | `{}` | no |
| <a name="input_secondary_ranges"></a> [secondary\_ranges](#input\_secondary\_ranges) | Secondary IP ranges for the private (compute) subnets, keyed by zone name (GKE Pods and Services). | <pre>map(list(object({<br/>    range_name    = string<br/>    ip_cidr_range = string<br/>  })))</pre> | `{}` | no |
| <a name="input_shared_vpc_host"></a> [shared\_vpc\_host](#input\_shared\_vpc\_host) | Enable the owning project as a Shared VPC host. | `bool` | `false` | no |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | Explicit per-tier subnet CIDRs (index-aligned with zones). An empty list derives that tier from cidr\_block. | <pre>object({<br/>    public   = optional(list(string), [])<br/>    private  = optional(list(string), [])<br/>    database = optional(list(string), [])<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_policy_id"></a> [firewall\_policy\_id](#output\_firewall\_policy\_id) | ID of the tier network firewall policy, or null in firewall\_mode = legacy. |
| <a name="output_firewall_policy_name"></a> [firewall\_policy\_name](#output\_firewall\_policy\_name) | Name of the tier network firewall policy (pass to network/internal-lb firewall\_policy), or null in firewall\_mode = legacy. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The VPC network ID. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The VPC network name. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The VPC network self link. |
| <a name="output_network_tags"></a> [network\_tags](#output\_network\_tags) | Network tags that select the security tiers in the baseline firewall rules. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Subnet module outputs by tier (public, private, database), each keyed by zone. |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | The composed VPC module outputs. |
<!-- END_TF_DOCS -->
