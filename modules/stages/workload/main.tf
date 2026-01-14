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
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 14.0"

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

# Grant "Service Project Admin" roles to the specified group
resource "google_project_iam_binding" "project_admins" {
  for_each = toset(var.project_admin_roles)

  project = module.project.project_id
  role    = each.value

  members = [
    "group:${var.project_admin_group_email}"
  ]
}

# Network User binding on specific subnets in the Host Project
# This allows the service project to use the subnets without owning them
resource "google_compute_subnetwork_iam_binding" "network_users" {
  for_each = var.enable_shared_vpc_attachment ? var.shared_vpc_subnets : []

  project    = var.shared_vpc_host_project_id
  region     = each.value.region
  subnetwork = each.value.subnet_name
  role       = "roles/compute.networkUser"

  members = [
    "serviceAccount:${module.project.service_account_email}",
    "group:${var.project_admin_group_email}",
    "serviceAccount:${module.project.project_number}@cloudservices.gserviceaccount.com",
    "serviceAccount:service-${module.project.project_number}@container-engine-robot.iam.gserviceaccount.com"
  ]

  depends_on = [google_compute_shared_vpc_service_project.attachment]
}
