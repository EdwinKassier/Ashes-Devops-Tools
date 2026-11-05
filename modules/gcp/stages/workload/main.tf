/**
 * Copyright 2023 Ashes
 *
 * Workload Factory Module
 *
 * This module implements the "Project Factory" pattern for service projects.
 * It standardizes the creation of workload projects, enabling APIs,
 * and attaching them to the Shared VPC Host.
 *
 * The project itself is created by the shared project primitive
 * (modules/gcp/project) — the same module stages/bootstrap and stages/projects
 * use — instead of the upstream terraform-google-modules/project-factory
 * (audit Modularity-H). The stage keeps only what the upstream factory did for
 * this caller: a random 4-hex project-ID suffix, a dedicated
 * "project-service-account", and disabling the default compute SA.
 * container.googleapis.com is no longer force-enabled: set enable_gke.
 */

# =============================================================================
# PROJECT CREATION
# =============================================================================

# 2-byte (4 hex) suffix — same length the upstream project-factory used, so the
# existing random_id state entry is moved (moved.tf) and project IDs are stable.
resource "random_id" "project_suffix" {
  byte_length = 2
}

locals {
  gke_enabled = var.enable_gke || var.enable_gke_network_user

  services = distinct(concat(
    [
      "compute.googleapis.com",
      "servicenetworking.googleapis.com",
    ],
    local.gke_enabled ? ["container.googleapis.com"] : [],
    var.activate_apis,
  ))
}

module "project" {
  source = "../../project"

  name            = var.project_name
  project_id      = "${var.project_name}-${random_id.project_suffix.hex}"
  parent          = var.folder_id != null ? "folders/${var.folder_id}" : "organizations/${var.org_id}"
  billing_account = var.billing_account
  labels          = var.labels
  deletion_policy = "PREVENT"

  services = local.services

  # SHARED VPC ATTACHMENT — attach as a service project of the env host.
  shared_vpc_host_project_id = var.enable_shared_vpc_attachment ? var.shared_vpc_host_project_id : null
}

# Dedicated project service account (upstream factory's create_project_sa).
# It is the identity granted compute.networkUser on the Shared VPC subnets.
resource "google_service_account" "project" {
  count = var.create_project_service_account ? 1 : 0

  project                      = module.project.project_id
  account_id                   = "project-service-account"
  display_name                 = "${var.project_name} Project Service Account"
  create_ignore_already_exists = true
}

# Default compute SA handling (upstream factory's default_service_account,
# which defaulted to "disable"). KEEP leaves it untouched.
resource "google_project_default_service_accounts" "this" {
  count = var.default_service_account_action == "KEEP" ? 0 : 1

  project        = module.project.project_id
  action         = var.default_service_account_action
  restore_policy = "REVERT_AND_IGNORE_FAILURE"
}

# =============================================================================
# IAM BINDINGS (Standardized Access)
# =============================================================================

# Grant "Service Project Admin" roles to the specified group.
# Uses google_project_iam_member (additive) rather than google_project_iam_binding
# (authoritative per role) so that bindings managed outside of Terraform are
# preserved on every apply. Authoritative bindings would silently evict any member
# not in this Terraform state on every plan+apply cycle.
resource "google_project_iam_member" "project_admins" {
  for_each = toset(var.project_admin_roles)

  project = module.project.project_id
  role    = each.value
  member  = "group:${var.project_admin_group_email}"
}

# Network User binding on specific subnets in the Host Project.
# Uses additive google_compute_subnetwork_iam_member for the same reason as above.
# The four standard members are:
#   1. The project service account (when create_project_service_account)
#   2. Admin group (so humans can schedule workloads)
#   3. Google Cloud Services robot SA (required for managed services)
#   4. GKE robot SA — only included when var.enable_gke_network_user = true,
#      since the GKE robot SA is created lazily when container.googleapis.com is
#      first enabled. Including it unconditionally on projects without GKE creates
#      a binding referencing a non-existent principal.

locals {
  # Build a flat map of (subnet_key, member) pairs for the additive bindings.
  subnet_members = var.enable_shared_vpc_attachment ? merge(
    # Always-present members
    var.create_project_service_account ? {
      for k, s in var.shared_vpc_subnets : "${k}/default-sa" => { subnet = s, member = "serviceAccount:${google_service_account.project[0].email}" }
    } : {},
    { for k, s in var.shared_vpc_subnets : "${k}/admin-group" => { subnet = s, member = "group:${var.project_admin_group_email}" } },
    { for k, s in var.shared_vpc_subnets : "${k}/cloud-services" => { subnet = s, member = "serviceAccount:${module.project.number}@cloudservices.gserviceaccount.com" } },
    # GKE robot SA — conditional on enable_gke_network_user flag
    var.enable_gke_network_user ? {
      for k, s in var.shared_vpc_subnets : "${k}/gke-robot" => {
        subnet = s
        member = "serviceAccount:service-${module.project.number}@container-engine-robot.iam.gserviceaccount.com"
      }
    } : {}
  ) : {}
}

resource "google_compute_subnetwork_iam_member" "network_users" {
  for_each = local.subnet_members

  project    = var.shared_vpc_host_project_id
  region     = each.value.subnet.region
  subnetwork = each.value.subnet.subnet_name
  role       = "roles/compute.networkUser"
  member     = each.value.member

  depends_on = [module.project]
}
