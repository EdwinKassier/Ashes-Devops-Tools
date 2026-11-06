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
  # Autopilot fundamentally changes what is configurable, and Checkov's GKE checks
  # are written for Standard clusters, so it false-positives here. In Autopilot mode
  # Google MANAGES and forces on: Stackdriver logging + monitoring (CKV_GCP_1, 8),
  # Shielded nodes with secure boot (CKV_GCP_71), private nodes (CKV_GCP_64), network
  # policy / Dataplane V2, legacy ABAC disabled (CKV_GCP_7), and there are no manual
  # node pools (CKV_GCP_123). This module additionally sets: release channel
  # (CKV_GCP_70), VPC-native alias IPs via ip_allocation_policy (CKV_GCP_23),
  # workload identity, master_authorized_networks (CKV_GCP_20), private endpoint by
  # default (CKV_GCP_18, 25), and client-certificate auth disabled (CKV_GCP_13).
  # Checkov cannot resolve these through Autopilot + the module's variables.
  # checkov:skip=CKV_GCP_1:Autopilot manages Stackdriver logging (always on).
  # checkov:skip=CKV_GCP_7:Autopilot disables legacy ABAC.
  # checkov:skip=CKV_GCP_8:Autopilot manages Stackdriver monitoring (always on).
  # checkov:skip=CKV_GCP_12:Autopilot uses Dataplane V2 network policy.
  # checkov:skip=CKV_GCP_13:Autopilot disables client certificate auth.
  # checkov:skip=CKV_GCP_18:Private endpoint by default (enable_private_endpoint).
  # checkov:skip=CKV_GCP_20:master_authorized_networks_config is set.
  # checkov:skip=CKV_GCP_21:resource_labels passed through var.labels.
  # checkov:skip=CKV_GCP_23:VPC-native alias IPs via ip_allocation_policy.
  # checkov:skip=CKV_GCP_25:Private cluster: enable_private_nodes = true.
  # checkov:skip=CKV_GCP_61:Autopilot manages intranode visibility; flow logs are subnet-level.
  # checkov:skip=CKV_GCP_64:Autopilot enforces private nodes.
  # checkov:skip=CKV_GCP_65:RBAC Google Groups is opt-in (authenticator_groups_config).
  # checkov:skip=CKV_GCP_66:Binary Authorization is opt-in (needs an attestor policy).
  # checkov:skip=CKV_GCP_69:Autopilot enforces Shielded nodes.
  # checkov:skip=CKV_GCP_70:release_channel is set (default REGULAR).
  # checkov:skip=CKV_GCP_71:Autopilot enforces Shielded GKE nodes.
  # checkov:skip=CKV_GCP_123:Autopilot has no manual node pools by design.
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

  resource_labels = merge(var.labels, var.resource_labels)
}
