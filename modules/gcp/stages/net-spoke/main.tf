/**
 * Copyright 2023 Ashes
 *
 * net-spoke - per-environment spoke network composition
 *
 * The Shared VPC host network of one application environment: a three-tier
 * VPC (network/tiered-vpc) plus Cloud NAT, Private Service Access, Private
 * Service Connect, hub connectivity (VPC peering, or an opt-in Network
 * Connectivity Center spoke), private or peering DNS zones, an opt-in Cloud
 * Armor edge policy, opt-in VPC flow-log export, Shared VPC service-project
 * attachments and the environment VPC-SC perimeter.
 *
 * Opt-in additional_regions add regional subnets (and a Cloud Router and NAT
 * per region) to the same VPC; empty keeps the single-region layout.
 *
 * Replaces the spoke use of the deprecated stages/host module. Module and
 * resource names deliberately match stages/host so a caller that keeps its
 * module label only needs `moved` blocks for the network core (see the
 * README migration table).
 */

locals {
  # Explicit zones win; otherwise fall back to the zones GCP returns.
  zones = length(var.network.explicit_zones) > 0 ? var.network.explicit_zones : data.google_compute_zones.available.names
}

# Auto-discover available zones (used only when network.explicit_zones is empty).
data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region

  lifecycle {
    postcondition {
      condition     = length(self.names) > 0
      error_message = "No compute zones returned for region '${var.region}' in project '${var.project_id}'. Verify the region is valid and the Compute Engine API is enabled."
    }
  }
}

# =============================================================================
# NETWORK CORE (VPC, three-tier subnets, baseline firewall)
# =============================================================================

module "network" {
  source = "../../network/tiered-vpc"

  project_id          = var.project_id
  name                = var.network.name
  region              = var.region
  cidr_block          = var.network.cidr_block
  zones               = local.zones
  subnet_cidrs        = var.network.subnet_cidrs
  secondary_ranges    = var.network.secondary_ranges
  shared_vpc_host     = var.network.shared_vpc_host
  deletion_protection = var.deletion_protection
  flow_logs           = var.network.flow_logs
  additional_regions  = var.additional_regions

  firewall_mode                     = var.firewall_mode
  firewall_policy_enforcement_order = var.firewall_policy_enforcement_order

  firewall = {
    enable_logging     = var.firewall.enable_logging
    enable_iap_access  = var.firewall.enable_iap_access
    compute_tier_ports = var.firewall.compute_tier_ports
    database_ports     = var.firewall.database_ports

    api_gateway_source_ranges               = var.firewall.api_gateway_source_ranges
    database_egress_target_service_accounts = var.firewall.database_egress_target_service_accounts
  }
}

module "additional_firewall_rules" {
  source   = "../../network/network-firewall"
  for_each = var.firewall.additional_rules

  project_id         = var.project_id
  firewall_rule_name = each.key
  network            = module.network.network_name
  direction          = each.value.direction
  description        = each.value.description
  priority           = each.value.priority
  allow_rules        = each.value.allow_rules
  deny_rules         = each.value.deny_rules
  source_ranges      = each.value.source_ranges
  target_tags        = each.value.target_tags
  source_tags        = each.value.source_tags
  enable_logging     = var.firewall.enable_logging
}

# =============================================================================
# EGRESS AND PRIVATE SERVICES (NAT, PSA, PSC)
# =============================================================================

# Cloud NAT for the private and database tiers only (public tier excluded).
module "integrated_nat" {
  source = "../../network/nat"
  count  = var.nat.enabled ? 1 : 0

  project_id = var.project_id
  name       = "${var.network.name}-nat"
  region     = var.region
  network    = module.network.network_id

  create_router = true
  router_name   = "${var.network.name}-router"

  nat_ip_allocate_option             = var.nat.ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = concat(
    [for s in module.network.subnets.private : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }],
    [for s in module.network.subnets.database : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }]
  )

  enable_logging = true
  log_filter     = var.nat.log_filter
}

# One Cloud Router and Cloud NAT per additional region with nat = true, same
# settings as the primary. Separate block keyed by region: the primary
# integrated_nat[0] address is unchanged.
module "additional_region_nat" {
  source   = "../../network/nat"
  for_each = var.nat.enabled ? { for region, r in var.additional_regions : region => r if r.nat } : {}

  project_id = var.project_id
  name       = "${var.network.name}-nat-${each.key}"
  region     = each.key
  network    = module.network.network_id

  create_router = true
  router_name   = "${var.network.name}-router-${each.key}"

  nat_ip_allocate_option             = var.nat.ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = [
    { name = module.network.additional_region_subnets[each.key].private.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] },
    { name = module.network.additional_region_subnets[each.key].database.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] },
  ]

  enable_logging = true
  log_filter     = var.nat.log_filter
}

module "private_service_access" {
  source = "../../network/private-service-access"
  count  = var.private_service_access.enabled ? 1 : 0

  project_id    = var.project_id
  vpc_network   = module.network.network_id
  name          = var.private_service_access.name
  prefix_length = var.private_service_access.prefix_length
}

module "private_service_connect" {
  source = "../../network/private-service-connect"
  count  = var.private_service_connect.enabled ? 1 : 0

  project_id = var.project_id
  name       = "${var.network.name}-psc"
  network    = module.network.network_id
  target     = var.private_service_connect.target
}

# =============================================================================
# HUB CONNECTIVITY AND DNS
# =============================================================================

# connectivity = "peering" (default): one VPC peering per var.peerings entry.
# connectivity = "ncc": no peerings; the VPC joins the hub as an NCC spoke
# instead (NCC rejects a VPC spoke that is still peered with a hub VPC).
# The for_each keys, and so the state addresses, are unchanged in peering mode.
module "vpc_peering" {
  source   = "../../network/vpc-peering"
  for_each = var.connectivity == "peering" ? var.peerings : {}

  peering_name           = each.key
  network                = module.network.network_self_link
  peer_network           = each.value.peer_network
  create_reverse_peering = each.value.create_reverse_peering
  export_custom_routes   = each.value.export_custom_routes
  import_custom_routes   = each.value.import_custom_routes
}

# NCC spoke for this VPC (edge group of a STAR hub by default), plus a producer
# VPC spoke for the Private Service Access peering so the hub learns the PSA
# range. depends_on orders the spoke after the peering deletion when an
# existing spoke switches from peering to ncc in one apply.
module "ncc_spoke" {
  source = "../../network/ncc-spoke"
  count  = var.connectivity == "ncc" ? 1 : 0

  project_id  = var.project_id
  name        = var.network.name
  description = "NCC spoke for ${var.network.name}"
  labels      = var.labels
  hub_id      = var.ncc.hub_id
  group       = var.ncc.group

  linked_vpc_network = {
    uri                   = module.network.network_self_link
    include_export_ranges = var.ncc.include_export_ranges
    exclude_export_ranges = var.ncc.exclude_export_ranges
  }

  producer_vpc_networks = var.private_service_access.enabled && var.ncc.export_private_service_access ? {
    psa = {
      network = module.network.network_name
      peering = module.private_service_access[0].peering.peering
    }
  } : {}

  depends_on = [module.vpc_peering]
}

module "dns" {
  source   = "../../network/dns"
  for_each = var.dns_zones

  project_id = var.project_id
  zone_name  = each.key
  dns_name   = each.value.dns_name
  # Optional attributes arrive as null; null-coalesce explicitly.
  description     = try(coalesce(each.value.description, "Managed DNS zone for ${each.key}"), "Managed DNS zone for ${each.key}")
  visibility      = each.value.visibility
  dnssec_enabled  = try(coalesce(each.value.dnssec_enabled, false), false)
  peering_network = each.value.peering_network == null ? "" : each.value.peering_network
  enable_logging  = true
  labels          = var.labels

  private_visibility_networks = each.value.visibility == "private" ? [module.network.network_self_link] : []

  records = each.value.records == null ? [] : each.value.records
}

# =============================================================================
# EDGE (Cloud Armor WAF policy, opt-in)
# =============================================================================

module "cloud_armor" {
  source = "../../network/cloud-armor"
  count  = var.edge.cloud_armor.enabled ? 1 : 0

  project_id                 = var.project_id
  policy_name                = "${var.project_prefix}-security-policy"
  description                = "WAF security policy for ${var.project_prefix}"
  enable_owasp_rules         = var.edge.cloud_armor.owasp_rules
  enable_adaptive_protection = var.edge.cloud_armor.adaptive_protection
  enable_log4j_protection    = var.edge.cloud_armor.log4j_protection
  owasp_sensitivity          = var.edge.cloud_armor.owasp_sensitivity
  custom_rules               = var.edge.cloud_armor.custom_rules
}

# =============================================================================
# OBSERVABILITY (VPC flow-log export, CMEK-encrypted)
# =============================================================================

data "google_project" "current" {
  count = var.flow_logs_export.enabled ? 1 : 0

  project_id = var.project_id
}

module "flow_logs_kms" {
  source = "../../governance/kms"
  count  = var.flow_logs_export.enabled ? 1 : 0

  project_id   = var.project_id
  keyring_name = "${var.project_prefix}-flow-logs"
  location     = var.region

  keys = {
    "vpc-flow-logs" = {
      encrypter_decrypters = [
        "serviceAccount:bq-${data.google_project.current[0].number}@bigquery-encryption.iam.gserviceaccount.com",
        "serviceAccount:service-${data.google_project.current[0].number}@gs-project-accounts.iam.gserviceaccount.com",
      ]
    }
  }
}

module "vpc_flow_logs" {
  source = "../../network/vpc-flow-logs"
  count  = var.flow_logs_export.enabled ? 1 : 0

  project_id = var.project_id
  sink_name  = var.flow_logs_export.sink_name
  # An explicit destination wins; otherwise derive it from the dataset this
  # module creates.
  destination = (
    var.flow_logs_export.destination != "" ? var.flow_logs_export.destination :
    var.flow_logs_export.create_bigquery_dataset ? "bigquery.googleapis.com/projects/${var.project_id}/datasets/${var.flow_logs_export.bigquery_dataset_id}" :
    ""
  )

  create_bigquery_dataset            = var.flow_logs_export.create_bigquery_dataset
  bigquery_dataset_id                = var.flow_logs_export.bigquery_dataset_id
  bigquery_location                  = var.flow_logs_export.bigquery_location
  bigquery_partition_expiration_days = var.flow_logs_export.retention_days
  bigquery_kms_key_name              = module.flow_logs_kms[0].key_names["vpc-flow-logs"]

  create_storage_bucket  = var.flow_logs_export.create_storage_bucket
  storage_bucket_name    = var.flow_logs_export.storage_bucket_name
  storage_location       = var.flow_logs_export.storage_location
  storage_retention_days = var.flow_logs_export.retention_days
  storage_kms_key_name   = module.flow_logs_kms[0].key_names["vpc-flow-logs"]

  labels = var.labels
}

# =============================================================================
# GOVERNANCE (Shared VPC service projects, VPC Service Controls)
# =============================================================================

module "shared_vpc_service_projects" {
  source   = "../../network/shared-vpc-service"
  for_each = var.network.shared_vpc_host ? var.shared_vpc_service_projects : {}

  host_project_id    = var.project_id
  service_project_id = each.key

  deletion_policy                   = each.value.deletion_policy
  subnet_iam_bindings               = each.value.subnet_iam_bindings
  grant_network_user_to_all_subnets = each.value.grant_network_user_to_all_subnets
  network_user_members              = each.value.network_user_members
  network_viewer_members            = each.value.network_viewer_members
  enable_gke_permissions            = each.value.enable_gke_permissions

  # The Shared VPC host must exist before service projects attach.
  depends_on = [module.network]
}

module "vpc_service_controls" {
  source   = "../../network/vpc-sc"
  for_each = var.vpc_service_controls

  organization_id            = each.value.organization_id
  access_policy_name         = each.value.access_policy_name
  create_access_policy       = each.value.create_access_policy
  perimeter_name             = each.key
  perimeter_title            = each.value.perimeter_title
  description                = each.value.description
  perimeter_type             = each.value.perimeter_type
  protected_projects         = each.value.protected_projects
  restricted_services        = each.value.restricted_services
  access_levels              = each.value.access_levels
  ingress_policies           = each.value.ingress_policies
  egress_policies            = each.value.egress_policies
  enable_dry_run             = each.value.enable_dry_run
  enable_deletion_protection = each.value.enable_deletion_protection

  dry_run_restricted_services = each.value.dry_run_restricted_services
  dry_run_ingress_policies    = each.value.dry_run_ingress_policies
  dry_run_egress_policies     = each.value.dry_run_egress_policies
}
