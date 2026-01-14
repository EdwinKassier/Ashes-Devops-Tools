/**
 * Copyright 2023 Ashes
 *
 * Host Module - Unified Infrastructure Orchestration
 * 
 * This module serves as the central entrypoint for project provisioning,
 * instantiating all network, security, and governance modules.
 */

# =============================================================================
# CORE NETWORKING
# =============================================================================

locals {
  # Network tags for tiered security
  network_tags = {
    api_gateway = "api-gateway"
    public      = "public"
    compute     = "compute"
    database    = "database"
  }

  # Dynamic CIDR calculation: Use provided CIDR or fallback to consistent hash of VPC Name
  # Using VPC Name is safer for standalone usage than Region, as multiple VPCs can exist in one region.
  name_hash      = abs(tonumber(format("%d", parseint(substr(md5(var.vpc_name), 0, 4), 16)))) % 256
  vpc_cidr_block = var.vpc_cidr_block != null ? var.vpc_cidr_block : "10.${local.name_hash}.0.0/16"

  # Calculate subnets dynamically
  public_cidrs   = length(var.subnet_cidrs.public) > 0 ? var.subnet_cidrs.public : [for i, z in local.zones : cidrsubnet(local.vpc_cidr_block, 8, i)]
  private_cidrs  = length(var.subnet_cidrs.private) > 0 ? var.subnet_cidrs.private : [for i, z in local.zones : cidrsubnet(local.vpc_cidr_block, 8, 16 + i)]
  database_cidrs = length(var.subnet_cidrs.database) > 0 ? var.subnet_cidrs.database : [for i, z in local.zones : cidrsubnet(local.vpc_cidr_block, 8, 32 + i)]

  # Auto-derive zones
  zones = data.google_compute_zones.available.names
}

# Auto-discover available zones
data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region
}

module "vpc" {
  source = "../network/vpc"
  count  = var.enable_networking ? 1 : 0

  project_id = var.project_id
  vpc_name   = var.vpc_name

  # Enterprise features
  enable_shared_vpc_host          = var.enable_shared_vpc_host
  delete_default_routes_on_create = true
}

# -----------------------------------------------------------------------------
# SUBNETS (Three-Tier Architecture)
# -----------------------------------------------------------------------------

# Public subnets
module "public_subnets" {
  source   = "../network/subnet"
  for_each = var.enable_networking ? { for i, z in local.zones : z => i } : {}

  project_id    = var.project_id
  subnet_name   = "${var.vpc_name}-public-${each.key}"
  ip_cidr_range = local.public_cidrs[each.value]
  region        = var.region
  network       = module.vpc[0].id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.log_config_aggregation_interval
  log_config_flow_sampling        = var.log_config_flow_sampling
}

# Private subnets (compute tier)
module "private_subnets" {
  source   = "../network/subnet"
  for_each = var.enable_networking ? { for i, z in local.zones : z => i } : {}

  project_id    = var.project_id
  subnet_name   = "${var.vpc_name}-private-${each.key}"
  ip_cidr_range = local.private_cidrs[each.value]
  region        = var.region
  network       = module.vpc[0].id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.log_config_aggregation_interval
  log_config_flow_sampling        = var.log_config_flow_sampling

  # Architecture: Enable Private Google Access for internal VMs
  private_ip_google_access = true

  # GKE Readiness: Pass secondary ranges if defined for this zone
  secondary_ip_ranges = try(var.secondary_ranges[each.key], [])
}

# Database subnets
module "database_subnets" {
  source   = "../network/subnet"
  for_each = var.enable_networking ? { for i, z in local.zones : z => i } : {}

  project_id    = var.project_id
  subnet_name   = "${var.vpc_name}-db-${each.key}"
  ip_cidr_range = local.database_cidrs[each.value]
  region        = var.region
  network       = module.vpc[0].id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.log_config_aggregation_interval
  log_config_flow_sampling        = var.log_config_flow_sampling

  # Architecture: Enable Private Google Access for secure data operations
  private_ip_google_access = true
}

# -----------------------------------------------------------------------------
# CORE SERVICES (NAT, PSA, PSC)
# -----------------------------------------------------------------------------

# Integrated NAT Gateway (for private/db subnets)
# Note: We use the standalone_nat module structure but integrated here for the 3-tier default
module "integrated_nat" {
  source = "../network/nat"
  count  = var.enable_networking ? 1 : 0

  project_id = var.project_id
  name       = "${var.vpc_name}-nat"
  region     = var.region
  network    = module.vpc[0].id

  create_router = true
  router_name   = "${var.vpc_name}-router"

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = concat(
    [for s in module.private_subnets : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }],
    [for s in module.database_subnets : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }]
  )

  enable_logging = true
  log_filter     = "ERRORS_ONLY"
}

# Private Service Access (for Cloud SQL, Redis, etc.)
module "private_service_access" {
  source = "../network/private-service-access"
  count  = var.enable_networking && var.enable_private_service_access ? 1 : 0

  project_id    = var.project_id
  vpc_network   = module.vpc[0].id
  name          = var.psa_name
  prefix_length = var.psa_prefix_length
}

# Private Service Connect (for Google APIs)
module "private_service_connect" {
  source = "../network/private-service-connect"
  count  = var.enable_networking && var.enable_private_service_connect ? 1 : 0

  project_id = var.project_id
  name       = "${var.vpc_name}-psc"
  network    = module.vpc[0].id
  target     = var.psc_target
}

# =============================================================================
# TIERED SECURITY FIREWALL RULES (Three-Tier Architecture)
# =============================================================================

# Allow API Gateway to Public tier
module "firewall_apigateway_to_public" {
  source = "../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-apigw-public"
  network            = module.vpc[0].name
  description        = "Allow traffic from API Gateway to public tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["443", "80"]
    }
  ]

  source_tags    = [local.network_tags.api_gateway]
  target_tags    = [local.network_tags.public]
  enable_logging = var.enable_firewall_logging
}

# Allow Public tier to Compute tier
module "firewall_public_to_compute" {
  source = "../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-public-compute"
  network            = module.vpc[0].name
  description        = "Allow traffic from public tier to compute tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = var.compute_tier_ports
    }
  ]

  source_tags    = [local.network_tags.public]
  target_tags    = [local.network_tags.compute]
  enable_logging = var.enable_firewall_logging
}

# Allow Compute tier to Database tier
module "firewall_compute_to_database" {
  source = "../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-compute-db"
  network            = module.vpc[0].name
  description        = "Allow traffic from compute tier to database tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = var.database_ports
    }
  ]

  source_tags    = [local.network_tags.compute]
  target_tags    = [local.network_tags.database]
  enable_logging = var.enable_firewall_logging
}

# =============================================================================
# UTILITY FIREWALL RULES
# =============================================================================

# Allow IAP access for secure SSH/RDP
module "firewall_iap_ssh_rdp" {
  source = "../network/network-firewall"
  count  = var.enable_networking && var.enable_iap_access ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-iap-ssh-rdp"
  network            = module.vpc[0].name
  description        = "Allow SSH and RDP from Identity-Aware Proxy VIP"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["22", "3389"]
    }
  ]

  source_ranges  = ["35.235.240.0/20"]
  enable_logging = var.enable_firewall_logging
}

# Allow GCP Health Checks (required for Load Balancers)
module "firewall_health_checks" {
  source = "../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-health-checks"
  network            = module.vpc[0].name
  description        = "Allow GCP health check probes for Load Balancers"

  allow_rules = [
    {
      protocol = "tcp"
    }
  ]

  source_ranges  = ["35.191.0.0/16", "130.211.0.0/22"]
  enable_logging = var.enable_firewall_logging
}

# Deny direct egress from database tier (defense in depth)
module "firewall_database_deny_egress" {
  source = "../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-deny-db-egress"
  network            = module.vpc[0].name
  description        = "Deny direct egress from database tier for security"
  priority           = 65534
  direction          = "EGRESS"

  deny_rules = [
    {
      protocol = "all"
    }
  ]

  target_tags    = [local.network_tags.database]
  enable_logging = var.enable_firewall_logging
}

# Deny all other ingress traffic (Logging / Catch-all)
module "firewall_deny_all" {
  source = "../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-deny-all-ingress"
  network            = module.vpc[0].name
  description        = "Deny all ingress traffic (lowest priority) and log it"
  priority           = 65535
  direction          = "INGRESS"

  deny_rules = [
    {
      protocol = "all"
    }
  ]

  source_ranges  = ["0.0.0.0/0"]
  enable_logging = var.enable_firewall_logging
}

# =============================================================================
# EDGE SECURITY (Cloud Armor WAF)
# =============================================================================

module "cloud_armor" {
  source = "../network/cloud_armor"
  count  = var.enable_cloud_armor ? 1 : 0

  project_id                 = var.project_id
  policy_name                = "${var.project_prefix}-security-policy"
  description                = "WAF security policy for ${var.project_prefix}"
  enable_owasp_rules         = var.enable_owasp_rules
  enable_adaptive_protection = var.enable_adaptive_protection
  owasp_sensitivity          = var.owasp_sensitivity
  custom_rules               = var.cloud_armor_custom_rules
}

# =============================================================================
# CONTENT DELIVERY (CDN + Global Load Balancer)
# =============================================================================

module "cdn" {
  source = "../network/cdn"
  count  = var.enable_cdn ? 1 : 0

  project_id           = var.project_id
  lb_name              = "${var.project_prefix}-cdn"
  domains              = var.cdn_domains
  enable_cdn           = true
  enable_http_redirect = var.cdn_enable_http_redirect
  security_policy      = var.enable_cloud_armor ? module.cloud_armor[0].policy_self_link : null
  backend_groups       = var.cdn_backend_groups
  cdn_policy           = var.cdn_policy
}

# =============================================================================
# DNS MANAGEMENT
# =============================================================================

module "dns" {
  source   = "../network/dns"
  for_each = var.dns_zones

  project_id      = var.project_id
  zone_name       = each.key
  dns_name        = each.value.dns_name
  description     = try(each.value.description, "Managed DNS zone for ${each.key}")
  visibility      = each.value.visibility
  dnssec_enabled  = try(each.value.dnssec_enabled, false)
  peering_network = try(each.value.peering_network, "")
  enable_logging  = true
  labels          = var.labels

  private_visibility_networks = each.value.visibility == "private" ? [
    var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  ] : []

  records = try(each.value.records, [])
}

# =============================================================================
# HYBRID CONNECTIVITY (VPN)
# =============================================================================

module "vpn" {
  source = "../network/vpn"
  count  = var.enable_vpn ? 1 : 0

  project_id               = var.project_id
  name                     = "${var.project_prefix}-vpn"
  region                   = var.region
  network                  = var.enable_networking ? module.vpc[0].id : var.existing_network_id
  tunnel_count             = var.vpn_tunnel_count
  router_asn               = var.vpn_router_asn
  peer_asn                 = var.vpn_peer_asn
  peer_external_gateway_ip = var.vpn_peer_gateway_ip
  shared_secret            = var.vpn_shared_secret
  local_ip_addresses       = var.vpn_local_ips
  peer_ip_addresses        = var.vpn_peer_ips
  advertised_ip_ranges     = var.vpn_advertised_ip_ranges
  labels                   = var.labels
}

# =============================================================================
# VPC PEERING (Hub-and-Spoke)
# =============================================================================

module "vpc_peering" {
  source   = "../network/vpc-peering"
  for_each = var.vpc_peerings

  project_id             = var.project_id
  peering_name           = each.key
  network                = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  peer_network           = each.value.peer_network
  create_reverse_peering = try(each.value.create_reverse_peering, true)
  export_custom_routes   = try(each.value.export_custom_routes, false)
  import_custom_routes   = try(each.value.import_custom_routes, false)
}

# =============================================================================
# API GATEWAY
# =============================================================================

module "api_gateway" {
  source = "../network/api_gateway"
  count  = var.enable_api_gateway ? 1 : 0

  project_id            = var.project_id
  region                = var.region
  api_id                = "${var.project_prefix}-api"
  display_name          = var.api_gateway_display_name
  gateway_id            = "${var.project_prefix}-gateway"
  gateway_display_name  = "${var.api_gateway_display_name} Gateway"
  service_account_email = var.api_gateway_service_account
  managed_service_ids   = var.api_gateway_managed_services
  openapi_spec          = var.api_gateway_openapi_spec
  labels                = var.labels
}

# =============================================================================
# ADDITIONAL FIREWALL RULES (Standalone)
# =============================================================================

module "additional_firewall_rules" {
  source   = "../network/network-firewall"
  for_each = var.additional_firewall_rules

  project_id         = var.project_id
  firewall_rule_name = each.key
  network            = var.enable_networking ? module.vpc[0].name : var.existing_network_name
  direction          = each.value.direction
  description        = each.value.description
  priority           = each.value.priority
  allow_rules        = try(each.value.allow_rules, [])
  deny_rules         = try(each.value.deny_rules, [])
  source_ranges      = try(each.value.source_ranges, null)
  target_tags        = try(each.value.target_tags, null)
  source_tags        = try(each.value.source_tags, null)
  enable_logging     = var.enable_firewall_logging
}

# =============================================================================
# STANDALONE NAT GATEWAY (when not using VPC-integrated NAT)
# =============================================================================

module "standalone_nat" {
  source   = "../network/nat"
  for_each = var.standalone_nat_gateways

  project_id = var.project_id
  name       = each.key
  region     = each.value.region
  network    = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link

  create_router                      = try(each.value.create_router, true)
  router_name                        = try(each.value.router_name, "${each.key}-router")
  nat_ip_allocate_option             = try(each.value.nat_ip_allocate_option, "AUTO_ONLY")
  nat_ips                            = try(each.value.nat_ips, [])
  source_subnetwork_ip_ranges_to_nat = try(each.value.source_subnetwork_ip_ranges_to_nat, "ALL_SUBNETWORKS_ALL_IP_RANGES")
  subnetworks                        = try(each.value.subnetworks, [])
  min_ports_per_vm                   = try(each.value.min_ports_per_vm, 64)
  enable_dynamic_port_allocation     = try(each.value.enable_dynamic_port_allocation, false)
  enable_logging                     = try(each.value.enable_logging, true)
  log_filter                         = try(each.value.log_filter, "ERRORS_ONLY")
}

# =============================================================================
# VPC FLOW LOGS EXPORT
# =============================================================================

module "vpc_flow_logs" {
  source = "../network/vpc-flow-logs"
  count  = var.enable_vpc_flow_logs_export ? 1 : 0

  project_id  = var.project_id
  sink_name   = var.vpc_flow_logs_sink_name
  destination = var.vpc_flow_logs_destination

  create_bigquery_dataset            = var.vpc_flow_logs_create_bigquery_dataset
  bigquery_dataset_id                = var.vpc_flow_logs_bigquery_dataset_id
  bigquery_location                  = var.vpc_flow_logs_bigquery_location
  bigquery_partition_expiration_days = var.vpc_flow_logs_retention_days

  create_storage_bucket  = var.vpc_flow_logs_create_storage_bucket
  storage_bucket_name    = var.vpc_flow_logs_storage_bucket_name
  storage_location       = var.vpc_flow_logs_storage_location
  storage_retention_days = var.vpc_flow_logs_retention_days

  labels = var.labels
}

# =============================================================================
# SHARED VPC SERVICE PROJECT ATTACHMENTS
# =============================================================================

module "shared_vpc_service_projects" {
  source   = "../network/shared-vpc-service"
  for_each = var.enable_shared_vpc_host ? var.shared_vpc_service_projects : {}

  host_project_id    = var.project_id
  service_project_id = each.key

  deletion_policy                   = try(each.value.deletion_policy, "ABANDON")
  subnet_iam_bindings               = try(each.value.subnet_iam_bindings, [])
  grant_network_user_to_all_subnets = try(each.value.grant_network_user_to_all_subnets, false)
  network_user_members              = try(each.value.network_user_members, [])
  network_viewer_members            = try(each.value.network_viewer_members, [])
  enable_gke_permissions            = try(each.value.enable_gke_permissions, false)

  # Ensure Shared VPC Host is configured before attaching service projects
  depends_on = [module.vpc]
}

# =============================================================================
# HIERARCHICAL FIREWALL POLICIES
# =============================================================================

module "hierarchical_firewall_policies" {
  source   = "../network/hierarchical-firewall"
  for_each = var.hierarchical_firewall_policies

  parent         = each.value.parent
  policy_name    = each.key
  description    = try(each.value.description, "Managed by Terraform")
  rules          = try(each.value.rules, [])
  associations   = try(each.value.associations, [])
  enable_logging = try(each.value.enable_logging, true)
}

# =============================================================================
# VPC SERVICE CONTROLS
# =============================================================================

module "vpc_service_controls" {
  source   = "../network/vpc-sc"
  for_each = var.vpc_service_controls

  organization_id      = each.value.organization_id
  access_policy_name   = try(each.value.access_policy_name, null)
  create_access_policy = try(each.value.create_access_policy, false)
  perimeter_name       = each.key
  perimeter_title      = each.value.perimeter_title
  description          = try(each.value.description, "Managed by Terraform")
  perimeter_type       = try(each.value.perimeter_type, "PERIMETER_TYPE_REGULAR")
  protected_projects   = try(each.value.protected_projects, [])
  restricted_services  = try(each.value.restricted_services, [])
  access_levels        = try(each.value.access_levels, [])
  ingress_policies     = try(each.value.ingress_policies, [])
  egress_policies      = try(each.value.egress_policies, [])
  enable_dry_run       = try(each.value.enable_dry_run, false)
}

# =============================================================================
# CLOUD INTERCONNECT
# =============================================================================

module "interconnects" {
  source   = "../network/interconnect"
  for_each = var.interconnects

  project_id      = var.project_id
  region          = each.value.region
  network         = var.enable_networking ? module.vpc[0].network_self_link : var.existing_network_self_link
  attachment_name = each.key

  interconnect_type = try(each.value.interconnect_type, "PARTNER")
  router_name       = each.value.router_name
  router_asn        = try(each.value.router_asn, 64512)
  create_router     = try(each.value.create_router, true)

  # Dedicated interconnect
  interconnect_self_link = try(each.value.interconnect_self_link, null)
  vlan_tag               = try(each.value.vlan_tag, null)
  bandwidth              = try(each.value.bandwidth, "BPS_10G")

  # Partner interconnect
  edge_availability_domain = try(each.value.edge_availability_domain, "AVAILABILITY_DOMAIN_1")

  # Common settings
  mtu           = try(each.value.mtu, 1440)
  admin_enabled = try(each.value.admin_enabled, true)
  encryption    = try(each.value.encryption, "NONE")

  # BGP
  create_bgp_peer      = try(each.value.create_bgp_peer, true)
  interface_ip_range   = try(each.value.interface_ip_range, null)
  peer_ip_address      = try(each.value.peer_ip_address, null)
  peer_asn             = try(each.value.peer_asn, 65000)
  enable_bfd           = try(each.value.enable_bfd, false)
  advertised_ip_ranges = try(each.value.advertised_ip_ranges, [])
}

# =============================================================================
# PACKET MIRRORING
# =============================================================================

module "packet_mirroring" {
  source   = "../network/packet-mirroring"
  for_each = var.packet_mirroring_policies

  project_id = var.project_id
  name       = each.key
  region     = each.value.region
  network    = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link

  collector_ilb_url    = each.value.collector_ilb_url
  mirrored_instances   = try(each.value.mirrored_instances, [])
  mirrored_subnetworks = try(each.value.mirrored_subnetworks, [])
  mirrored_tags        = try(each.value.mirrored_tags, [])
  filter_ip_protocols  = try(each.value.filter_ip_protocols, [])
  filter_cidr_ranges   = try(each.value.filter_cidr_ranges, [])
  filter_direction     = try(each.value.filter_direction, "BOTH")
  priority             = try(each.value.priority, 1000)
  enable               = try(each.value.enable, true)
}

# =============================================================================
# INTERNAL LOAD BALANCERS
# =============================================================================

module "internal_load_balancers" {
  source   = "../network/internal-lb"
  for_each = var.internal_load_balancers

  project_id = var.project_id
  name       = each.key
  region     = each.value.region
  network    = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  subnet     = each.value.subnet

  is_l7      = try(each.value.is_l7, true)
  port_range = try(each.value.port_range, "80")
  backends   = each.value.backends

  # Health check
  health_check_type         = try(each.value.health_check_type, "HTTP")
  health_check_port         = try(each.value.health_check_port, 80)
  health_check_request_path = try(each.value.health_check_request_path, "/health")

  # Optional settings
  allow_global_access = try(each.value.allow_global_access, false)
  enable_ssl          = try(each.value.enable_ssl, false)
  ssl_certificates    = try(each.value.ssl_certificates, [])
  session_affinity    = try(each.value.session_affinity, "NONE")
  enable_logging      = try(each.value.enable_logging, true)

  # Firewall
  create_firewall_rule     = try(each.value.create_firewall_rule, true)
  proxy_only_subnet_ranges = try(each.value.proxy_only_subnet_ranges, [])
  backend_target_tags      = try(each.value.backend_target_tags, [])
  backend_port             = try(each.value.backend_port, 80)

  labels = try(each.value.labels, {})
}


