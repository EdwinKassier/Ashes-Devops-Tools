# Guard: fail fast when TFC OIDC is enabled but no workspaces are bound.
# Variable-level validation cannot cross-reference other variables, so a
# precondition on a terraform_data resource is used instead.
resource "terraform_data" "tfc_workspaces_guard" {
  count = var.enable_tfc_oidc && var.tfc_organization != null ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(var.tfc_workspaces) > 0
      error_message = "tfc_workspaces must not be empty when enable_tfc_oidc = true. Provide at least one workspace name."
    }
  }
}

# Admin Project - Foundation of the Automation
resource "google_project" "admin_project" {
  name                = "${var.project_prefix}-admin"
  project_id          = "${var.project_prefix}-admin-${random_id.suffix.hex}"
  org_id              = var.org_id
  billing_account     = var.billing_account
  auto_create_network = false
  labels = {
    environment = "admin"
    purpose     = "administration"
    managed-by  = "terraform"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# Enable essential APIs on the admin project
resource "google_project_service" "admin_project_services" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "securitycenter.googleapis.com",
    "cloudidentity.googleapis.com",
    "orgpolicy.googleapis.com",
    "accesscontextmanager.googleapis.com",
    "essentialcontacts.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudasset.googleapis.com",
    "compute.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "monitoring.googleapis.com",
  ])

  project = google_project.admin_project.project_id
  service = each.key

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Terraform Admin Service Account
module "terraform_admin_sa" {
  source = "../../iam/service_account"

  project_id   = google_project.admin_project.project_id
  account_id   = "terraform-admin"
  display_name = "Terraform Admin"
  description  = "Centralised Terraform Admin for managing downstream resources"

  # Allow the actual admin user to impersonate this SA
  impersonation_members = ["user:${var.admin_email}"]
}

# Workload Identity for GitHub Actions (or TFC in future)
module "gh_oidc" {
  source = "../../iam/workload_identity"

  project_id   = google_project.admin_project.project_id
  pool_id      = "github-pool"
  display_name = "GitHub Actions Pool"

  enable_github_provider = true
  github_organization    = var.github_org

  # Security: Restrict to main branch only for production deployments
  github_allowed_refs                 = ["refs/heads/main"]
  github_attribute_condition_override = "assertion.sub == 'repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main'"

  github_sa_bindings = [
    {
      repository            = "${var.github_org}/${var.github_repo}"
      service_account_email = module.terraform_admin_sa.email
    }
  ]
}

# Workload Identity for Terraform Cloud (Dynamic Credentials)
module "tfc_oidc" {
  source = "../../iam/workload_identity"
  count  = var.enable_tfc_oidc && var.tfc_organization != null ? 1 : 0

  project_id   = google_project.admin_project.project_id
  pool_id      = "tfc-pool"
  display_name = "Terraform Cloud Pool"

  enable_tfc_provider = true
  tfc_organization    = var.tfc_organization

  tfc_sa_bindings = [
    for ws in var.tfc_workspaces : {
      workspace_name        = ws
      service_account_email = module.terraform_admin_sa.email
    }
  ]
}

# Grant Org-Level Roles to the Terraform Admin SA
# Note: Folder roles are granted in the organization module where folders exist
resource "google_organization_iam_member" "terraform_admin_standard_org_roles" {
  for_each = toset([
    "roles/orgpolicy.policyAdmin",
    "roles/accesscontextmanager.policyAdmin",
    "roles/logging.admin",
    "roles/resourcemanager.organizationViewer",
    "roles/compute.xpnAdmin",
    "roles/resourcemanager.tagAdmin", # Tag management for governance
  ])

  org_id = var.org_id
  role   = each.key #tfsec:ignore:google-iam-no-privileged-service-accounts
  member = "serviceAccount:${module.terraform_admin_sa.email}"
}

resource "google_organization_iam_member" "terraform_admin_exception_org_roles" {
  # checkov:skip=CKV_GCP_45:Justified — roles are intentionally isolated in a dedicated resource block
  # with per-role commentary. See rationale below; these are the minimum org-level privileges the
  # bootstrap SA requires to automate the full landing zone lifecycle.
  #
  # roles/securitycenter.admin:
  #   Manages SCC notification configs, findings, and BigQuery exports created by the
  #   organization and governance stages. No narrower predefined role exists for this.
  #
  # roles/iam.securityAdmin:
  #   Grants resourcemanager.{projects,folders,organizations}.{get,set}IamPolicy so
  #   the SA can create and manage IAM bindings across the org hierarchy. A custom role
  #   scoped to only these permissions would require the SA to already hold
  #   roles/iam.roleAdmin (which is equally privileged), creating a circular dependency.
  #   Prefer over roles/resourcemanager.organizationAdmin, which additionally grants
  #   full org resource management (create/delete folders, move projects, etc.).
  #   Access is restricted to this single SA by org policy; rotation is automated via
  #   the key-less WIF flows provisioned by this bootstrap module.
  for_each = toset([
    "roles/securitycenter.admin", # SCC findings and notifications management
    "roles/iam.securityAdmin",    # Minimum IAM-policy management scope — see rationale above
  ])

  org_id = var.org_id
  role   = each.key #tfsec:ignore:google-iam-no-privileged-service-accounts
  member = "serviceAccount:${module.terraform_admin_sa.email}"
}
