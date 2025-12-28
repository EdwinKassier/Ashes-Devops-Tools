/**
 * Copyright 2023 Ashes
 *
 * Host Module - Variables
 */

# =============================================================================
# CORE PROJECT CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "project_prefix" {
  description = "Prefix for naming resources (e.g., 'ashes-dev')"
  type        = string
}

variable "region" {
  description = "The primary GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "enable_networking" {
  description = "Enable VPC and network infrastructure provisioning"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "main-vpc"
}

variable "existing_network_id" {
  description = "ID of existing network (when enable_networking is false)"
  type        = string
  default     = ""
}

variable "existing_network_self_link" {
  description = "Self link of existing network (when enable_networking is false)"
  type        = string
  default     = ""
}

variable "database_ports" {
  description = "Database ports to allow from compute to database tier"
  type        = list(string)
  default     = ["3306", "5432", "6379"]
}

variable "enable_iap_access" {
  description = "Enable IAP SSH/RDP access"
  type        = bool
  default     = true
}

variable "enable_private_service_access" {
  description = "Enable Private Service Access for Cloud SQL, Redis, etc."
  type        = bool
  default     = true
}

variable "psa_name" {
  description = "Name of the Private Service Access allocation"
  type        = string
  default     = "google-managed-services"
}

variable "enable_private_service_connect" {
  description = "Enable Private Service Connect for Google APIs"
  type        = bool
  default     = true
}

variable "psa_prefix_length" {
  description = "Prefix length for Private Service Access (e.g. 16 for /16)"
  type        = number
  default     = 16
}

variable "psc_target" {
  description = "Target for Private Service Connect (e.g. 'all-apis' or 'vpc-sc')"
  type        = string
  default     = "all-apis"
}

variable "enable_shared_vpc_host" {
  description = "Enable this project as a Shared VPC Host"
  type        = bool
  default     = false
}

variable "enable_firewall_logging" {
  description = "Enable logging for all firewall rules"
  type        = bool
  default     = true
}

variable "compute_tier_ports" {
  description = "Ports allowed from public to compute tier"
  type        = list(string)
  default     = ["8080", "8443", "3000"]
}

variable "enable_deletion_protection" {
  description = "Enable lifecycle prevent_destroy for critical resources"
  type        = bool
  default     = false
}

variable "log_config_aggregation_interval" {
  description = "Flow logs aggregation interval"
  type        = string
  default     = "INTERVAL_5_SEC"
}

variable "log_config_flow_sampling" {
  description = "Flow logs sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.5
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs for public, private, and database tiers"
  type = object({
    public   = list(string)
    private  = list(string)
    database = list(string)
  })
  default = {
    public   = []
    private  = []
    database = []
  }
}

# =============================================================================
# CLOUD ARMOR (WAF) CONFIGURATION
# =============================================================================

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor WAF security policy"
  type        = bool
  default     = true
}

variable "enable_owasp_rules" {
  description = "Enable OWASP Top 10 WAF rules"
  type        = bool
  default     = true
}

variable "enable_adaptive_protection" {
  description = "Enable Cloud Armor adaptive protection (DDoS)"
  type        = bool
  default     = true
}

variable "owasp_sensitivity" {
  description = "OWASP rule sensitivity (1-4, lower is more strict)"
  type        = number
  default     = 2
}

variable "cloud_armor_custom_rules" {
  description = "Custom Cloud Armor rules (map of rule name to rule config)"
  type = map(object({
    action      = string
    priority    = number
    description = optional(string)
    match_conditions = object({
      versioned_expr = string
      config = object({
        src_ip_ranges = list(string)
      })
    })
    rate_limit_options = optional(object({
      threshold_count     = number
      interval_sec        = number
      conform_action      = optional(string)
      exceed_action       = optional(string)
      enforce_on_key      = optional(string)
      enforce_on_key_type = optional(string)
    }))
  }))
  default = {}
}

# =============================================================================
# CDN CONFIGURATION
# =============================================================================

variable "enable_cdn" {
  description = "Enable Cloud CDN with Global Load Balancer"
  type        = bool
  default     = false
}

variable "cdn_domains" {
  description = "Domains for managed SSL certificate"
  type        = list(string)
  default     = []
}

variable "cdn_enable_http_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

variable "cdn_backend_groups" {
  description = "Backend groups for the CDN load balancer"
  type = list(object({
    group           = string
    balancing_mode  = optional(string)
    capacity_scaler = optional(number)
    description     = optional(string)
  }))
  default = []
}

variable "cdn_policy" {
  description = "CDN caching policy configuration"
  type = object({
    cache_mode                   = optional(string, "CACHE_ALL_STATIC")
    client_ttl                   = optional(number, 3600)
    default_ttl                  = optional(number, 3600)
    max_ttl                      = optional(number, 86400)
    negative_caching             = optional(bool, true)
    signed_url_cache_max_age_sec = optional(number, 0)
  })
  default = {}
}

# =============================================================================
# DNS CONFIGURATION
# =============================================================================

variable "dns_zones" {
  description = "Map of DNS zones to create"
  type = map(object({
    dns_name       = string
    visibility     = string
    description    = optional(string)
    dnssec_enabled = optional(bool, false)
    records = optional(list(object({
      name    = string
      type    = string
      ttl     = number
      rrdatas = list(string)
    })), [])
  }))
  default = {}
}

# =============================================================================
# VPN CONFIGURATION
# =============================================================================

variable "enable_vpn" {
  description = "Enable Cloud VPN for hybrid connectivity"
  type        = bool
  default     = false
}

variable "vpn_tunnel_count" {
  description = "Number of VPN tunnels (1 or 2 for HA)"
  type        = number
  default     = 2
}

variable "vpn_router_asn" {
  description = "Cloud Router BGP ASN"
  type        = number
  default     = 64512
}

variable "vpn_peer_asn" {
  description = "Peer router BGP ASN"
  type        = number
  default     = 64513
}

variable "vpn_peer_gateway_ip" {
  description = "External IP of the peer VPN gateway"
  type        = string
  default     = ""
}

variable "vpn_shared_secret" {
  description = "VPN shared secret (consider using Secret Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpn_local_ips" {
  description = "Local IP addresses for VPN interfaces"
  type        = list(string)
  default     = ["169.254.0.1", "169.254.0.3"]
}

variable "vpn_peer_ips" {
  description = "Peer IP addresses for BGP sessions"
  type        = list(string)
  default     = ["169.254.0.2", "169.254.0.4"]
}

variable "vpn_advertised_ip_ranges" {
  description = "IP ranges to advertise via BGP"
  type = list(object({
    range       = string
    description = string
  }))
  default = []
}

# =============================================================================
# VPC PEERING CONFIGURATION
# =============================================================================

variable "vpc_peerings" {
  description = "Map of VPC peering configurations"
  type = map(object({
    peer_network           = string
    create_reverse_peering = optional(bool, true)
    export_custom_routes   = optional(bool, false)
    import_custom_routes   = optional(bool, false)
  }))
  default = {}
}

# =============================================================================
# API GATEWAY CONFIGURATION
# =============================================================================

variable "enable_api_gateway" {
  description = "Enable API Gateway"
  type        = bool
  default     = false
}

variable "api_gateway_display_name" {
  description = "Display name for the API Gateway"
  type        = string
  default     = "API Gateway"
}

variable "api_gateway_service_account" {
  description = "Service account email for API Gateway backend"
  type        = string
  default     = ""
}

variable "api_gateway_managed_services" {
  description = "Map of managed service IDs for auto-generated OpenAPI spec"
  type        = map(string)
  default     = {}
}

variable "api_gateway_openapi_spec" {
  description = "Custom OpenAPI specification (if not using managed_service_ids)"
  type        = string
  default     = ""
}

# =============================================================================
# ADDITIONAL FIREWALL RULES CONFIGURATION
# =============================================================================

variable "existing_network_name" {
  description = "Name of existing network (when enable_networking is false)"
  type        = string
  default     = ""
}

variable "additional_firewall_rules" {
  description = "Map of additional firewall rules to create outside of the VPC module"
  type = map(object({
    direction   = optional(string, "INGRESS")
    description = optional(string)
    priority    = optional(number, 1000)
    allow_rules = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
    deny_rules = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
    source_ranges = optional(list(string))
    target_tags   = optional(list(string))
    source_tags   = optional(list(string))
  }))
  default = {}
}

# =============================================================================
# STANDALONE NAT GATEWAY CONFIGURATION
# =============================================================================

variable "standalone_nat_gateways" {
  description = "Map of standalone NAT gateways to create (for multi-region or custom NAT configurations)"
  type = map(object({
    region                             = string
    create_router                      = optional(bool, true)
    router_name                        = optional(string)
    nat_ip_allocate_option             = optional(string, "AUTO_ONLY")
    nat_ips                            = optional(list(string), [])
    source_subnetwork_ip_ranges_to_nat = optional(string, "ALL_SUBNETWORKS_ALL_IP_RANGES")
    subnetworks = optional(list(object({
      name                     = string
      source_ip_ranges_to_nat  = list(string)
      secondary_ip_range_names = optional(list(string))
    })), [])
    min_ports_per_vm               = optional(number, 64)
    enable_dynamic_port_allocation = optional(bool, false)
    enable_logging                 = optional(bool, true)
    log_filter                     = optional(string, "ERRORS_ONLY")
  }))
  default = {}
}

# =============================================================================
# VPC FLOW LOGS EXPORT CONFIGURATION
# =============================================================================

variable "enable_vpc_flow_logs_export" {
  description = "Enable VPC Flow Logs export to BigQuery or Cloud Storage"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_sink_name" {
  description = "Name of the VPC Flow Logs sink"
  type        = string
  default     = "vpc-flow-logs-sink"
}

variable "vpc_flow_logs_destination" {
  description = "Destination for VPC Flow Logs (e.g., bigquery.googleapis.com/projects/PROJECT/datasets/DATASET)"
  type        = string
  default     = ""
}

variable "vpc_flow_logs_create_bigquery_dataset" {
  description = "Whether to create a BigQuery dataset for flow logs"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_bigquery_dataset_id" {
  description = "BigQuery dataset ID for flow logs"
  type        = string
  default     = "vpc_flow_logs"
}

variable "vpc_flow_logs_bigquery_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
}

variable "vpc_flow_logs_create_storage_bucket" {
  description = "Whether to create a Cloud Storage bucket for flow logs"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_storage_bucket_name" {
  description = "Cloud Storage bucket name for flow logs"
  type        = string
  default     = ""
}

variable "vpc_flow_logs_storage_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "vpc_flow_logs_retention_days" {
  description = "Days to retain flow logs data"
  type        = number
  default     = 90
}

# =============================================================================
# SHARED VPC SERVICE PROJECT CONFIGURATION
# =============================================================================

variable "shared_vpc_service_projects" {
  description = "Map of service projects to attach to this host project (requires enable_shared_vpc_host = true)"
  type = map(object({
    deletion_policy = optional(string, "ABANDON")
    subnet_iam_bindings = optional(list(object({
      subnet = string
      region = string
      member = string
    })), [])
    grant_network_user_to_all_subnets = optional(bool, false)
    network_user_members              = optional(list(string), [])
    network_viewer_members            = optional(list(string), [])
    enable_gke_permissions            = optional(bool, false)
  }))
  default = {}
}

# =============================================================================
# HIERARCHICAL FIREWALL POLICY CONFIGURATION
# =============================================================================

variable "hierarchical_firewall_policies" {
  description = "Map of hierarchical firewall policies to create at org/folder level"
  type = map(object({
    parent      = string
    description = optional(string, "Managed by Terraform")
    rules = optional(list(object({
      priority       = number
      action         = string
      direction      = string
      description    = optional(string)
      disabled       = optional(bool, false)
      enable_logging = optional(bool, false)
      layer4_configs = list(object({
        ip_protocol = string
        ports       = optional(list(string))
      }))
      src_ip_ranges           = optional(list(string))
      src_region_codes        = optional(list(string))
      dest_ip_ranges          = optional(list(string))
      dest_region_codes       = optional(list(string))
      target_networks         = optional(list(string))
      target_service_accounts = optional(list(string))
    })), [])
    associations   = optional(list(string), [])
    enable_logging = optional(bool, true)
  }))
  default = {}
}

# =============================================================================
# VPC SERVICE CONTROLS CONFIGURATION
# =============================================================================

variable "vpc_service_controls" {
  description = "Map of VPC Service Controls perimeters to create"
  type = map(object({
    organization_id      = string
    access_policy_name   = optional(string)
    create_access_policy = optional(bool, false)
    perimeter_title      = string
    description          = optional(string, "Managed by Terraform")
    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")
    protected_projects   = optional(list(string), [])
    restricted_services  = optional(list(string), [])
    access_levels = optional(list(object({
      name               = string
      title              = string
      description        = optional(string)
      combining_function = optional(string, "AND")
      conditions = list(object({
        ip_subnetworks = optional(list(string))
        members        = optional(list(string))
        negate         = optional(bool, false)
        regions        = optional(list(string))
      }))
    })), [])
    ingress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      resources     = optional(list(string))
      operations = optional(list(object({
        service_name = string
      })))
    })), [])
    egress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      resources     = optional(list(string))
      operations = optional(list(object({
        service_name = string
      })))
    })), [])
  }))
  default = {}
}

# =============================================================================
# INTERCONNECT CONFIGURATION
# =============================================================================

variable "interconnects" {
  description = "Map of Cloud Interconnect attachments to create"
  type = map(object({
    region            = string
    interconnect_type = optional(string, "PARTNER")
    router_name       = string
    router_asn        = optional(number, 64512)
    create_router     = optional(bool, true)

    # Dedicated interconnect settings
    interconnect_self_link = optional(string)
    vlan_tag               = optional(number)
    bandwidth              = optional(string, "BPS_10G")

    # Partner interconnect settings
    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")

    # Common settings
    mtu           = optional(number, 1440)
    admin_enabled = optional(bool, true)
    encryption    = optional(string, "NONE")

    # BGP settings
    create_bgp_peer    = optional(bool, true)
    interface_ip_range = optional(string)
    peer_ip_address    = optional(string)
    peer_asn           = optional(number, 65000)
    enable_bfd         = optional(bool, false)

    advertised_ip_ranges = optional(list(object({
      range       = string
      description = optional(string)
    })), [])
  }))
  default = {}
}

# =============================================================================
# PACKET MIRRORING CONFIGURATION
# =============================================================================

variable "packet_mirroring_policies" {
  description = "Map of packet mirroring policies to create"
  type = map(object({
    region               = string
    collector_ilb_url    = string
    mirrored_instances   = optional(list(string), [])
    mirrored_subnetworks = optional(list(string), [])
    mirrored_tags        = optional(list(string), [])
    filter_ip_protocols  = optional(list(string), [])
    filter_cidr_ranges   = optional(list(string), [])
    filter_direction     = optional(string, "BOTH")
    priority             = optional(number, 1000)
    enable               = optional(bool, true)
  }))
  default = {}
}

# =============================================================================
# INTERNAL LOAD BALANCER CONFIGURATION
# =============================================================================

variable "internal_load_balancers" {
  description = "Map of internal HTTP(S) load balancers to create"
  type = map(object({
    region     = string
    subnet     = string
    is_l7      = optional(bool, true)
    port_range = optional(string, "80")

    backends = list(object({
      group           = string
      balancing_mode  = optional(string, "UTILIZATION")
      capacity_scaler = optional(number, 1.0)
      max_utilization = optional(number, 0.8)
    }))

    # Health check
    health_check_type         = optional(string, "HTTP")
    health_check_port         = optional(number, 80)
    health_check_request_path = optional(string, "/health")

    # Optional settings
    allow_global_access = optional(bool, false)
    enable_ssl          = optional(bool, false)
    ssl_certificates    = optional(list(string), [])
    session_affinity    = optional(string, "NONE")
    enable_logging      = optional(bool, true)

    # Firewall
    create_firewall_rule     = optional(bool, true)
    proxy_only_subnet_ranges = optional(list(string), [])
    backend_target_tags      = optional(list(string), [])
    backend_port             = optional(number, 80)

    labels = optional(map(string), {})
  }))
  default = {}
}

