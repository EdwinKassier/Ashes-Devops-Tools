/**
 * Copyright 2023 Ashes
 *
 * Subnet Module - Main Configuration
 */

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.ip_cidr_range
  region        = var.region
  network       = var.network
  project       = var.project_id

  private_ip_google_access = var.private_ip_google_access
  purpose                  = var.purpose
  role                     = var.role

  # Flow logs configuration
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = var.log_config_aggregation_interval
      flow_sampling        = var.log_config_flow_sampling
      metadata             = var.log_config_metadata
    }
  }

  # Secondary IP ranges (for GKE, etc.)
  dynamic "secondary_ip_range" {
    for_each = var.secondary_ip_ranges
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }
}
