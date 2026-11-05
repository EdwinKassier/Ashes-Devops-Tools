/**
 * Copyright 2023 Ashes
 *
 * GKE Autopilot Module - Main Configuration
 *
 * Creates a private, Autopilot-mode Google Kubernetes Engine cluster attached to
 * a Shared VPC. Secure by default: private nodes, a private control-plane endpoint,
 * Workload Identity always on, deletion protection, and a Gateway API controller.
 * Every hardening control is a toggle so platform admins can compose the posture
 * they need without forking the module.
 */

locals {
  # Workload Identity pool is always "<project>.svc.id.goog" for Autopilot clusters.
  # Computed here (not read back from the resource) so it is deterministic at plan time.
  workload_pool = "${var.project_id}.svc.id.goog"
}

# Deletion protection guard — present only when enable_deletion_protection = true.
# Terraform's prevent_destroy must be a static literal; it cannot reference a variable.
# This guard carries prevent_destroy = true and is created conditionally so that
# removing it (by toggling the flag) is also blocked, forcing an explicit state rm.
resource "terraform_data" "deletion_protection_guard" {
  count = var.enable_deletion_protection ? 1 : 0

  input = var.name

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_container_cluster" "this" {
  provider = google

  name     = var.name
  project  = var.project_id
  location = var.location

  enable_autopilot    = true
  deletion_protection = var.enable_deletion_protection

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native (alias IP) addressing from the Shared VPC secondary ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  release_channel {
    channel = var.release_channel
  }

  # Private by default: nodes never get public IPs; the control-plane endpoint is
  # private unless an admin explicitly opts into a public (but still authorized) one.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity is always on — the only secure way to grant pods GCP access.
  workload_identity_config {
    workload_pool = local.workload_pool
  }

  # Gateway API (standard channel) as the supported ingress/routing control plane.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  resource_labels = var.resource_labels
}
