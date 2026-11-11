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
perimeter, opt-in hybrid connectivity (HA VPN, Cloud Interconnect) and an
opt-in Network Connectivity Center hub (the alternative to spoke peering).

Opt-in additional\_regions add regional subnets (and a Cloud Router and NAT
per region) to the same VPC; empty keeps the single-region layout.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.10.0 |

## Modules


- additional_region_nat - ../../network/nat
- hierarchical_firewall_policies - ../../network/hierarchical-firewall
- integrated_nat - ../../network/nat
- interconnects - ../../network/interconnect
- ncc_hub - ../../network/ncc-hub
- ncc_hub_spoke - ../../network/ncc-spoke
- ncc_vpn_spoke - ../../network/ncc-spoke
- network - ../../network/tiered-vpc
- network_alerts - ../../monitoring/alert-policy
- private_service_access - ../../network/private-service-access
- private_service_connect - ../../network/private-service-connect
- secure_web_proxy - ../../network/secure-web-proxy
- vpc_service_controls - ../../network/vpc-sc
- vpn - ../../network/vpn


## Resources

The following resources are created:


- data source.google_compute_zones.available (modules/gcp/stages/net-hub/main.tf#L25)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_network"></a> [network](#input\_network) | The VPC and its three-tier zonal subnet layout.<br/>name and cidr\_block are required. Pin explicit\_zones for production: when<br/>empty, zones are discovered from GCP and a change in the returned zone set<br/>re-derives the subnet CIDRs (replacing subnets). subnet\_cidrs lists are<br/>index-aligned with the zones; an empty list derives that tier from<br/>cidr\_block. secondary\_ranges (GKE Pods and Services) attach to the private<br/>tier, keyed by zone. shared\_vpc\_host makes the hub project a<br/>Shared VPC host (default true). flow\_logs sets the subnet flow-log sampling. | <pre>object({<br/>    name           = string<br/>    cidr_block     = string<br/>    explicit_zones = optional(list(string), [])<br/>    subnet_cidrs = optional(object({<br/>      public   = optional(list(string), [])<br/>      private  = optional(list(string), [])<br/>      database = optional(list(string), [])<br/>    }), {})<br/>    secondary_ranges = optional(map(list(object({<br/>      range_name    = string<br/>      ip_cidr_range = string<br/>    }))), {})<br/>    shared_vpc_host = optional(bool, true)<br/>    flow_logs = optional(object({<br/>      aggregation_interval = optional(string, "INTERVAL_5_SEC")<br/>      sampling             = optional(number, 0.5)<br/>    }), {})<br/>  })</pre> | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID that owns the network (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter). | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix for derived resource names (e.g. 'ashes-dev'). Must start with a letter and contain only lowercase letters, digits, and hyphens. | `string` | n/a | yes |
| <a name="input_additional_regions"></a> [additional\_regions](#input\_additional\_regions) | Opt-in extra regions of this VPC, keyed by region name (passed to network/tiered-vpc): subnet\_cidrs (public, private, database; one regional subnet per tier, no overlap with the primary subnets or another region), optional secondary\_ranges for the region's private subnet, and nat (default true): a Cloud Router <network.name>-router-<region> and Cloud NAT <network.name>-nat-<region> for the region's private and database subnets, with the primary nat settings (created only when nat.enabled). PSA, PSC, VPN, DNS and VPC-SC stay single-region or global. Empty (default) = single-region, nothing changes. | <pre>map(object({<br/>    subnet_cidrs = object({<br/>      public   = string<br/>      private  = string<br/>      database = string<br/>    })<br/>    secondary_ranges = optional(list(object({<br/>      range_name    = string<br/>      ip_cidr_range = string<br/>    })), [])<br/>    nat = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_alerting"></a> [alerting](#input\_alerting) | Data-plane alert policies in the hub project, on by default for the features that exist: VPN tunnel down (vpn.enabled), BGP session down (vpn.enabled or any interconnect) and Cloud NAT allocation failures and OUT\_OF\_RESOURCES drops (nat.enabled). notification\_channel\_ids are existing channel IDs (projects/<project>/notificationChannels/<id>); empty = the policies still open incidents in the console but notify no one. enabled = false creates none. | <pre>object({<br/>    enabled                       = optional(bool, true)<br/>    notification_channel_ids      = optional(list(string), [])<br/>    nat_dropped_packets_threshold = optional(number, 0)<br/>  })</pre> | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Guard the VPC and subnet stack with a prevent\_destroy terraform\_data resource and enable VPC deletion protection. To deprovision deliberately, first run terraform state rm on the network module guard. | `bool` | `false` | no |
| <a name="input_firewall"></a> [firewall](#input\_firewall) | Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database. api\_gateway\_source\_ranges and database\_egress\_target\_service\_accounts apply only to the network firewall policy (firewall\_mode both / policy). | <pre>object({<br/>    enable_logging     = optional(bool, true)<br/>    enable_iap_access  = optional(bool, true)<br/>    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])<br/>    database_ports     = optional(list(string), ["3306", "5432", "6379"])<br/>    # Network firewall policy only (firewall_mode both / policy).<br/>    api_gateway_source_ranges               = optional(list(string), [])<br/>    database_egress_target_service_accounts = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_firewall_mode"></a> [firewall\_mode](#input\_firewall\_mode) | How the baseline tier firewall is enforced (network/tiered-vpc firewall\_mode). legacy: tag-based VPC firewall rules (default). both: the VPC rules plus a global network firewall policy keyed on tier subnet CIDRs. policy: the network firewall policy only. See docs/runbooks/gcp-firewall-policy-migration.md. | `string` | `"legacy"` | no |
| <a name="input_firewall_policy_enforcement_order"></a> [firewall\_policy\_enforcement\_order](#input\_firewall\_policy\_enforcement\_order) | Network firewall policy enforcement order on the VPC: BEFORE\_CLASSIC\_FIREWALL or AFTER\_CLASSIC\_FIREWALL. null derives it from firewall\_mode (policy sets BEFORE\_CLASSIC\_FIREWALL; legacy and both leave the API default AFTER\_CLASSIC\_FIREWALL). Updates the network in place. WARNING: switching from both to policy with this unset flips the order in the same apply that deletes the legacy rules; set it explicitly. | `string` | `null` | no |
| <a name="input_hierarchical_firewall_policies"></a> [hierarchical\_firewall\_policies](#input\_hierarchical\_firewall\_policies) | Hierarchical firewall policies owned by the hub, keyed by policy name. parent is the owning folders/<id> or organizations/<id>; associations lists the folders or organization the policy is attached to. | <pre>map(object({<br/>    parent      = string<br/>    description = optional(string, "Managed by Terraform")<br/>    rules = optional(list(object({<br/>      priority       = number<br/>      action         = string<br/>      direction      = string<br/>      description    = optional(string)<br/>      disabled       = optional(bool, false)<br/>      enable_logging = optional(bool, false)<br/>      layer4_configs = list(object({<br/>        ip_protocol = string<br/>        ports       = optional(list(string))<br/>      }))<br/>      src_ip_ranges           = optional(list(string))<br/>      src_region_codes        = optional(list(string))<br/>      dest_ip_ranges          = optional(list(string))<br/>      dest_region_codes       = optional(list(string))<br/>      target_networks         = optional(list(string))<br/>      target_service_accounts = optional(list(string))<br/>    })), [])<br/>    associations   = optional(list(string), [])<br/>    enable_logging = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_interconnects"></a> [interconnects](#input\_interconnects) | Cloud Interconnect VLAN attachments on the hub network, keyed by attachment name (Dedicated or Partner). | <pre>map(object({<br/>    region            = string<br/>    interconnect_type = optional(string, "PARTNER")<br/>    router_name       = string<br/>    router_asn        = optional(number, 64512)<br/>    create_router     = optional(bool, true)<br/><br/>    # Dedicated interconnect settings<br/>    interconnect_self_link = optional(string)<br/>    vlan_tag               = optional(number)<br/>    bandwidth              = optional(string, "BPS_10G")<br/><br/>    # Partner interconnect settings<br/>    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")<br/><br/>    # Common settings<br/>    mtu           = optional(number, 1440)<br/>    admin_enabled = optional(bool, true)<br/>    encryption    = optional(string, "NONE")<br/><br/>    # BGP settings<br/>    create_bgp_peer    = optional(bool, true)<br/>    interface_ip_range = optional(string)<br/>    peer_ip_address    = optional(string)<br/>    peer_asn           = optional(number, 65000)<br/>    enable_bfd         = optional(bool, false)<br/><br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = optional(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource. | `map(string)` | `{}` | no |
| <a name="input_nat"></a> [nat](#input\_nat) | Cloud NAT (and its Cloud Router) for the private tier. Set enabled = false for a network with no egress need. include\_database\_subnets (default false) also NATs the database tier: leave it off so a database VM has no internet path even when it lacks the database network tag. | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    ip_allocate_option       = optional(string, "AUTO_ONLY")<br/>    log_filter               = optional(string, "ERRORS_ONLY")<br/>    include_database_subnets = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_ncc"></a> [ncc](#input\_ncc) | Network Connectivity Center hub, off by default (spokes then use VPC peering). preset\_topology: STAR (edge spokes reach the center only; the peering-equivalent) or MESH. Immutable once created. name defaults to <project\_prefix>-ncc-hub. export\_private\_service\_access adds a producer VPC spoke for the hub PSA peering (when PSA is enabled). auto\_accept\_projects (project IDs or numbers) adopts the spoke group to auto-accept spokes from those projects; empty = spokes from other projects wait for a manual accept. vpn\_site\_to\_site\_data\_transfer lets on-premises sites exchange traffic through the VPN hybrid spoke (only when vpn.enabled; the region must support it). | <pre>object({<br/>    enabled                        = optional(bool, false)<br/>    name                           = optional(string)<br/>    preset_topology                = optional(string, "STAR")<br/>    export_psc                     = optional(bool, false)<br/>    export_private_service_access  = optional(bool, true)<br/>    auto_accept_projects           = optional(list(string), [])<br/>    vpn_site_to_site_data_transfer = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_private_service_access"></a> [private\_service\_access](#input\_private\_service\_access) | Private Service Access range (private-IP Cloud SQL, Memorystore and other Google-managed services peer through it). | <pre>object({<br/>    enabled       = optional(bool, true)<br/>    name          = optional(string, "google-managed-services")<br/>    prefix_length = optional(number, 16)<br/>  })</pre> | `{}` | no |
| <a name="input_private_service_connect"></a> [private\_service\_connect](#input\_private\_service\_connect) | Private Service Connect endpoint for Google APIs; target is 'all-apis' or 'vpc-sc'. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    target  = optional(string, "all-apis")<br/>  })</pre> | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | The primary GCP region of the network (e.g., 'us-central1', 'europe-west1'). | `string` | `"us-central1"` | no |
| <a name="input_secure_web_proxy"></a> [secure\_web\_proxy](#input\_secure\_web\_proxy) | Opt-in central egress control (preview): a Secure Web Proxy in the hub region with an FQDN<br/>allowlist (everything else is denied). It takes its address from the first primary-region<br/>private subnet. proxy\_only\_subnet\_cidr creates the proxy-only subnet it needs (null = one already<br/>exists). psc\_nat\_subnet\_cidr publishes the proxy through a Private Service Connect service<br/>attachment that accepts consumer\_accept\_projects only; spokes then reach it through a PSC<br/>endpoint (stages/net-spoke egress\_proxy). Clients use it as an explicit proxy<br/>(HTTPS\_PROXY=<address>:<port>). Default: off. | <pre>object({<br/>    enabled       = optional(bool, false)<br/>    address       = optional(string)<br/>    ports         = optional(list(number), [443])<br/>    allowed_fqdns = optional(list(string), [])<br/>    additional_rules = optional(map(object({<br/>      priority            = number<br/>      action              = string<br/>      session_matcher     = string<br/>      application_matcher = optional(string)<br/>      description         = optional(string)<br/>      enabled             = optional(bool, true)<br/>    })), {})<br/>    certificate_urls         = optional(list(string), [])<br/>    proxy_only_subnet_cidr   = optional(string)<br/>    psc_nat_subnet_cidr      = optional(string)<br/>    consumer_accept_projects = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_vpc_service_controls"></a> [vpc\_service\_controls](#input\_vpc\_service\_controls) | VPC Service Controls perimeters, keyed by perimeter name. protected\_projects takes project NUMBERS, not IDs. | <pre>map(object({<br/>    # organization_id must be the FULL resource form 'organizations/<numeric-id>'<br/>    # (Access Context Manager's access-policy parent requires this form). NOTE:<br/>    # this diverges from every other org-id input in the repo (governance/tags,<br/>    # governance/cloud-audit-logs, stages/organization var.org_id) which take the<br/>    # BARE numeric id. Callers prefix the bare org_id output here accordingly.<br/>    # See docs: the vpc-sc module is the sole outlier; a future normalization<br/>    # would have vpc-sc accept the bare id and prefix internally.<br/>    organization_id      = string<br/>    access_policy_name   = optional(string)<br/>    create_access_policy = optional(bool, false)<br/>    perimeter_title      = string<br/>    description          = optional(string, "Managed by Terraform")<br/>    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")<br/>    protected_projects   = optional(list(string), [])<br/>    restricted_services  = optional(list(string), [])<br/>    access_levels = optional(list(object({<br/>      name               = string<br/>      title              = string<br/>      description        = optional(string)<br/>      combining_function = optional(string, "AND")<br/>      conditions = list(object({<br/>        ip_subnetworks = optional(list(string))<br/>        members        = optional(list(string))<br/>        negate         = optional(bool, false)<br/>        regions        = optional(list(string))<br/>      }))<br/>    })), [])<br/>    ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    enable_dry_run             = optional(bool, true)<br/>    enable_deletion_protection = optional(bool, true)<br/>    # Staged dry-run delta on an ENFORCED perimeter (see network/vpc-sc). null = same as enforced.<br/>    dry_run_restricted_services = optional(list(string))<br/>    dry_run_ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })))<br/>    dry_run_egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })))<br/>  }))</pre> | `{}` | no |
| <a name="input_vpn"></a> [vpn](#input\_vpn) | HA VPN to an on-premises or other-cloud peer gateway, off by default.<br/>tunnel\_count is 2 for HA (production) or 1 for testing. peer\_gateway\_ips<br/>lists the peer interface IPv4 addresses (one per tunnel). local\_ips and<br/>peer\_ips are the BGP link-local addresses. The pre-shared key is the separate<br/>vpn\_shared\_secret\_wo (write-only) or legacy vpn\_shared\_secret input. With ncc.enabled, the tunnels also join the NCC hub as a hybrid spoke. | <pre>object({<br/>    enabled          = optional(bool, false)<br/>    tunnel_count     = optional(number, 2)<br/>    router_asn       = optional(number, 64512)<br/>    peer_asn         = optional(number, 64513)<br/>    peer_gateway_ips = optional(list(string), [])<br/>    local_ips        = optional(list(string), ["169.254.0.1", "169.254.0.3"])<br/>    peer_ips         = optional(list(string), ["169.254.0.2", "169.254.0.4"])<br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = string<br/>    })), [])<br/>  })</pre> | `{}` | no |
| <a name="input_vpn_shared_secret"></a> [vpn\_shared\_secret](#input\_vpn\_shared\_secret) | HA VPN pre-shared key, stored in state (legacy). Prefer vpn\_shared\_secret\_wo, which never enters state. Set exactly one of the two when vpn.enabled is true. | `string` | `null` | no |
| <a name="input_vpn_shared_secret_wo"></a> [vpn\_shared\_secret\_wo](#input\_vpn\_shared\_secret\_wo) | Write-only HA VPN pre-shared key: sent to the API at apply time, never stored in state or plan. Supply it from an ephemeral source (an ephemeral resource, or a TFC variable). Set exactly one of vpn\_shared\_secret or vpn\_shared\_secret\_wo when vpn.enabled is true. | `string` | `null` | no |
| <a name="input_vpn_shared_secret_wo_version"></a> [vpn\_shared\_secret\_wo\_version](#input\_vpn\_shared\_secret\_wo\_version) | Rotation counter for vpn\_shared\_secret\_wo. Write-only values are not diffed: increment this to push a changed key. | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_additional_region_routers"></a> [additional\_region\_routers](#output\_additional\_region\_routers) | Cloud Router name per additional region that has Cloud NAT, keyed by region; empty when there is none. |
| <a name="output_additional_region_subnets"></a> [additional\_region\_subnets](#output\_additional\_region\_subnets) | Subnet module outputs of the additional regions, keyed by region, each with public, private and database; empty when additional\_regions is empty. |
| <a name="output_firewall_policy_name"></a> [firewall\_policy\_name](#output\_firewall\_policy\_name) | Name of the tier network firewall policy (pass to network/internal-lb firewall\_policy), or null in firewall\_mode = legacy. |
| <a name="output_hierarchical_firewall_policy_ids"></a> [hierarchical\_firewall\_policy\_ids](#output\_hierarchical\_firewall\_policy\_ids) | The IDs of the hierarchical firewall policies, keyed by policy name. |
| <a name="output_hybrid_connectivity"></a> [hybrid\_connectivity](#output\_hybrid\_connectivity) | Which hybrid connectivity is planned: vpn (HA VPN on), ncc\_vpn\_spoke (tunnels linked to the NCC hub), ncc\_vpn\_spoke\_group and the interconnect attachment names. |
| <a name="output_interconnect_pairing_keys"></a> [interconnect\_pairing\_keys](#output\_interconnect\_pairing\_keys) | Pairing keys for partner interconnects (share with the provider). |
| <a name="output_interconnect_states"></a> [interconnect\_states](#output\_interconnect\_states) | The state of each interconnect attachment. |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | The Cloud NAT IP addresses, or null when NAT is disabled. |
| <a name="output_nat_subnet_tiers"></a> [nat\_subnet\_tiers](#output\_nat\_subnet\_tiers) | Subnet tiers the primary Cloud NAT translates (private, plus database only with nat.include\_database\_subnets); empty when NAT is disabled. |
| <a name="output_ncc_hub_id"></a> [ncc\_hub\_id](#output\_ncc\_hub\_id) | The NCC hub ID that environment spokes attach to (stages/net-spoke ncc.hub\_id), or null when ncc.enabled = false. |
| <a name="output_ncc_spoke_group"></a> [ncc\_spoke\_group](#output\_ncc\_spoke\_group) | The NCC group environment spokes join (edge for STAR, default for MESH), or null when ncc.enabled = false. |
| <a name="output_ncc_vpn_spoke_id"></a> [ncc\_vpn\_spoke\_id](#output\_ncc\_vpn\_spoke\_id) | ID of the NCC hybrid spoke for the HA VPN tunnels, or null unless both ncc.enabled and vpn.enabled. |
| <a name="output_network_alert_policy_ids"></a> [network\_alert\_policy\_ids](#output\_network\_alert\_policy\_ids) | Data-plane alert policy IDs keyed by alert (vpn\_tunnel\_down, bgp\_session\_down, nat\_allocation\_failed, nat\_dropped\_packets); empty when alerting is off or no watched feature exists. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The VPC network ID. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The VPC network name. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The VPC network self link. |
| <a name="output_network_tags"></a> [network\_tags](#output\_network\_tags) | Network tags that select the security tiers in the baseline firewall rules. |
| <a name="output_private_service_access_range_name"></a> [private\_service\_access\_range\_name](#output\_private\_service\_access\_range\_name) | Name of the Private Service Access range reserved on this VPC, or null when PSA is disabled. |
| <a name="output_secure_web_proxy"></a> [secure\_web\_proxy](#output\_secure\_web\_proxy) | The hub Secure Web Proxy: gateway\_id, address (known after apply unless set), ports and service\_attachment\_id (target for spoke PSC endpoints, null when not published). Null when secure\_web\_proxy.enabled = false. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Subnet module outputs by tier (public, private, database), each keyed by zone. |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | The composed VPC module outputs. |
| <a name="output_vpc_service_control_perimeter_names"></a> [vpc\_service\_control\_perimeter\_names](#output\_vpc\_service\_control\_perimeter\_names) | The names of all VPC Service Controls perimeters. |
| <a name="output_vpc_service_controls"></a> [vpc\_service\_controls](#output\_vpc\_service\_controls) | All VPC Service Controls perimeter outputs, keyed by perimeter name. |
| <a name="output_vpn_gateway_ips"></a> [vpn\_gateway\_ips](#output\_vpn\_gateway\_ips) | The HA VPN gateway external IP addresses, or null when VPN is disabled. |
| <a name="output_vpn_tunnel_statuses"></a> [vpn\_tunnel\_statuses](#output\_vpn\_tunnel\_statuses) | The status of each VPN tunnel, or null when VPN is disabled. |
<!-- END_TF_DOCS -->
