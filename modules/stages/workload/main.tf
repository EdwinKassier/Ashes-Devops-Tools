/**
 * Copyright 2023 Ashes
 *
 * Workload Factory Module
 * 
 * This module implements the "Project Factory" pattern for service projects.
 * It standardizes the creation of workload projects, enabling APIs,
 * and attaching them to the Shared VPC Host.
 */

# =============================================================================
# PROJECT CREATION
# =============================================================================

module "project" {
  # checkov:skip=CKV_TF_1:Uses the upstream Terraform Google Project Factory module pinned by release version.
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.2"

  name              = var.project_name
  random_project_id = true
  org_id            = var.org_id
  folder_id         = var.folder_id
  billing_account   = var.billing_account

  activate_apis = concat([
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com"
  ], var.activate_apis)

  labels = var.labels
}

# =============================================================================
# SHARED VPC ATTACHMENT
# =============================================================================

resource "google_compute_shared_vpc_service_project" "attachment" {
  count = var.enable_shared_vpc_attachment ? 1 : 0

  host_project    = var.shared_vpc_host_project_id
  service_project = module.project.project_id
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
#   1. Default compute SA of the service project
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
    { for k, s in var.shared_vpc_subnets : "${k}/default-sa" => { subnet = s, member = "serviceAccount:${module.project.service_account_email}" } },
    { for k, s in var.shared_vpc_subnets : "${k}/admin-group" => { subnet = s, member = "group:${var.project_admin_group_email}" } },
    { for k, s in var.shared_vpc_subnets : "${k}/cloud-services" => { subnet = s, member = "serviceAccount:${module.project.project_number}@cloudservices.gserviceaccount.com" } },
    # GKE robot SA — conditional on enable_gke_network_user flag
    var.enable_gke_network_user ? {
      for k, s in var.shared_vpc_subnets : "${k}/gke-robot" => {
        subnet = s
        member = "serviceAccount:service-${module.project.project_number}@container-engine-robot.iam.gserviceaccount.com"
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

  depends_on = [google_compute_shared_vpc_service_project.attachment]
}
