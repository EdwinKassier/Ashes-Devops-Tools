/**
 * Copyright 2023 Ashes
 *
 * Shared VPC Service Project Module - Main Configuration
 * 
 * Attaches a service project to a Shared VPC host project and optionally
 * grants subnet-level IAM permissions to service accounts.
 */

# -----------------------------------------------------------------------------
# SERVICE PROJECT ATTACHMENT
# -----------------------------------------------------------------------------

resource "google_compute_shared_vpc_service_project" "service_project" {
  host_project    = var.host_project_id
  service_project = var.service_project_id

  deletion_policy = var.deletion_policy
}

# -----------------------------------------------------------------------------
# SUBNET-LEVEL IAM (for specific subnet access)
# -----------------------------------------------------------------------------

# Grant compute.networkUser role on specific subnets
resource "google_compute_subnetwork_iam_member" "subnet_users" {
  for_each = { for binding in var.subnet_iam_bindings : "${binding.subnet}-${binding.member}" => binding }

  project    = var.host_project_id
  region     = each.value.region
  subnetwork = each.value.subnet
  role       = "roles/compute.networkUser"
  member     = each.value.member
}

# -----------------------------------------------------------------------------
# PROJECT-LEVEL IAM (for all subnets access)
# -----------------------------------------------------------------------------

# Grant compute.networkUser role at project level (access to all subnets)
resource "google_project_iam_member" "network_users" {
  for_each = var.grant_network_user_to_all_subnets ? toset(var.network_user_members) : []

  project = var.host_project_id
  role    = "roles/compute.networkUser"
  member  = each.value
}

# Grant compute.networkViewer role (read-only network access)
resource "google_project_iam_member" "network_viewers" {
  for_each = toset(var.network_viewer_members)

  project = var.host_project_id
  role    = "roles/compute.networkViewer"
  member  = each.value
}

# -----------------------------------------------------------------------------
# HOST PROJECT SERVICE AGENT PERMISSIONS
# -----------------------------------------------------------------------------

# Grant GKE service account permissions on host project (for GKE clusters)
resource "google_project_iam_member" "gke_host_service_agent" {
  count = var.enable_gke_permissions ? 1 : 0

  project = var.host_project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:service-${data.google_project.service_project.number}@container-engine-robot.iam.gserviceaccount.com"

  depends_on = [google_compute_shared_vpc_service_project.service_project]
}

# Data source to get service project number
data "google_project" "service_project" {
  project_id = var.service_project_id
}
