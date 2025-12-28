# Google Cloud Service Account Module
# Creates a service account with configurable IAM roles and impersonation settings
# Best Practice: Avoid creating keys - use Workload Identity Federation instead

resource "google_service_account" "service_account" {
  account_id   = var.account_id
  display_name = var.display_name
  project      = var.project_id
  description  = var.description
}

# Grant IAM roles to the service account at project level
resource "google_project_iam_member" "sa_project_roles" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

# Grant IAM roles to the service account at folder level
resource "google_folder_iam_member" "sa_folder_roles" {
  for_each = { for item in var.folder_roles : "${item.folder_id}-${item.role}" => item }

  folder = each.value.folder_id
  role   = each.value.role
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# Grant IAM roles to the service account at organization level
resource "google_organization_iam_member" "sa_org_roles" {
  for_each = { for item in var.organization_roles : "${item.org_id}-${item.role}" => item }

  org_id = each.value.org_id
  role   = each.value.role
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# Allow specified members to impersonate this service account
# This is preferred over creating service account keys
resource "google_service_account_iam_member" "impersonation" {
  for_each = toset(var.impersonation_members)

  service_account_id = google_service_account.service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# Allow specified members to use the service account for Workload Identity
resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = toset(var.workload_identity_members)

  service_account_id = google_service_account.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value
}
