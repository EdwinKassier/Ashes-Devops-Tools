# net-hub

Landing-zone hub network composition: a Shared VPC host network built on
[`network/tiered-vpc`](../../network/tiered-vpc/), with Cloud NAT, Private
Service Access, Private Service Connect, hierarchical (folder or organization)
firewall policies, the hub VPC Service Controls perimeter, and opt-in hybrid
connectivity (HA VPN, Cloud Interconnect).

Called by [`stages/network-hub`](../network-hub/) as `module.hub`. It replaces
the hub use of the removed `stages/host` module.

## Interface

| Input | Purpose |
|-------|---------|
| `network` | VPC name and CIDR (required), explicit zones, per-tier CIDRs, secondary ranges, Shared VPC host flag (default on), subnet flow-log sampling |
| `firewall` | Rule logging, IAP SSH/RDP rule, tier ports |
| `hierarchical_firewall_policies` | Folder or organization firewall policies owned by the hub |
| `nat` / `private_service_access` / `private_service_connect` | Egress and private Google services, each with an `enabled` flag (default on) |
| `vpn` + `vpn_shared_secret` | HA VPN (default off); the pre-shared key is a separate sensitive input |
| `interconnects` | Dedicated or Partner Interconnect VLAN attachments |
| `vpc_service_controls` | Hub perimeter (project numbers, not IDs) |

## Migrating from stages/host

`stages/network-hub` renamed its call from `module.hub_network` to
`module.hub`. The network core moves into `module.hub.module.network`; NAT,
PSA, PSC, hierarchical firewall policies and VPC-SC move to the same names
under `module.hub`. stages/host also created a Cloud Armor policy in the hub by
default; the stage keeps it as the standalone `module.hub_cloud_armor`
primitive rather than adding an edge input to the hub. See
[`stages/network-hub/moved.tf`](../network-hub/moved.tf) for every mapping.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

net-hub - hub network composition

The landing-zone hub: a Shared VPC host network with a three-tier VPC
(network/tiered-vpc), Cloud NAT, Private Service Access, Private Service
Connect, hierarchical (folder or org) firewall policies, the hub VPC-SC
perimeter, and opt-in hybrid connectivity (HA VPN, Cloud Interconnect).

Replaces the hub use of the deprecated stages/host module (see the README
migration table for the moved blocks).

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	network =
	project_id =
	project_prefix =
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


- hierarchical_firewall_policies - ../../network/hierarchical-firewall
- integrated_nat - ../../network/nat
- interconnects - ../../network/interconnect
- network - ../../network/tiered-vpc
- private_service_access - ../../network/private-service-access
- private_service_connect - ../../network/private-service-connect
- vpc_service_controls - ../../network/vpc-sc
- vpn - ../../network/vpn


## Resources

The following resources are created:


- data source.google_compute_zones.available (modules/gcp/stages/net-hub/main.tf#L21)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_network"></a> [network](#input\_network) | The VPC and its three-tier zonal subnet layout.<br/>name and cidr\_block are required. Pin explicit\_zones for production: when<br/>empty, zones are discovered from GCP and a change in the returned zone set<br/>re-derives the subnet CIDRs (replacing subnets). subnet\_cidrs lists are<br/>index-aligned with the zones; an empty list derives that tier from<br/>cidr\_block. secondary\_ranges (GKE Pods and Services) attach to the private<br/>tier, keyed by zone. shared\_vpc\_host makes the hub project a<br/>Shared VPC host (default true). flow\_logs sets the subnet flow-log sampling. | <pre>object({<br/>    name           = string<br/>    cidr_block     = string<br/>    explicit_zones = optional(list(string), [])<br/>    subnet_cidrs = optional(object({<br/>      public   = optional(list(string), [])<br/>      private  = optional(list(string), [])<br/>      database = optional(list(string), [])<br/>    }), {})<br/>    secondary_ranges = optional(map(list(object({<br/>      range_name    = string<br/>      ip_cidr_range = string<br/>    }))), {})<br/>    shared_vpc_host = optional(bool, true)<br/>    flow_logs = optional(object({<br/>      aggregation_interval = optional(string, "INTERVAL_5_SEC")<br/>      sampling             = optional(number, 0.5)<br/>    }), {})<br/>  })</pre> | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID that owns the network (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter). | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix for derived resource names (e.g. 'ashes-dev'). Must start with a letter and contain only lowercase letters, digits, and hyphens. | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Guard the VPC and subnet stack with a prevent\_destroy terraform\_data resource and enable VPC deletion protection. To deprovision deliberately, first run terraform state rm on the network module guard. | `bool` | `false` | no |
| <a name="input_firewall"></a> [firewall](#input\_firewall) | Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database. | <pre>object({<br/>    enable_logging     = optional(bool, true)<br/>    enable_iap_access  = optional(bool, true)<br/>    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])<br/>    database_ports     = optional(list(string), ["3306", "5432", "6379"])<br/>  })</pre> | `{}` | no |
| <a name="input_hierarchical_firewall_policies"></a> [hierarchical\_firewall\_policies](#input\_hierarchical\_firewall\_policies) | Hierarchical firewall policies owned by the hub, keyed by policy name. parent is the owning folders/<id> or organizations/<id>; associations lists the folders or organization the policy is attached to. | <pre>map(object({<br/>    parent      = string<br/>    description = optional(string, "Managed by Terraform")<br/>    rules = optional(list(object({<br/>      priority       = number<br/>      action         = string<br/>      direction      = string<br/>      description    = optional(string)<br/>      disabled       = optional(bool, false)<br/>      enable_logging = optional(bool, false)<br/>      layer4_configs = list(object({<br/>        ip_protocol = string<br/>        ports       = optional(list(string))<br/>      }))<br/>      src_ip_ranges           = optional(list(string))<br/>      src_region_codes        = optional(list(string))<br/>      dest_ip_ranges          = optional(list(string))<br/>      dest_region_codes       = optional(list(string))<br/>      target_networks         = optional(list(string))<br/>      target_service_accounts = optional(list(string))<br/>    })), [])<br/>    associations   = optional(list(string), [])<br/>    enable_logging = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_interconnects"></a> [interconnects](#input\_interconnects) | Cloud Interconnect VLAN attachments on the hub network, keyed by attachment name (Dedicated or Partner). | <pre>map(object({<br/>    region            = string<br/>    interconnect_type = optional(string, "PARTNER")<br/>    router_name       = string<br/>    router_asn        = optional(number, 64512)<br/>    create_router     = optional(bool, true)<br/><br/>    # Dedicated interconnect settings<br/>    interconnect_self_link = optional(string)<br/>    vlan_tag               = optional(number)<br/>    bandwidth              = optional(string, "BPS_10G")<br/><br/>    # Partner interconnect settings<br/>    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")<br/><br/>    # Common settings<br/>    mtu           = optional(number, 1440)<br/>    admin_enabled = optional(bool, true)<br/>    encryption    = optional(string, "NONE")<br/><br/>    # BGP settings<br/>    create_bgp_peer    = optional(bool, true)<br/>    interface_ip_range = optional(string)<br/>    peer_ip_address    = optional(string)<br/>    peer_asn           = optional(number, 65000)<br/>    enable_bfd         = optional(bool, false)<br/><br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = optional(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource. | `map(string)` | `{}` | no |
| <a name="input_nat"></a> [nat](#input\_nat) | Cloud NAT (and its Cloud Router) for the private and database tiers. Set enabled = false for a network with no egress need. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    ip_allocate_option = optional(string, "AUTO_ONLY")<br/>    log_filter         = optional(string, "ERRORS_ONLY")<br/>  })</pre> | `{}` | no |
| <a name="input_private_service_access"></a> [private\_service\_access](#input\_private\_service\_access) | Private Service Access range (private-IP Cloud SQL, Memorystore and other Google-managed services peer through it). | <pre>object({<br/>    enabled       = optional(bool, true)<br/>    name          = optional(string, "google-managed-services")<br/>    prefix_length = optional(number, 16)<br/>  })</pre> | `{}` | no |
| <a name="input_private_service_connect"></a> [private\_service\_connect](#input\_private\_service\_connect) | Private Service Connect endpoint for Google APIs; target is 'all-apis' or 'vpc-sc'. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    target  = optional(string, "all-apis")<br/>  })</pre> | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | The primary GCP region of the network (e.g., 'us-central1', 'europe-west1'). | `string` | `"us-central1"` | no |
| <a name="input_vpc_service_controls"></a> [vpc\_service\_controls](#input\_vpc\_service\_controls) | VPC Service Controls perimeters, keyed by perimeter name. protected\_projects takes project NUMBERS, not IDs. | <pre>map(object({<br/>    # organization_id must be the FULL resource form 'organizations/<numeric-id>'<br/>    # (Access Context Manager's access-policy parent requires this form). NOTE:<br/>    # this diverges from every other org-id input in the repo (governance/tags,<br/>    # governance/cloud-audit-logs, stages/organization var.org_id) which take the<br/>    # BARE numeric id. Callers prefix the bare org_id output here accordingly.<br/>    # See docs: the vpc-sc module is the sole outlier; a future normalization<br/>    # would have vpc-sc accept the bare id and prefix internally.<br/>    organization_id      = string<br/>    access_policy_name   = optional(string)<br/>    create_access_policy = optional(bool, false)<br/>    perimeter_title      = string<br/>    description          = optional(string, "Managed by Terraform")<br/>    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")<br/>    protected_projects   = optional(list(string), [])<br/>    restricted_services  = optional(list(string), [])<br/>    access_levels = optional(list(object({<br/>      name               = string<br/>      title              = string<br/>      description        = optional(string)<br/>      combining_function = optional(string, "AND")<br/>      conditions = list(object({<br/>        ip_subnetworks = optional(list(string))<br/>        members        = optional(list(string))<br/>        negate         = optional(bool, false)<br/>        regions        = optional(list(string))<br/>      }))<br/>    })), [])<br/>    ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    enable_dry_run             = optional(bool, true)<br/>    enable_deletion_protection = optional(bool, true)<br/>    # Staged dry-run delta on an ENFORCED perimeter (see network/vpc-sc). null = same as enforced.<br/>    dry_run_restricted_services = optional(list(string))<br/>    dry_run_ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })))<br/>    dry_run_egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })))<br/>  }))</pre> | `{}` | no |
| <a name="input_vpn"></a> [vpn](#input\_vpn) | HA VPN to an on-premises or other-cloud peer gateway, off by default.<br/>tunnel\_count is 2 for HA (production) or 1 for testing. peer\_gateway\_ips<br/>lists the peer interface IPv4 addresses (one per tunnel). local\_ips and<br/>peer\_ips are the BGP link-local addresses. The pre-shared key is the separate<br/>sensitive vpn\_shared\_secret input. | <pre>object({<br/>    enabled          = optional(bool, false)<br/>    tunnel_count     = optional(number, 2)<br/>    router_asn       = optional(number, 64512)<br/>    peer_asn         = optional(number, 64513)<br/>    peer_gateway_ips = optional(list(string), [])<br/>    local_ips        = optional(list(string), ["169.254.0.1", "169.254.0.3"])<br/>    peer_ips         = optional(list(string), ["169.254.0.2", "169.254.0.4"])<br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = string<br/>    })), [])<br/>  })</pre> | `{}` | no |
| <a name="input_vpn_shared_secret"></a> [vpn\_shared\_secret](#input\_vpn\_shared\_secret) | HA VPN pre-shared key. Required when vpn.enabled is true; inject it from Secret Manager or a sensitive workspace variable, not a plaintext tfvars file. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_hierarchical_firewall_policy_ids"></a> [hierarchical\_firewall\_policy\_ids](#output\_hierarchical\_firewall\_policy\_ids) | The IDs of the hierarchical firewall policies, keyed by policy name. |
| <a name="output_interconnect_pairing_keys"></a> [interconnect\_pairing\_keys](#output\_interconnect\_pairing\_keys) | Pairing keys for partner interconnects (share with the provider). |
| <a name="output_interconnect_states"></a> [interconnect\_states](#output\_interconnect\_states) | The state of each interconnect attachment. |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | The Cloud NAT IP addresses, or null when NAT is disabled. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The VPC network ID. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The VPC network name. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The VPC network self link. |
| <a name="output_network_tags"></a> [network\_tags](#output\_network\_tags) | Network tags that select the security tiers in the baseline firewall rules. |
| <a name="output_private_service_access_range_name"></a> [private\_service\_access\_range\_name](#output\_private\_service\_access\_range\_name) | Name of the Private Service Access range reserved on this VPC, or null when PSA is disabled. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Subnet module outputs by tier (public, private, database), each keyed by zone. |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | The composed VPC module outputs. |
| <a name="output_vpc_service_control_perimeter_names"></a> [vpc\_service\_control\_perimeter\_names](#output\_vpc\_service\_control\_perimeter\_names) | The names of all VPC Service Controls perimeters. |
| <a name="output_vpc_service_controls"></a> [vpc\_service\_controls](#output\_vpc\_service\_controls) | All VPC Service Controls perimeter outputs, keyed by perimeter name. |
| <a name="output_vpn_gateway_ips"></a> [vpn\_gateway\_ips](#output\_vpn\_gateway\_ips) | The HA VPN gateway external IP addresses, or null when VPN is disabled. |
| <a name="output_vpn_tunnel_statuses"></a> [vpn\_tunnel\_statuses](#output\_vpn\_tunnel\_statuses) | The status of each VPN tunnel, or null when VPN is disabled. |
<!-- END_TF_DOCS -->
