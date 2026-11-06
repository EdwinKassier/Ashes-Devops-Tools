/**
 * Copyright 2023 Ashes
 *
 * dns-anchor - private DNS anchor network composition
 *
 * A workload-free VPC whose only job is to anchor the organization's private
 * Cloud DNS zones; spokes reach the zones through DNS peering. It composes the
 * network/tiered-vpc core (VPC, zonal subnets, baseline deny-by-default
 * firewall), the private zones bound to that VPC, and optional VPC peerings.
 *
 * There is deliberately no Cloud NAT, Cloud Armor, Private Service Connect or
 * Private Service Access: nothing in the anchor VPC egresses or calls Google
 * APIs, so those billable resources would be pure cost (FinOps F4).
 *
 * Replaces the DNS-hub use of the deprecated stages/host module (see the
 * README migration table for the moved blocks).
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

module "network" {
  source = "../../network/tiered-vpc"

  project_id          = var.project_id
  name                = var.network.name
  region              = var.region
  cidr_block          = var.network.cidr_block
  zones               = local.zones
  subnet_cidrs        = var.network.subnet_cidrs
  shared_vpc_host     = false
  deletion_protection = var.deletion_protection
  flow_logs           = var.network.flow_logs
  firewall            = var.firewall
}

# Private zones, always bound to the anchor VPC (plus any extra networks) with
# query logging on.
module "dns_zones" {
  source   = "../../network/dns"
  for_each = var.dns_zones

  project_id     = var.project_id
  zone_name      = each.key
  dns_name       = each.value.dns_name
  description    = coalesce(each.value.description, "Private DNS zone for ${each.key}")
  visibility     = "private"
  dnssec_enabled = each.value.dnssec_enabled
  enable_logging = true
  labels         = var.labels
  records        = each.value.records

  private_visibility_networks = concat([module.network.network_self_link], each.value.additional_visibility_networks)
}

module "vpc_peering" {
  source   = "../../network/vpc-peering"
  for_each = var.peerings

  peering_name           = each.key
  network                = module.network.network_self_link
  peer_network           = each.value.peer_network
  create_reverse_peering = each.value.create_reverse_peering
  export_custom_routes   = each.value.export_custom_routes
  import_custom_routes   = each.value.import_custom_routes
}
