/**
 * Copyright 2023 Ashes
 *
 * Packet Mirroring Module - Main Configuration
 * 
 * Creates packet mirroring policies for network forensics, IDS/IPS,
 * and security analysis by cloning network traffic to collector instances.
 */

# -----------------------------------------------------------------------------
# PACKET MIRRORING POLICY
# -----------------------------------------------------------------------------

resource "google_compute_packet_mirroring" "mirroring" {
  project     = var.project_id
  name        = var.name
  region      = var.region
  description = var.description

  network {
    url = var.network
  }

  # Collector destination (internal load balancer)
  collector_ilb {
    url = var.collector_ilb_url
  }

  # Mirrored resources configuration
  mirrored_resources {
    # Mirror specific instances
    dynamic "instances" {
      for_each = var.mirrored_instances
      content {
        url = instances.value
      }
    }

    # Mirror by subnetworks
    dynamic "subnetworks" {
      for_each = var.mirrored_subnetworks
      content {
        url = subnetworks.value
      }
    }

    # Mirror by instance tags
    tags = var.mirrored_tags
  }

  # Filter configuration
  filter {
    ip_protocols = var.filter_ip_protocols
    cidr_ranges  = var.filter_cidr_ranges
    direction    = var.filter_direction
  }

  priority = var.priority
}
