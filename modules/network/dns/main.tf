/**
 * Copyright 2023 Ashes
 *
 * Cloud DNS Module - Main Configuration
 */

locals {
  is_private_zone = var.visibility == "private"
  managed_zone    = local.is_private_zone ? google_dns_managed_zone.private_zone[0] : google_dns_managed_zone.public_zone[0]
}

resource "google_dns_managed_zone" "private_zone" {
  count = local.is_private_zone ? 1 : 0

  project     = var.project_id
  name        = var.zone_name
  dns_name    = var.dns_name
  description = var.description
  labels      = var.labels
  visibility  = "private"

  dynamic "private_visibility_config" {
    for_each = [1]
    content {
      dynamic "networks" {
        for_each = var.private_visibility_networks
        content {
          network_url = networks.value
        }
      }
    }
  }

  dynamic "peering_config" {
    for_each = var.peering_network != "" ? [1] : []
    content {
      target_network {
        network_url = var.peering_network
      }
    }
  }

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

  dynamic "cloud_logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable_logging = true
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_dns_managed_zone" "public_zone" {
  count = local.is_private_zone ? 0 : 1

  project     = var.project_id
  name        = var.zone_name
  dns_name    = var.dns_name
  description = var.description
  labels      = var.labels
  visibility  = "public"

  dnssec_config {
    state = var.dnssec_enabled ? "on" : "transfer"
  }

  dynamic "cloud_logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable_logging = true
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# DNS Records
resource "google_dns_record_set" "records" {
  for_each = { for r in var.records : "${r.name}-${r.type}" => r }

  project      = var.project_id
  managed_zone = local.managed_zone.name
  name         = each.value.name
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}
