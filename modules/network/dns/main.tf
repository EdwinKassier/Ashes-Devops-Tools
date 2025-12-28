/**
 * Copyright 2023 Ashes
 *
 * Cloud DNS Module - Main Configuration
 */

# DNS Managed Zone
resource "google_dns_managed_zone" "zone" {
  project     = var.project_id
  name        = var.zone_name
  dns_name    = var.dns_name
  description = var.description
  labels      = var.labels

  visibility = var.visibility

  # Private zone configuration
  dynamic "private_visibility_config" {
    for_each = var.visibility == "private" ? [1] : []
    content {
      dynamic "networks" {
        for_each = var.private_visibility_networks
        content {
          network_url = networks.value
        }
      }
    }
  }

  # DNSSEC configuration (public zones only)
  dynamic "dnssec_config" {
    for_each = var.visibility == "public" && var.dnssec_enabled ? [1] : []
    content {
      state = "on"
    }
  }

  # Forwarding configuration
  dynamic "forwarding_config" {
    for_each = length(var.forwarding_targets) > 0 ? [1] : []
    content {
      dynamic "target_name_servers" {
        for_each = var.forwarding_targets
        content {
          ipv4_address = target_name_servers.value
        }
      }
    }
  }

  # Cloud logging
  dynamic "cloud_logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable_logging = true
    }
  }

  lifecycle {
    prevent_destroy = false # Set to true for production usage
  }
}

# DNS Records
resource "google_dns_record_set" "records" {
  for_each = { for r in var.records : "${r.name}-${r.type}" => r }

  project      = var.project_id
  managed_zone = google_dns_managed_zone.zone.name
  name         = each.value.name
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}
