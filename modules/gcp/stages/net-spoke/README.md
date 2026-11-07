# net-spoke

Per-environment spoke network composition: the Shared VPC host network of one
application environment. It composes [`network/tiered-vpc`](../../network/tiered-vpc/)
with Cloud NAT, Private Service Access, Private Service Connect, hub peering,
private or peering DNS zones, an opt-in Cloud Armor edge policy, opt-in VPC
flow-log export (CMEK), Shared VPC service-project attachments and the
environment VPC Service Controls perimeter.

Called by [`envs/gcp/workload`](../../../../envs/gcp/workload/). It replaces the
spoke use of the removed `stages/host` module.

## Interface

Related inputs are grouped into typed objects, each with secure defaults:

| Input | Purpose |
|-------|---------|
| `network` | VPC name and CIDR (required), explicit zones, per-tier CIDRs, GKE secondary ranges, Shared VPC host flag, subnet flow-log sampling |
| `firewall` | Rule logging, IAP SSH/RDP rule, tier ports, `additional_rules` |
| `nat` / `private_service_access` / `private_service_connect` | Egress and private Google services, each with an `enabled` flag (default on) |
| `peerings` / `dns_zones` | Hub peering and DNS zones (private or peering) |
| `edge` | `cloud_armor` WAF policy (default on) |
| `flow_logs_export` | Flow-log sink to BigQuery or Cloud Storage (default off) |
| `shared_vpc_service_projects` / `vpc_service_controls` | Governance |

## Migrating from stages/host

Module and resource names match `stages/host`, so a caller that keeps its
module label (as `envs/gcp/workload` does with `module "host"`) only moves the
network core into the `network` building block. Services (NAT, PSA, PSC, Cloud
Armor, peering, DNS, flow-log export, VPC-SC, Shared VPC attachments,
additional firewall rules) keep their addresses.

| stages/host address | net-spoke address |
|---------------------|-------------------|
| `terraform_data.deletion_protection_guard` | `module.network.terraform_data.deletion_protection_guard` |
| `terraform_data.subnet_cidr_count_guard[0]` | `module.network.terraform_data.subnet_cidr_count_guard` |
| `module.vpc[0]` | `module.network.module.vpc` |
| `module.public_subnets` / `private_subnets` / `database_subnets` | `module.network.module.<same>` |
| `module.firewall_<rule>[0]` (six baseline rules) | `module.network.module.firewall_<rule>` |
| `module.firewall_iap_ssh_rdp` | `module.network.module.firewall_iap_ssh_rdp` |

See [`envs/gcp/workload/moved.tf`](../../../../envs/gcp/workload/moved.tf) for
the full set. Input mapping: `vpc_name` / `vpc_cidr_block` / `explicit_zones` /
`subnet_cidrs` / `secondary_ranges` / `enable_shared_vpc_host` /
`log_config_*` go into `network`; `enable_cloud_armor` and the OWASP inputs go
into `edge.cloud_armor`; `vpc_flow_logs_*` go into `flow_logs_export`;
`vpc_peerings` becomes `peerings`. CDN, API Gateway, internal load balancers,
packet mirroring and standalone NAT are not part of the spoke contract: compose
them directly from the `network/` primitives (for example
[`network/app-ingress`](../../network/app-ingress/)).

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

net-spoke - per-environment spoke network composition

The Shared VPC host network of one application environment: a three-tier
VPC (network/tiered-vpc) plus Cloud NAT, Private Service Access, Private
Service Connect, hub connectivity (VPC peering, or an opt-in Network
Connectivity Center spoke), private or peering DNS zones, an opt-in Cloud
Armor edge policy, opt-in VPC flow-log export, Shared VPC service-project
attachments and the environment VPC-SC perimeter.

Replaces the spoke use of the deprecated stages/host module. Module and
resource names deliberately match stages/host so a caller that keeps its
module label only needs `moved` blocks for the network core (see the
README migration table).

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


- additional_firewall_rules - ../../network/network-firewall
- cloud_armor - ../../network/cloud-armor
- dns - ../../network/dns
- flow_logs_kms - ../../governance/kms
- integrated_nat - ../../network/nat
- ncc_spoke - ../../network/ncc-spoke
- network - ../../network/tiered-vpc
- private_service_access - ../../network/private-service-access
- private_service_connect - ../../network/private-service-connect
- shared_vpc_service_projects - ../../network/shared-vpc-service
- vpc_flow_logs - ../../network/vpc-flow-logs
- vpc_peering - ../../network/vpc-peering
- vpc_service_controls - ../../network/vpc-sc


## Resources

The following resources are created:


- data source.google_compute_zones.available (modules/gcp/stages/net-spoke/main.tf#L25)
- data source.google_project.current (modules/gcp/stages/net-spoke/main.tf#L229)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_network"></a> [network](#input\_network) | The VPC and its three-tier zonal subnet layout.<br/>name and cidr\_block are required. Pin explicit\_zones for production: when<br/>empty, zones are discovered from GCP and a change in the returned zone set<br/>re-derives the subnet CIDRs (replacing subnets). subnet\_cidrs lists are<br/>index-aligned with the zones; an empty list derives that tier from<br/>cidr\_block. secondary\_ranges (GKE Pods and Services) attach to the private<br/>tier, keyed by zone. shared\_vpc\_host makes the project a<br/>Shared VPC host (default true). flow\_logs sets the subnet flow-log sampling. | <pre>object({<br/>    name           = string<br/>    cidr_block     = string<br/>    explicit_zones = optional(list(string), [])<br/>    subnet_cidrs = optional(object({<br/>      public   = optional(list(string), [])<br/>      private  = optional(list(string), [])<br/>      database = optional(list(string), [])<br/>    }), {})<br/>    secondary_ranges = optional(map(list(object({<br/>      range_name    = string<br/>      ip_cidr_range = string<br/>    }))), {})<br/>    shared_vpc_host = optional(bool, true)<br/>    flow_logs = optional(object({<br/>      aggregation_interval = optional(string, "INTERVAL_5_SEC")<br/>      sampling             = optional(number, 0.5)<br/>    }), {})<br/>  })</pre> | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID that owns the network (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter). | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix for derived resource names (e.g. 'ashes-dev'). Must start with a letter and contain only lowercase letters, digits, and hyphens. | `string` | n/a | yes |
| <a name="input_connectivity"></a> [connectivity](#input\_connectivity) | How the VPC reaches the hub. peering (default): VPC peering per peerings entry. ncc: a Network Connectivity Center spoke on ncc.hub\_id, with peerings ignored. Switching an existing spoke deletes its peering; see docs/runbooks/gcp-peering-to-ncc-migration.md. | `string` | `"peering"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Guard the VPC and subnet stack with a prevent\_destroy terraform\_data resource and enable VPC deletion protection. To deprovision deliberately, first run terraform state rm on the network module guard. | `bool` | `false` | no |
| <a name="input_dns_zones"></a> [dns\_zones](#input\_dns\_zones) | Cloud DNS zones hosted in this project, keyed by zone name. Private zones bind to this VPC; set peering\_network for a peering zone that resolves through another VPC (for example the hub DNS anchor). Query logging is always on. | <pre>map(object({<br/>    dns_name        = string<br/>    visibility      = string<br/>    description     = optional(string)<br/>    dnssec_enabled  = optional(bool, false)<br/>    peering_network = optional(string)<br/>    records = optional(list(object({<br/>      name    = string<br/>      type    = string<br/>      ttl     = number<br/>      rrdatas = list(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_edge"></a> [edge](#input\_edge) | Edge security for the environment. cloud\_armor is the project-level Cloud<br/>Armor WAF policy named <project\_prefix>-security-policy (OWASP, Log4Shell<br/>and adaptive DDoS protection). custom\_rules entries use either an IP match<br/>(versioned\_expr SRC\_IPS\_V1 plus config.src\_ip\_ranges) or a CEL expr, never<br/>both. Attach the policy to load balancers via the security\_policy\_self\_link<br/>output. | <pre>object({<br/>    cloud_armor = optional(object({<br/>      enabled             = optional(bool, true)<br/>      owasp_rules         = optional(bool, true)<br/>      adaptive_protection = optional(bool, true)<br/>      log4j_protection    = optional(bool, true)<br/>      owasp_sensitivity   = optional(number, 2)<br/>      custom_rules = optional(map(object({<br/>        action      = string<br/>        priority    = number<br/>        description = optional(string)<br/>        match_conditions = object({<br/>          # IP-based match. Set versioned_expr AND config, or set expr — never both.<br/>          versioned_expr = optional(string)<br/>          config = optional(object({<br/>            src_ip_ranges = list(string)<br/>          }))<br/>          # CEL expression match. Mutually exclusive with versioned_expr + config.<br/>          expr = optional(string)<br/>        })<br/>        rate_limit_options = optional(object({<br/>          threshold_count     = number<br/>          interval_sec        = number<br/>          conform_action      = optional(string)<br/>          exceed_action       = optional(string)<br/>          enforce_on_key      = optional(string)<br/>          enforce_on_key_type = optional(string)<br/>        }))<br/>      })), {})<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_firewall"></a> [firewall](#input\_firewall) | Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database, plus additional\_rules (VPC firewall rules keyed by rule name). api\_gateway\_source\_ranges and database\_egress\_target\_service\_accounts apply only to the network firewall policy (firewall\_mode both / policy). | <pre>object({<br/>    enable_logging     = optional(bool, true)<br/>    enable_iap_access  = optional(bool, true)<br/>    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])<br/>    database_ports     = optional(list(string), ["3306", "5432", "6379"])<br/>    # Network firewall policy only (firewall_mode both / policy).<br/>    api_gateway_source_ranges               = optional(list(string), [])<br/>    database_egress_target_service_accounts = optional(list(string), [])<br/>    additional_rules = optional(map(object({<br/>      direction   = optional(string, "INGRESS")<br/>      description = optional(string)<br/>      priority    = optional(number, 1000)<br/>      allow_rules = optional(list(object({<br/>        protocol = string<br/>        ports    = optional(list(string))<br/>      })), [])<br/>      deny_rules = optional(list(object({<br/>        protocol = string<br/>        ports    = optional(list(string))<br/>      })), [])<br/>      source_ranges = optional(list(string))<br/>      target_tags   = optional(list(string))<br/>      source_tags   = optional(list(string))<br/>    })), {})<br/>  })</pre> | `{}` | no |
| <a name="input_firewall_mode"></a> [firewall\_mode](#input\_firewall\_mode) | How the baseline tier firewall is enforced (network/tiered-vpc firewall\_mode). legacy: tag-based VPC firewall rules (default). both: the VPC rules plus a global network firewall policy keyed on tier subnet CIDRs. policy: the network firewall policy only. See docs/runbooks/gcp-firewall-policy-migration.md. | `string` | `"legacy"` | no |
| <a name="input_firewall_policy_enforcement_order"></a> [firewall\_policy\_enforcement\_order](#input\_firewall\_policy\_enforcement\_order) | Network firewall policy enforcement order on the VPC: BEFORE\_CLASSIC\_FIREWALL or AFTER\_CLASSIC\_FIREWALL. null derives it from firewall\_mode (policy sets BEFORE\_CLASSIC\_FIREWALL; legacy and both leave the API default AFTER\_CLASSIC\_FIREWALL). Updates the network in place. WARNING: switching from both to policy with this unset flips the order in the same apply that deletes the legacy rules; set it explicitly. | `string` | `null` | no |
| <a name="input_flow_logs_export"></a> [flow\_logs\_export](#input\_flow\_logs\_export) | Export of VPC flow logs to BigQuery and/or Cloud Storage through a log sink,<br/>encrypted with a dedicated CMEK key. Off by default. When enabled, either set<br/>create\_bigquery\_dataset = true (the sink destination is then derived from<br/>bigquery\_dataset\_id) or give an explicit destination URI. | <pre>object({<br/>    enabled                 = optional(bool, false)<br/>    sink_name               = optional(string, "vpc-flow-logs-sink")<br/>    destination             = optional(string, "")<br/>    create_bigquery_dataset = optional(bool, false)<br/>    bigquery_dataset_id     = optional(string, "vpc_flow_logs")<br/>    bigquery_location       = optional(string, "US")<br/>    create_storage_bucket   = optional(bool, false)<br/>    storage_bucket_name     = optional(string, "")<br/>    storage_location        = optional(string, "US")<br/>    retention_days          = optional(number, 90)<br/>  })</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource. | `map(string)` | `{}` | no |
| <a name="input_nat"></a> [nat](#input\_nat) | Cloud NAT (and its Cloud Router) for the private and database tiers. Set enabled = false for a network with no egress need. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    ip_allocate_option = optional(string, "AUTO_ONLY")<br/>    log_filter         = optional(string, "ERRORS_ONLY")<br/>  })</pre> | `{}` | no |
| <a name="input_ncc"></a> [ncc](#input\_ncc) | NCC spoke settings, used when connectivity = ncc. hub\_id: the network/ncc-hub id. group: edge (STAR hub) or default (MESH hub). Export ranges filter the subnet ranges the hub learns. export\_private\_service\_access adds a producer VPC spoke for the PSA peering (when PSA is enabled). | <pre>object({<br/>    hub_id                        = optional(string)<br/>    group                         = optional(string, "edge")<br/>    include_export_ranges         = optional(list(string), [])<br/>    exclude_export_ranges         = optional(list(string), [])<br/>    export_private_service_access = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_peerings"></a> [peerings](#input\_peerings) | VPC peerings from this network, keyed by peering name (for example the spoke-to-hub peering). | <pre>map(object({<br/>    peer_network           = string<br/>    create_reverse_peering = optional(bool, true)<br/>    export_custom_routes   = optional(bool, false)<br/>    import_custom_routes   = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_private_service_access"></a> [private\_service\_access](#input\_private\_service\_access) | Private Service Access range (private-IP Cloud SQL, Memorystore and other Google-managed services peer through it). | <pre>object({<br/>    enabled       = optional(bool, true)<br/>    name          = optional(string, "google-managed-services")<br/>    prefix_length = optional(number, 16)<br/>  })</pre> | `{}` | no |
| <a name="input_private_service_connect"></a> [private\_service\_connect](#input\_private\_service\_connect) | Private Service Connect endpoint for Google APIs; target is 'all-apis' or 'vpc-sc'. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    target  = optional(string, "all-apis")<br/>  })</pre> | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | The primary GCP region of the network (e.g., 'us-central1', 'europe-west1'). | `string` | `"us-central1"` | no |
| <a name="input_shared_vpc_service_projects"></a> [shared\_vpc\_service\_projects](#input\_shared\_vpc\_service\_projects) | Map of service projects to attach to this host project (ignored unless network.shared\_vpc\_host is true) | <pre>map(object({<br/>    deletion_policy = optional(string, "ABANDON")<br/>    subnet_iam_bindings = optional(list(object({<br/>      subnet = string<br/>      region = string<br/>      member = string<br/>    })), [])<br/>    grant_network_user_to_all_subnets = optional(bool, false)<br/>    network_user_members              = optional(list(string), [])<br/>    network_viewer_members            = optional(list(string), [])<br/>    enable_gke_permissions            = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_service_controls"></a> [vpc\_service\_controls](#input\_vpc\_service\_controls) | Map of VPC Service Controls perimeters to create | <pre>map(object({<br/>    # organization_id must be the FULL resource form 'organizations/<numeric-id>'<br/>    # (Access Context Manager's access-policy parent requires this form). NOTE:<br/>    # this diverges from every other org-id input in the repo (governance/tags,<br/>    # governance/cloud-audit-logs, stages/organization var.org_id) which take the<br/>    # BARE numeric id. Callers prefix the bare org_id output here accordingly.<br/>    # See docs: the vpc-sc module is the sole outlier; a future normalization<br/>    # would have vpc-sc accept the bare id and prefix internally.<br/>    organization_id      = string<br/>    access_policy_name   = optional(string)<br/>    create_access_policy = optional(bool, false)<br/>    perimeter_title      = string<br/>    description          = optional(string, "Managed by Terraform")<br/>    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")<br/>    protected_projects   = optional(list(string), [])<br/>    restricted_services  = optional(list(string), [])<br/>    access_levels = optional(list(object({<br/>      name               = string<br/>      title              = string<br/>      description        = optional(string)<br/>      combining_function = optional(string, "AND")<br/>      conditions = list(object({<br/>        ip_subnetworks = optional(list(string))<br/>        members        = optional(list(string))<br/>        negate         = optional(bool, false)<br/>        regions        = optional(list(string))<br/>      }))<br/>    })), [])<br/>    ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    enable_dry_run             = optional(bool, true)<br/>    enable_deletion_protection = optional(bool, true)<br/>    # Staged dry-run delta on an ENFORCED perimeter (see network/vpc-sc). null = same as enforced.<br/>    dry_run_restricted_services = optional(list(string))<br/>    dry_run_ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })))<br/>    dry_run_egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_additional_firewall_rule_ids"></a> [additional\_firewall\_rule\_ids](#output\_additional\_firewall\_rule\_ids) | IDs of the additional firewall rules, keyed by rule name. |
| <a name="output_cloud_armor"></a> [cloud\_armor](#output\_cloud\_armor) | The Cloud Armor security policy module outputs, or null when disabled. |
| <a name="output_dns_name_servers"></a> [dns\_name\_servers](#output\_dns\_name\_servers) | Name servers for each DNS zone. |
| <a name="output_dns_zones"></a> [dns\_zones](#output\_dns\_zones) | All DNS zone outputs, keyed by zone name. |
| <a name="output_firewall_policy_name"></a> [firewall\_policy\_name](#output\_firewall\_policy\_name) | Name of the tier network firewall policy (pass to network/internal-lb firewall\_policy), or null in firewall\_mode = legacy. |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | The Cloud NAT IP addresses, or null when NAT is disabled. |
| <a name="output_ncc_producer_spoke_ids"></a> [ncc\_producer\_spoke\_ids](#output\_ncc\_producer\_spoke\_ids) | NCC producer VPC spoke IDs (Private Service Access), keyed by name; empty when connectivity = peering. |
| <a name="output_ncc_spoke_id"></a> [ncc\_spoke\_id](#output\_ncc\_spoke\_id) | The NCC spoke ID, or null when connectivity = peering. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The VPC network ID. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The VPC network name. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The VPC network self link. |
| <a name="output_network_tags"></a> [network\_tags](#output\_network\_tags) | Network tags that select the security tiers in the baseline firewall rules. |
| <a name="output_peering_states"></a> [peering\_states](#output\_peering\_states) | The state of each VPC peering connection. |
| <a name="output_private_service_access_range_name"></a> [private\_service\_access\_range\_name](#output\_private\_service\_access\_range\_name) | Name of the Private Service Access range reserved on this VPC, or null when PSA is disabled. |
| <a name="output_security_policy_id"></a> [security\_policy\_id](#output\_security\_policy\_id) | The Cloud Armor security policy ID, or null when disabled. |
| <a name="output_security_policy_self_link"></a> [security\_policy\_self\_link](#output\_security\_policy\_self\_link) | The Cloud Armor security policy self link, or null when disabled. |
| <a name="output_shared_vpc_service_project_ids"></a> [shared\_vpc\_service\_project\_ids](#output\_shared\_vpc\_service\_project\_ids) | The IDs of the Shared VPC service project attachments, keyed by service project. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Subnet module outputs by tier (public, private, database), each keyed by zone. |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | The composed VPC module outputs. |
| <a name="output_vpc_flow_logs_kms_key_name"></a> [vpc\_flow\_logs\_kms\_key\_name](#output\_vpc\_flow\_logs\_kms\_key\_name) | The CMEK key encrypting exported flow logs, or null when export is disabled. |
| <a name="output_vpc_flow_logs_sink_name"></a> [vpc\_flow\_logs\_sink\_name](#output\_vpc\_flow\_logs\_sink\_name) | The Cloud Logging sink that exports VPC flow logs, or null when export is disabled. |
| <a name="output_vpc_flow_logs_sink_writer_identity"></a> [vpc\_flow\_logs\_sink\_writer\_identity](#output\_vpc\_flow\_logs\_sink\_writer\_identity) | The sink writer identity to grant on the destination, or null when export is disabled. |
| <a name="output_vpc_peerings"></a> [vpc\_peerings](#output\_vpc\_peerings) | All VPC peering outputs, keyed by peering name. |
| <a name="output_vpc_service_control_perimeter_names"></a> [vpc\_service\_control\_perimeter\_names](#output\_vpc\_service\_control\_perimeter\_names) | The names of all VPC Service Controls perimeters. |
| <a name="output_vpc_service_controls"></a> [vpc\_service\_controls](#output\_vpc\_service\_controls) | All VPC Service Controls perimeter outputs, keyed by perimeter name. |
<!-- END_TF_DOCS -->
