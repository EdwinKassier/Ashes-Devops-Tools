/**
 * Copyright 2023 Ashes
 *
 * Cloud NAT Module - Main Configuration
 * 
 * Creates a Cloud NAT gateway with configurable NAT IP allocation,
 * subnetwork targeting, and logging options.
 */

# Cloud Router (if not provided)
resource "google_compute_router" "router" {
  count = var.create_router ? 1 : 0

  project = var.project_id
  name    = var.router_name
  network = var.network
  region  = var.region

  dynamic "bgp" {
    for_each = var.router_asn != null ? [1] : []
    content {
      asn = var.router_asn
    }
  }
}

locals {
  router_name = var.create_router ? google_compute_router.router[0].name : var.router_name
}

# Cloud NAT Gateway
resource "google_compute_router_nat" "nat" {
  project = var.project_id
  name    = var.name
  router  = local.router_name
  region  = var.region

  # NAT IP allocation mode
  nat_ip_allocate_option = var.nat_ip_allocate_option

  # Manual NAT IPs (when using MANUAL_ONLY)
  nat_ips = var.nat_ip_allocate_option == "MANUAL_ONLY" ? var.nat_ips : null

  # Source subnetwork IP ranges configuration
  source_subnetwork_ip_ranges_to_nat = var.source_subnetwork_ip_ranges_to_nat

  # Subnetwork configuration (when using LIST_OF_SUBNETWORKS)
  dynamic "subnetwork" {
    for_each = var.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS" ? var.subnetworks : []
    content {
      name                     = subnetwork.value.name
      source_ip_ranges_to_nat  = subnetwork.value.source_ip_ranges_to_nat
      secondary_ip_range_names = try(subnetwork.value.secondary_ip_range_names, null)
    }
  }

  # Timeouts
  min_ports_per_vm                    = var.min_ports_per_vm
  max_ports_per_vm                    = var.max_ports_per_vm
  enable_dynamic_port_allocation      = var.enable_dynamic_port_allocation
  udp_idle_timeout_sec                = var.udp_idle_timeout_sec
  icmp_idle_timeout_sec               = var.icmp_idle_timeout_sec
  tcp_established_idle_timeout_sec    = var.tcp_established_idle_timeout_sec
  tcp_transitory_idle_timeout_sec     = var.tcp_transitory_idle_timeout_sec
  tcp_time_wait_timeout_sec           = var.tcp_time_wait_timeout_sec
  enable_endpoint_independent_mapping = var.enable_endpoint_independent_mapping

  # Logging configuration
  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable = true
      filter = var.log_filter
    }
  }
}
