# Host Module

Unified infrastructure orchestration module that serves as the central entrypoint for project provisioning.

## Overview

This module instantiates and coordinates all network, security, and governance modules to provide a complete infrastructure foundation. It eliminates the need to manually wire together individual modules and ensures consistent configuration across all components.

## Features

- **Core Networking**: VPC with tiered subnets (public/private/database), NAT gateway, and flow logging
- **Edge Security**: Cloud Armor WAF with OWASP Top 10 protection and adaptive DDoS defense
- **Content Delivery**: Global Load Balancer with Cloud CDN and HTTP→HTTPS redirect
- **DNS Management**: Public and private DNS zones with DNSSEC support
- **Hybrid Connectivity**: HA VPN with BGP routing
- **Network Peering**: VPC peering for hub-and-spoke architectures
- **API Management**: API Gateway with OpenAPI spec support

## Usage

### Minimal Example

```hcl
module "infrastructure" {
  source = "../modules/host"

  project_id     = "my-project-id"
  project_prefix = "myapp-dev"
  region         = "us-central1"

  enable_networking = true
}
```

### Production Example

```hcl
module "infrastructure" {
  source = "../modules/host"

  project_id     = "my-project-id"
  project_prefix = "myapp-prod"
  region         = "us-central1"

  # Networking
  enable_networking              = true
  vpc_name                       = "production-vpc"
  enable_private_service_access  = true
  enable_private_service_connect = true
  enable_deletion_protection     = true

  # Security
  enable_cloud_armor         = true
  enable_owasp_rules         = true
  enable_adaptive_protection = true
  owasp_sensitivity          = 2

  # CDN
  enable_cdn   = true
  cdn_domains  = ["app.example.com", "api.example.com"]
  
  # DNS
  dns_zones = {
    "example-public" = {
      dns_name   = "example.com."
      visibility = "public"
      dnssec_enabled = true
    }
    "example-private" = {
      dns_name   = "internal.example.com."
      visibility = "private"
    }
  }

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
```

## Inputs

See [variables.tf](variables.tf) for the complete list of input variables.

### Key Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `project_id` | The GCP project ID | `string` | **required** |
| `project_prefix` | Prefix for resource naming | `string` | **required** |
| `region` | Primary GCP region | `string` | `"us-central1"` |
| `enable_networking` | Enable VPC provisioning | `bool` | `true` |
| `enable_cloud_armor` | Enable Cloud Armor WAF | `bool` | `true` |
| `enable_cdn` | Enable CDN/Global LB | `bool` | `false` |
| `enable_vpn` | Enable Cloud VPN | `bool` | `false` |

## Outputs

See [outputs.tf](outputs.tf) for the complete list of outputs.

### Key Outputs

| Name | Description |
|------|-------------|
| `network_id` | The VPC network ID |
| `network_self_link` | The VPC network self link |
| `subnets` | All subnet outputs by tier |
| `security_policy_self_link` | Cloud Armor policy self link |
| `cdn_ip` | Global load balancer IP |
| `dns_name_servers` | Name servers for public zones |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host Module                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌───────────────┐  ┌─────────────────────┐   │
│  │     VPC     │  │  Cloud Armor  │  │        CDN          │   │
│  │  + Subnets  │  │  + OWASP WAF  │  │ + Global LB         │   │
│  │  + NAT      │  │  + Adaptive   │  │ + SSL Cert          │   │
│  │  + Firewall │  │               │  │ + HTTP Redirect     │   │
│  └─────────────┘  └───────────────┘  └─────────────────────┘   │
│                                                                  │
│  ┌─────────────┐  ┌───────────────┐  ┌─────────────────────┐   │
│  │     DNS     │  │      VPN      │  │    API Gateway      │   │
│  │  + Public   │  │  + HA VPN     │  │  + OpenAPI          │   │
│  │  + Private  │  │  + BGP        │  │  + Serverless NEG   │   │
│  │  + DNSSEC   │  │  + Tunnels    │  │                     │   │
│  └─────────────┘  └───────────────┘  └─────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     VPC Peering                           │   │
│  │               (Hub-and-Spoke Connectivity)                │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| google | >= 4.80.0 |
| google-beta | >= 4.80.0 |

## License

Copyright 2023 Ashes

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Host Module - Unified Infrastructure Orchestration

This module serves as the central entrypoint for project provisioning,
instantiating all network, security, and governance modules.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	project_prefix = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 4.80.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 4.80.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |

## Modules


- additional_firewall_rules - ../network/network-firewall
- api_gateway - ../network/api_gateway
- cdn - ../network/cdn
- cloud_armor - ../network/cloud_armor
- database_subnets - ../network/subnet
- dns - ../network/dns
- firewall_apigateway_to_public - ../network/network-firewall
- firewall_compute_to_database - ../network/network-firewall
- firewall_database_deny_egress - ../network/network-firewall
- firewall_deny_all - ../network/network-firewall
- firewall_health_checks - ../network/network-firewall
- firewall_iap_ssh_rdp - ../network/network-firewall
- firewall_public_to_compute - ../network/network-firewall
- hierarchical_firewall_policies - ../network/hierarchical-firewall
- integrated_nat - ../network/nat
- interconnects - ../network/interconnect
- internal_load_balancers - ../network/internal-lb
- packet_mirroring - ../network/packet-mirroring
- private_service_access - ../network/private-service-access
- private_service_connect - ../network/private-service-connect
- private_subnets - ../network/subnet
- public_subnets - ../network/subnet
- shared_vpc_service_projects - ../network/shared-vpc-service
- standalone_nat - ../network/nat
- vpc - ../network/vpc
- vpc_flow_logs - ../network/vpc-flow-logs
- vpc_peering - ../network/vpc-peering
- vpc_service_controls - ../network/vpc-sc
- vpn - ../network/vpn


## Resources

The following resources are created:


- data source.google_compute_zones.available (modules/host/main.tf#L38)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix for naming resources (e.g., 'ashes-dev') | `string` | n/a | yes |
| <a name="input_additional_firewall_rules"></a> [additional\_firewall\_rules](#input\_additional\_firewall\_rules) | Map of additional firewall rules to create outside of the VPC module | <pre>map(object({<br/>    direction   = optional(string, "INGRESS")<br/>    description = optional(string)<br/>    priority    = optional(number, 1000)<br/>    allow_rules = optional(list(object({<br/>      protocol = string<br/>      ports    = optional(list(string))<br/>    })), [])<br/>    deny_rules = optional(list(object({<br/>      protocol = string<br/>      ports    = optional(list(string))<br/>    })), [])<br/>    source_ranges = optional(list(string))<br/>    target_tags   = optional(list(string))<br/>    source_tags   = optional(list(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_api_gateway_display_name"></a> [api\_gateway\_display\_name](#input\_api\_gateway\_display\_name) | Display name for the API Gateway | `string` | `"API Gateway"` | no |
| <a name="input_api_gateway_managed_services"></a> [api\_gateway\_managed\_services](#input\_api\_gateway\_managed\_services) | Map of managed service IDs for auto-generated OpenAPI spec | `map(string)` | `{}` | no |
| <a name="input_api_gateway_openapi_spec"></a> [api\_gateway\_openapi\_spec](#input\_api\_gateway\_openapi\_spec) | Custom OpenAPI specification (if not using managed\_service\_ids) | `string` | `""` | no |
| <a name="input_api_gateway_service_account"></a> [api\_gateway\_service\_account](#input\_api\_gateway\_service\_account) | Service account email for API Gateway backend | `string` | `""` | no |
| <a name="input_cdn_backend_groups"></a> [cdn\_backend\_groups](#input\_cdn\_backend\_groups) | Backend groups for the CDN load balancer | <pre>list(object({<br/>    group           = string<br/>    balancing_mode  = optional(string)<br/>    capacity_scaler = optional(number)<br/>    description     = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_cdn_domains"></a> [cdn\_domains](#input\_cdn\_domains) | Domains for managed SSL certificate | `list(string)` | `[]` | no |
| <a name="input_cdn_enable_http_redirect"></a> [cdn\_enable\_http\_redirect](#input\_cdn\_enable\_http\_redirect) | Enable HTTP to HTTPS redirect | `bool` | `true` | no |
| <a name="input_cdn_policy"></a> [cdn\_policy](#input\_cdn\_policy) | CDN caching policy configuration | <pre>object({<br/>    cache_mode                   = optional(string, "CACHE_ALL_STATIC")<br/>    client_ttl                   = optional(number, 3600)<br/>    default_ttl                  = optional(number, 3600)<br/>    max_ttl                      = optional(number, 86400)<br/>    negative_caching             = optional(bool, true)<br/>    signed_url_cache_max_age_sec = optional(number, 0)<br/>  })</pre> | `{}` | no |
| <a name="input_cloud_armor_custom_rules"></a> [cloud\_armor\_custom\_rules](#input\_cloud\_armor\_custom\_rules) | Custom Cloud Armor rules (map of rule name to rule config) | <pre>map(object({<br/>    action      = string<br/>    priority    = number<br/>    description = optional(string)<br/>    match_conditions = object({<br/>      versioned_expr = string<br/>      config = object({<br/>        src_ip_ranges = list(string)<br/>      })<br/>    })<br/>    rate_limit_options = optional(object({<br/>      threshold_count     = number<br/>      interval_sec        = number<br/>      conform_action      = optional(string)<br/>      exceed_action       = optional(string)<br/>      enforce_on_key      = optional(string)<br/>      enforce_on_key_type = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_compute_tier_ports"></a> [compute\_tier\_ports](#input\_compute\_tier\_ports) | Ports allowed from public to compute tier. WARNING: Exposing ports directly to 0.0.0.0/0 is discouraged. Prefer using Global Load Balancers with Cloud Armor. | `list(string)` | <pre>[<br/>  "8080",<br/>  "8443",<br/>  "3000"<br/>]</pre> | no |
| <a name="input_database_ports"></a> [database\_ports](#input\_database\_ports) | Database ports to allow from compute to database tier | `list(string)` | <pre>[<br/>  "3306",<br/>  "5432",<br/>  "6379"<br/>]</pre> | no |
| <a name="input_dns_zones"></a> [dns\_zones](#input\_dns\_zones) | Map of DNS zones to create | <pre>map(object({<br/>    dns_name        = string<br/>    visibility      = string<br/>    description     = optional(string)<br/>    dnssec_enabled  = optional(bool, false)<br/>    peering_network = optional(string)<br/>    records = optional(list(object({<br/>      name    = string<br/>      type    = string<br/>      ttl     = number<br/>      rrdatas = list(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_adaptive_protection"></a> [enable\_adaptive\_protection](#input\_enable\_adaptive\_protection) | Enable Cloud Armor adaptive protection (DDoS) | `bool` | `true` | no |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable API Gateway | `bool` | `false` | no |
| <a name="input_enable_cdn"></a> [enable\_cdn](#input\_enable\_cdn) | Enable Cloud CDN with Global Load Balancer | `bool` | `false` | no |
| <a name="input_enable_cloud_armor"></a> [enable\_cloud\_armor](#input\_enable\_cloud\_armor) | Enable Cloud Armor WAF security policy | `bool` | `true` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Enable lifecycle prevent\_destroy for critical resources | `bool` | `false` | no |
| <a name="input_enable_firewall_logging"></a> [enable\_firewall\_logging](#input\_enable\_firewall\_logging) | Enable logging for all firewall rules | `bool` | `true` | no |
| <a name="input_enable_iap_access"></a> [enable\_iap\_access](#input\_enable\_iap\_access) | Enable IAP SSH/RDP access | `bool` | `true` | no |
| <a name="input_enable_networking"></a> [enable\_networking](#input\_enable\_networking) | Enable VPC and network infrastructure provisioning | `bool` | `true` | no |
| <a name="input_enable_owasp_rules"></a> [enable\_owasp\_rules](#input\_enable\_owasp\_rules) | Enable OWASP Top 10 WAF rules | `bool` | `true` | no |
| <a name="input_enable_private_service_access"></a> [enable\_private\_service\_access](#input\_enable\_private\_service\_access) | Enable Private Service Access for Cloud SQL, Redis, etc. | `bool` | `true` | no |
| <a name="input_enable_private_service_connect"></a> [enable\_private\_service\_connect](#input\_enable\_private\_service\_connect) | Enable Private Service Connect for Google APIs | `bool` | `true` | no |
| <a name="input_enable_shared_vpc_host"></a> [enable\_shared\_vpc\_host](#input\_enable\_shared\_vpc\_host) | Enable this project as a Shared VPC Host | `bool` | `false` | no |
| <a name="input_enable_vpc_flow_logs_export"></a> [enable\_vpc\_flow\_logs\_export](#input\_enable\_vpc\_flow\_logs\_export) | Enable VPC Flow Logs export to BigQuery or Cloud Storage | `bool` | `false` | no |
| <a name="input_enable_vpn"></a> [enable\_vpn](#input\_enable\_vpn) | Enable Cloud VPN for hybrid connectivity | `bool` | `false` | no |
| <a name="input_existing_network_id"></a> [existing\_network\_id](#input\_existing\_network\_id) | ID of existing network (when enable\_networking is false) | `string` | `""` | no |
| <a name="input_existing_network_name"></a> [existing\_network\_name](#input\_existing\_network\_name) | Name of existing network (when enable\_networking is false) | `string` | `""` | no |
| <a name="input_existing_network_self_link"></a> [existing\_network\_self\_link](#input\_existing\_network\_self\_link) | Self link of existing network (when enable\_networking is false) | `string` | `""` | no |
| <a name="input_hierarchical_firewall_policies"></a> [hierarchical\_firewall\_policies](#input\_hierarchical\_firewall\_policies) | Map of hierarchical firewall policies to create at org/folder level | <pre>map(object({<br/>    parent      = string<br/>    description = optional(string, "Managed by Terraform")<br/>    rules = optional(list(object({<br/>      priority       = number<br/>      action         = string<br/>      direction      = string<br/>      description    = optional(string)<br/>      disabled       = optional(bool, false)<br/>      enable_logging = optional(bool, false)<br/>      layer4_configs = list(object({<br/>        ip_protocol = string<br/>        ports       = optional(list(string))<br/>      }))<br/>      src_ip_ranges           = optional(list(string))<br/>      src_region_codes        = optional(list(string))<br/>      dest_ip_ranges          = optional(list(string))<br/>      dest_region_codes       = optional(list(string))<br/>      target_networks         = optional(list(string))<br/>      target_service_accounts = optional(list(string))<br/>    })), [])<br/>    associations   = optional(list(string), [])<br/>    enable_logging = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_interconnects"></a> [interconnects](#input\_interconnects) | Map of Cloud Interconnect attachments to create | <pre>map(object({<br/>    region            = string<br/>    interconnect_type = optional(string, "PARTNER")<br/>    router_name       = string<br/>    router_asn        = optional(number, 64512)<br/>    create_router     = optional(bool, true)<br/><br/>    # Dedicated interconnect settings<br/>    interconnect_self_link = optional(string)<br/>    vlan_tag               = optional(number)<br/>    bandwidth              = optional(string, "BPS_10G")<br/><br/>    # Partner interconnect settings<br/>    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")<br/><br/>    # Common settings<br/>    mtu           = optional(number, 1440)<br/>    admin_enabled = optional(bool, true)<br/>    encryption    = optional(string, "NONE")<br/><br/>    # BGP settings<br/>    create_bgp_peer    = optional(bool, true)<br/>    interface_ip_range = optional(string)<br/>    peer_ip_address    = optional(string)<br/>    peer_asn           = optional(number, 65000)<br/>    enable_bfd         = optional(bool, false)<br/><br/>    advertised_ip_ranges = optional(list(object({<br/>      range       = string<br/>      description = optional(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_internal_load_balancers"></a> [internal\_load\_balancers](#input\_internal\_load\_balancers) | Map of internal HTTP(S) load balancers to create | <pre>map(object({<br/>    region     = string<br/>    subnet     = string<br/>    is_l7      = optional(bool, true)<br/>    port_range = optional(string, "80")<br/><br/>    backends = list(object({<br/>      group           = string<br/>      balancing_mode  = optional(string, "UTILIZATION")<br/>      capacity_scaler = optional(number, 1.0)<br/>      max_utilization = optional(number, 0.8)<br/>    }))<br/><br/>    # Health check<br/>    health_check_type         = optional(string, "HTTP")<br/>    health_check_port         = optional(number, 80)<br/>    health_check_request_path = optional(string, "/health")<br/><br/>    # Optional settings<br/>    allow_global_access = optional(bool, false)<br/>    enable_ssl          = optional(bool, false)<br/>    ssl_certificates    = optional(list(string), [])<br/>    session_affinity    = optional(string, "NONE")<br/>    enable_logging      = optional(bool, true)<br/><br/>    # Firewall<br/>    create_firewall_rule     = optional(bool, true)<br/>    proxy_only_subnet_ranges = optional(list(string), [])<br/>    backend_target_tags      = optional(list(string), [])<br/>    backend_port             = optional(number, 80)<br/><br/>    labels = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_log_config_aggregation_interval"></a> [log\_config\_aggregation\_interval](#input\_log\_config\_aggregation\_interval) | Flow logs aggregation interval | `string` | `"INTERVAL_5_SEC"` | no |
| <a name="input_log_config_flow_sampling"></a> [log\_config\_flow\_sampling](#input\_log\_config\_flow\_sampling) | Flow logs sampling rate (0.0 to 1.0) | `number` | `0.5` | no |
| <a name="input_owasp_sensitivity"></a> [owasp\_sensitivity](#input\_owasp\_sensitivity) | OWASP rule sensitivity (1-4, lower is more strict) | `number` | `2` | no |
| <a name="input_packet_mirroring_policies"></a> [packet\_mirroring\_policies](#input\_packet\_mirroring\_policies) | Map of packet mirroring policies to create | <pre>map(object({<br/>    region               = string<br/>    collector_ilb_url    = string<br/>    mirrored_instances   = optional(list(string), [])<br/>    mirrored_subnetworks = optional(list(string), [])<br/>    mirrored_tags        = optional(list(string), [])<br/>    filter_ip_protocols  = optional(list(string), [])<br/>    filter_cidr_ranges   = optional(list(string), [])<br/>    filter_direction     = optional(string, "BOTH")<br/>    priority             = optional(number, 1000)<br/>    enable               = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_psa_name"></a> [psa\_name](#input\_psa\_name) | Name of the Private Service Access allocation | `string` | `"google-managed-services"` | no |
| <a name="input_psa_prefix_length"></a> [psa\_prefix\_length](#input\_psa\_prefix\_length) | Prefix length for Private Service Access (e.g. 16 for /16) | `number` | `16` | no |
| <a name="input_psc_target"></a> [psc\_target](#input\_psc\_target) | Target for Private Service Connect (e.g. 'all-apis' or 'vpc-sc') | `string` | `"all-apis"` | no |
| <a name="input_region"></a> [region](#input\_region) | The primary GCP region for resources | `string` | `"us-central1"` | no |
| <a name="input_secondary_ranges"></a> [secondary\_ranges](#input\_secondary\_ranges) | Secondary IP ranges for private subnets (required for GKE Pods/Services). Key is the zone name. | <pre>map(list(object({<br/>    range_name    = string<br/>    ip_cidr_range = string<br/>  })))</pre> | `{}` | no |
| <a name="input_shared_vpc_service_projects"></a> [shared\_vpc\_service\_projects](#input\_shared\_vpc\_service\_projects) | Map of service projects to attach to this host project (requires enable\_shared\_vpc\_host = true) | <pre>map(object({<br/>    deletion_policy = optional(string, "ABANDON")<br/>    subnet_iam_bindings = optional(list(object({<br/>      subnet = string<br/>      region = string<br/>      member = string<br/>    })), [])<br/>    grant_network_user_to_all_subnets = optional(bool, false)<br/>    network_user_members              = optional(list(string), [])<br/>    network_viewer_members            = optional(list(string), [])<br/>    enable_gke_permissions            = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_standalone_nat_gateways"></a> [standalone\_nat\_gateways](#input\_standalone\_nat\_gateways) | Map of standalone NAT gateways to create (for multi-region or custom NAT configurations) | <pre>map(object({<br/>    region                             = string<br/>    create_router                      = optional(bool, true)<br/>    router_name                        = optional(string)<br/>    nat_ip_allocate_option             = optional(string, "AUTO_ONLY")<br/>    nat_ips                            = optional(list(string), [])<br/>    source_subnetwork_ip_ranges_to_nat = optional(string, "ALL_SUBNETWORKS_ALL_IP_RANGES")<br/>    subnetworks = optional(list(object({<br/>      name                     = string<br/>      source_ip_ranges_to_nat  = list(string)<br/>      secondary_ip_range_names = optional(list(string))<br/>    })), [])<br/>    min_ports_per_vm               = optional(number, 64)<br/>    enable_dynamic_port_allocation = optional(bool, false)<br/>    enable_logging                 = optional(bool, true)<br/>    log_filter                     = optional(string, "ERRORS_ONLY")<br/>  }))</pre> | `{}` | no |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | Subnet CIDRs for public, private, and database tiers | <pre>object({<br/>    public   = list(string)<br/>    private  = list(string)<br/>    database = list(string)<br/>  })</pre> | <pre>{<br/>  "database": [],<br/>  "private": [],<br/>  "public": []<br/>}</pre> | no |
| <a name="input_vpc_cidr_block"></a> [vpc\_cidr\_block](#input\_vpc\_cidr\_block) | The CIDR block for the VPC. If not provided, it will be auto-calculated based on the VPC name hash. | `string` | `null` | no |
| <a name="input_vpc_flow_logs_bigquery_dataset_id"></a> [vpc\_flow\_logs\_bigquery\_dataset\_id](#input\_vpc\_flow\_logs\_bigquery\_dataset\_id) | BigQuery dataset ID for flow logs | `string` | `"vpc_flow_logs"` | no |
| <a name="input_vpc_flow_logs_bigquery_location"></a> [vpc\_flow\_logs\_bigquery\_location](#input\_vpc\_flow\_logs\_bigquery\_location) | Location for the BigQuery dataset | `string` | `"US"` | no |
| <a name="input_vpc_flow_logs_create_bigquery_dataset"></a> [vpc\_flow\_logs\_create\_bigquery\_dataset](#input\_vpc\_flow\_logs\_create\_bigquery\_dataset) | Whether to create a BigQuery dataset for flow logs | `bool` | `false` | no |
| <a name="input_vpc_flow_logs_create_storage_bucket"></a> [vpc\_flow\_logs\_create\_storage\_bucket](#input\_vpc\_flow\_logs\_create\_storage\_bucket) | Whether to create a Cloud Storage bucket for flow logs | `bool` | `false` | no |
| <a name="input_vpc_flow_logs_destination"></a> [vpc\_flow\_logs\_destination](#input\_vpc\_flow\_logs\_destination) | Destination for VPC Flow Logs (e.g., bigquery.googleapis.com/projects/PROJECT/datasets/DATASET) | `string` | `""` | no |
| <a name="input_vpc_flow_logs_retention_days"></a> [vpc\_flow\_logs\_retention\_days](#input\_vpc\_flow\_logs\_retention\_days) | Days to retain flow logs data | `number` | `90` | no |
| <a name="input_vpc_flow_logs_sink_name"></a> [vpc\_flow\_logs\_sink\_name](#input\_vpc\_flow\_logs\_sink\_name) | Name of the VPC Flow Logs sink | `string` | `"vpc-flow-logs-sink"` | no |
| <a name="input_vpc_flow_logs_storage_bucket_name"></a> [vpc\_flow\_logs\_storage\_bucket\_name](#input\_vpc\_flow\_logs\_storage\_bucket\_name) | Cloud Storage bucket name for flow logs | `string` | `""` | no |
| <a name="input_vpc_flow_logs_storage_location"></a> [vpc\_flow\_logs\_storage\_location](#input\_vpc\_flow\_logs\_storage\_location) | Location for the Cloud Storage bucket | `string` | `"US"` | no |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | Name of the VPC network | `string` | `"main-vpc"` | no |
| <a name="input_vpc_peerings"></a> [vpc\_peerings](#input\_vpc\_peerings) | Map of VPC peering configurations | <pre>map(object({<br/>    peer_network           = string<br/>    create_reverse_peering = optional(bool, true)<br/>    export_custom_routes   = optional(bool, false)<br/>    import_custom_routes   = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_service_controls"></a> [vpc\_service\_controls](#input\_vpc\_service\_controls) | Map of VPC Service Controls perimeters to create | <pre>map(object({<br/>    organization_id      = string<br/>    access_policy_name   = optional(string)<br/>    create_access_policy = optional(bool, false)<br/>    perimeter_title      = string<br/>    description          = optional(string, "Managed by Terraform")<br/>    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")<br/>    protected_projects   = optional(list(string), [])<br/>    restricted_services  = optional(list(string), [])<br/>    access_levels = optional(list(object({<br/>      name               = string<br/>      title              = string<br/>      description        = optional(string)<br/>      combining_function = optional(string, "AND")<br/>      conditions = list(object({<br/>        ip_subnetworks = optional(list(string))<br/>        members        = optional(list(string))<br/>        negate         = optional(bool, false)<br/>        regions        = optional(list(string))<br/>      }))<br/>    })), [])<br/>    ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>      })))<br/>    })), [])<br/>    egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>      })))<br/>    })), [])<br/>    enable_dry_run = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_vpn_advertised_ip_ranges"></a> [vpn\_advertised\_ip\_ranges](#input\_vpn\_advertised\_ip\_ranges) | IP ranges to advertise via BGP | <pre>list(object({<br/>    range       = string<br/>    description = string<br/>  }))</pre> | `[]` | no |
| <a name="input_vpn_local_ips"></a> [vpn\_local\_ips](#input\_vpn\_local\_ips) | Local IP addresses for VPN interfaces | `list(string)` | <pre>[<br/>  "169.254.0.1",<br/>  "169.254.0.3"<br/>]</pre> | no |
| <a name="input_vpn_peer_asn"></a> [vpn\_peer\_asn](#input\_vpn\_peer\_asn) | Peer router BGP ASN | `number` | `64513` | no |
| <a name="input_vpn_peer_gateway_ip"></a> [vpn\_peer\_gateway\_ip](#input\_vpn\_peer\_gateway\_ip) | External IP of the peer VPN gateway | `string` | `""` | no |
| <a name="input_vpn_peer_ips"></a> [vpn\_peer\_ips](#input\_vpn\_peer\_ips) | Peer IP addresses for BGP sessions | `list(string)` | <pre>[<br/>  "169.254.0.2",<br/>  "169.254.0.4"<br/>]</pre> | no |
| <a name="input_vpn_router_asn"></a> [vpn\_router\_asn](#input\_vpn\_router\_asn) | Cloud Router BGP ASN | `number` | `64512` | no |
| <a name="input_vpn_shared_secret"></a> [vpn\_shared\_secret](#input\_vpn\_shared\_secret) | VPN shared secret (consider using Secret Manager) | `string` | `""` | no |
| <a name="input_vpn_tunnel_count"></a> [vpn\_tunnel\_count](#input\_vpn\_tunnel\_count) | Number of VPN tunnels (1 or 2 for HA) | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_additional_firewall_rule_ids"></a> [additional\_firewall\_rule\_ids](#output\_additional\_firewall\_rule\_ids) | The IDs of all additional firewall rules |
| <a name="output_additional_firewall_rules"></a> [additional\_firewall\_rules](#output\_additional\_firewall\_rules) | All additional firewall rule outputs |
| <a name="output_api_gateway"></a> [api\_gateway](#output\_api\_gateway) | The API Gateway module outputs (if enabled) |
| <a name="output_api_gateway_hostname"></a> [api\_gateway\_hostname](#output\_api\_gateway\_hostname) | The default hostname of the API Gateway |
| <a name="output_api_gateway_neg_id"></a> [api\_gateway\_neg\_id](#output\_api\_gateway\_neg\_id) | The serverless NEG ID for load balancer integration |
| <a name="output_cdn"></a> [cdn](#output\_cdn) | The CDN module outputs (if enabled) |
| <a name="output_cdn_backend_service_id"></a> [cdn\_backend\_service\_id](#output\_cdn\_backend\_service\_id) | The CDN backend service ID |
| <a name="output_cdn_ip"></a> [cdn\_ip](#output\_cdn\_ip) | The global load balancer IP address |
| <a name="output_cloud_armor"></a> [cloud\_armor](#output\_cloud\_armor) | The Cloud Armor security policy (if enabled) |
| <a name="output_dns_name_servers"></a> [dns\_name\_servers](#output\_dns\_name\_servers) | Name servers for each public DNS zone |
| <a name="output_dns_zones"></a> [dns\_zones](#output\_dns\_zones) | All DNS zone outputs |
| <a name="output_hierarchical_firewall_policies"></a> [hierarchical\_firewall\_policies](#output\_hierarchical\_firewall\_policies) | All hierarchical firewall policy outputs |
| <a name="output_hierarchical_firewall_policy_ids"></a> [hierarchical\_firewall\_policy\_ids](#output\_hierarchical\_firewall\_policy\_ids) | The IDs of all hierarchical firewall policies |
| <a name="output_interconnect_pairing_keys"></a> [interconnect\_pairing\_keys](#output\_interconnect\_pairing\_keys) | Pairing keys for partner interconnects (share with provider) |
| <a name="output_interconnect_states"></a> [interconnect\_states](#output\_interconnect\_states) | The state of each interconnect attachment |
| <a name="output_interconnects"></a> [interconnects](#output\_interconnects) | All Cloud Interconnect attachment outputs |
| <a name="output_internal_load_balancer_backend_services"></a> [internal\_load\_balancer\_backend\_services](#output\_internal\_load\_balancer\_backend\_services) | The backend service self\_links for all internal load balancers |
| <a name="output_internal_load_balancer_ips"></a> [internal\_load\_balancer\_ips](#output\_internal\_load\_balancer\_ips) | The IP addresses of all internal load balancers |
| <a name="output_internal_load_balancers"></a> [internal\_load\_balancers](#output\_internal\_load\_balancers) | All internal load balancer outputs |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | The NAT gateway IP addresses |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The VPC network ID |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The VPC network name |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The VPC network self link |
| <a name="output_network_tags"></a> [network\_tags](#output\_network\_tags) | Network tags for tiered security |
| <a name="output_packet_mirroring_policies"></a> [packet\_mirroring\_policies](#output\_packet\_mirroring\_policies) | All packet mirroring policy outputs |
| <a name="output_packet_mirroring_policy_ids"></a> [packet\_mirroring\_policy\_ids](#output\_packet\_mirroring\_policy\_ids) | The IDs of all packet mirroring policies |
| <a name="output_peering_states"></a> [peering\_states](#output\_peering\_states) | The state of each VPC peering connection |
| <a name="output_security_policy_id"></a> [security\_policy\_id](#output\_security\_policy\_id) | The Cloud Armor security policy ID |
| <a name="output_security_policy_self_link"></a> [security\_policy\_self\_link](#output\_security\_policy\_self\_link) | The Cloud Armor security policy self link |
| <a name="output_shared_vpc_service_project_ids"></a> [shared\_vpc\_service\_project\_ids](#output\_shared\_vpc\_service\_project\_ids) | The IDs of all Shared VPC service project attachments |
| <a name="output_shared_vpc_service_projects"></a> [shared\_vpc\_service\_projects](#output\_shared\_vpc\_service\_projects) | All Shared VPC service project attachment outputs |
| <a name="output_standalone_nat_gateways"></a> [standalone\_nat\_gateways](#output\_standalone\_nat\_gateways) | All standalone NAT gateway outputs |
| <a name="output_standalone_nat_ips"></a> [standalone\_nat\_ips](#output\_standalone\_nat\_ips) | The NAT IP addresses for each standalone NAT gateway |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | All subnet outputs organized by tier |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | The VPC module outputs (if enabled) |
| <a name="output_vpc_flow_logs"></a> [vpc\_flow\_logs](#output\_vpc\_flow\_logs) | The VPC Flow Logs export module outputs (if enabled) |
| <a name="output_vpc_flow_logs_sink_id"></a> [vpc\_flow\_logs\_sink\_id](#output\_vpc\_flow\_logs\_sink\_id) | The ID of the VPC Flow Logs sink |
| <a name="output_vpc_flow_logs_writer_identity"></a> [vpc\_flow\_logs\_writer\_identity](#output\_vpc\_flow\_logs\_writer\_identity) | The service account identity for the flow logs sink writer |
| <a name="output_vpc_peerings"></a> [vpc\_peerings](#output\_vpc\_peerings) | All VPC peering outputs |
| <a name="output_vpc_service_control_perimeter_names"></a> [vpc\_service\_control\_perimeter\_names](#output\_vpc\_service\_control\_perimeter\_names) | The names of all VPC Service Controls perimeters |
| <a name="output_vpc_service_controls"></a> [vpc\_service\_controls](#output\_vpc\_service\_controls) | All VPC Service Controls perimeter outputs |
| <a name="output_vpn"></a> [vpn](#output\_vpn) | The VPN module outputs (if enabled) |
| <a name="output_vpn_gateway_ips"></a> [vpn\_gateway\_ips](#output\_vpn\_gateway\_ips) | The VPN gateway external IP addresses |
| <a name="output_vpn_tunnel_statuses"></a> [vpn\_tunnel\_statuses](#output\_vpn\_tunnel\_statuses) | The status of each VPN tunnel |

## Security Considerations

- Ensure all sensitive variables are marked as `sensitive = true`
- Use GCP Secret Manager for storing secrets
- Follow the principle of least privilege for IAM roles
- Enable audit logging for compliance

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

This module is licensed under the MIT License. See [LICENSE](../../LICENSE) for details.
<!-- END_TF_DOCS -->