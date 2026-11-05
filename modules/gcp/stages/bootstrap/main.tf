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

  # The admin/automation project must not be deletable by a routine plan.
  deletion_policy = "PREVENT"
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

# Terraform Admin Service Account (= the gcp-bootstrap APPLY identity).
#
# C2: this SA is no longer shared by every TFC workspace. It is impersonable by the
# human admin for the documented phase-0 bootstrap, and WIF-bound ONLY to the
# gcp-bootstrap workspace's apply phase. Every other stage / environment runs as
# its own per-stage plan (read-only) or apply SA — see service_accounts.tf.
module "terraform_admin_sa" {
  source = "../../iam/service-account"

  project_id   = google_project.admin_project.project_id
  account_id   = "terraform-admin"
  display_name = "Terraform Admin"
  description  = "Centralised Terraform Admin for managing downstream resources"

  # Allow the actual admin user to impersonate this SA
  impersonation_members = ["user:${var.admin_email}"]
}


# ─── Workload Identity Federation ────────────────────────────────────────────

# GitHub Actions WIF (C2): OFF by default — no workflow in this repo requests
# `id-token: write`, so a standing trust was unused privilege. When enabled it
# trusts ONE repository by its immutable numeric IDs (repository_id +
# repository_owner_id, never the renameable names), only from refs/heads/main,
# and binds it to the READ-ONLY organization PLAN SA — never an apply/admin SA.
module "gh_oidc" {
  source = "../../iam/workload-identity"
  count  = var.enable_github_wif ? 1 : 0

  project_id   = google_project.admin_project.project_id
  pool_id      = var.github_wif_pool_id
  display_name = "GitHub Actions Pool"

  enable_github_provider     = true
  github_organization        = var.github_org
  github_repository_owner_id = var.github_repository_owner_id

  github_allowed_refs = ["refs/heads/main"]
  github_attribute_condition_override = join(" && ", [
    "assertion.repository_owner_id == '${coalesce(var.github_repository_owner_id, "unset")}'",
    "assertion.repository_id == '${coalesce(var.github_repository_id, "unset")}'",
    "assertion.ref == 'refs/heads/main'",
  ])

  github_sa_bindings = [
    {
      repository            = "${coalesce(var.github_org, "unset")}/${coalesce(var.github_repo, "unset")}"
      repository_id         = var.github_repository_id
      key                   = "organization-plan"
      service_account_email = google_service_account.stage["organization-plan"].email
    }
  ]
}

# Terraform Cloud WIF (Dynamic Credentials) — FAST-style plan/apply split.
# Every (workspace, run phase) gets its own binding: the plan phase of a
# workspace can only mint the stage's read-only plan SA, and only the apply phase
# can mint the write SA. Bindings use the immutable workspace ID when
# tfc_workspace_ids supplies one, else the workspace name.
module "tfc_oidc" {
  source = "../../iam/workload-identity"
  count  = var.enable_tfc_oidc && var.tfc_organization != null ? 1 : 0

  project_id   = google_project.admin_project.project_id
  pool_id      = "tfc-pool"
  display_name = "Terraform Cloud Pool"

  enable_tfc_provider = true
  tfc_organization    = var.tfc_organization
  tfc_organization_id = var.tfc_organization_id
  tfc_project_ids     = var.tfc_project_ids

  tfc_sa_bindings = [
    for key, sa in local.tfc_identities : {
      workspace_name        = sa.workspace
      workspace_id          = lookup(var.tfc_workspace_ids, sa.workspace, null)
      run_phase             = sa.phase
      service_account_email = local.stage_sa_email[key]
    }
  ]
}
