# dns-anchor

Private DNS anchor network composition: a workload-free VPC whose only job is
to anchor the organization's private Cloud DNS zones. Spokes resolve the zones
through DNS peering zones targeting `network_self_link`.

It composes the [`network/tiered-vpc`](../../network/tiered-vpc/) core, the
private zones (always bound to the anchor VPC, query logging on, DNSSEC flag on
by default) and optional VPC peerings. There is deliberately no Cloud NAT,
Cloud Armor, Private Service Connect or Private Service Access: nothing in the
anchor VPC egresses or calls Google APIs, so those billable resources would be
pure cost.

Called by [`stages/network-hub`](../network-hub/) as `module.dns_anchor`. It
replaces the DNS-hub use of the removed `stages/host` module plus
the stage's separate root-zone module.

## Interface

| Input | Purpose |
|-------|---------|
| `network` | VPC name and CIDR (required), explicit zones, per-tier CIDRs, subnet flow-log sampling |
| `firewall` | Baseline rule logging, IAP SSH/RDP rule, tier ports |
| `dns_zones` | Private zones keyed by zone name: FQDN with trailing dot, description, DNSSEC flag, records, extra visibility networks |
| `peerings` | Optional VPC peerings |

## Migrating from stages/host

`stages/network-hub` renamed `module.dns_hub_network` to `module.dns_anchor`
(network core under `module.dns_anchor.module.network`) and folded
`module.dns_hub_zone` into `module.dns_anchor.module.dns_zones["internal-root"]`.
See [`stages/network-hub/moved.tf`](../network-hub/moved.tf) for every mapping.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

dns-anchor - private DNS anchor network composition

A workload-free VPC whose only job is to anchor the organization's private
Cloud DNS zones; spokes reach the zones through DNS peering. It composes the
network/tiered-vpc core (VPC, zonal subnets, baseline deny-by-default
firewall), the private zones bound to that VPC, and optional VPC peerings.

There is deliberately no Cloud NAT, Cloud Armor, Private Service Connect or
Private Service Access: nothing in the anchor VPC egresses or calls Google
APIs, so those billable resources would be pure cost (FinOps F4).

Replaces the DNS-hub use of the removed stages/host module.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	network =
	project_id =
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

## Modules


- dns_zones - ../../network/dns
- network - ../../network/tiered-vpc
- vpc_peering - ../../network/vpc-peering


## Resources

The following resources are created:


- data source.google_compute_zones.available (modules/gcp/stages/dns-anchor/main.tf#L24)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_network"></a> [network](#input\_network) | The VPC and its three-tier zonal subnet layout.<br/>name and cidr\_block are required. Pin explicit\_zones for production: when<br/>empty, zones are discovered from GCP and a change in the returned zone set<br/>re-derives the subnet CIDRs (replacing subnets). subnet\_cidrs lists are<br/>index-aligned with the zones; an empty list derives that tier from<br/>cidr\_block. The anchor VPC hosts no workloads; the subnets keep the<br/>layout uniform with the hub and spokes. flow\_logs sets the subnet flow-log<br/>sampling. | <pre>object({<br/>    name           = string<br/>    cidr_block     = string<br/>    explicit_zones = optional(list(string), [])<br/>    subnet_cidrs = optional(object({<br/>      public   = optional(list(string), [])<br/>      private  = optional(list(string), [])<br/>      database = optional(list(string), [])<br/>    }), {})<br/>    flow_logs = optional(object({<br/>      aggregation_interval = optional(string, "INTERVAL_5_SEC")<br/>      sampling             = optional(number, 0.5)<br/>    }), {})<br/>  })</pre> | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID that owns the network (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter). | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Guard the VPC and subnet stack with a prevent\_destroy terraform\_data resource and enable VPC deletion protection. To deprovision deliberately, first run terraform state rm on the network module guard. | `bool` | `false` | no |
| <a name="input_dns_zones"></a> [dns\_zones](#input\_dns\_zones) | Private Cloud DNS zones anchored on this VPC, keyed by zone name. dns\_name<br/>must end with a dot. Every zone is bound to the anchor VPC; add other<br/>networks via additional\_visibility\_networks. DNSSEC defaults on and query<br/>logging is always on. | <pre>map(object({<br/>    dns_name                       = string<br/>    description                    = optional(string)<br/>    dnssec_enabled                 = optional(bool, true)<br/>    additional_visibility_networks = optional(list(string), [])<br/>    records = optional(list(object({<br/>      name    = string<br/>      type    = string<br/>      ttl     = optional(number, 300)<br/>      rrdatas = list(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_firewall"></a> [firewall](#input\_firewall) | Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database. | <pre>object({<br/>    enable_logging     = optional(bool, true)<br/>    enable_iap_access  = optional(bool, true)<br/>    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])<br/>    database_ports     = optional(list(string), ["3306", "5432", "6379"])<br/>  })</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource. | `map(string)` | `{}` | no |
| <a name="input_peerings"></a> [peerings](#input\_peerings) | VPC peerings from this network, keyed by peering name (the anchor is normally reached by DNS peering, not VPC peering). | <pre>map(object({<br/>    peer_network           = string<br/>    create_reverse_peering = optional(bool, true)<br/>    export_custom_routes   = optional(bool, false)<br/>    import_custom_routes   = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | The primary GCP region of the network (e.g., 'us-central1', 'europe-west1'). | `string` | `"us-central1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_names"></a> [dns\_names](#output\_dns\_names) | DNS suffix served by each DNS zone. |
| <a name="output_dns_zone_names"></a> [dns\_zone\_names](#output\_dns\_zone\_names) | Managed zone name of each DNS zone. |
| <a name="output_dns_zones"></a> [dns\_zones](#output\_dns\_zones) | All DNS zone module outputs, keyed by zone name. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The anchor VPC network ID. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The anchor VPC network name. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The anchor VPC network self link (the target for DNS peering zones). |
| <a name="output_peering_states"></a> [peering\_states](#output\_peering\_states) | The state of each VPC peering connection. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Subnet module outputs by tier (public, private, database), each keyed by zone. |
<!-- END_TF_DOCS -->
