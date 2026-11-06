# Admin Project - Foundation of the Automation.
# Created through the shared project primitive (modules/gcp/project), so the
# admin project gets the same baseline as every other project: no default
# network, deletion_policy = PREVENT, APIs never disabled on destroy. The naming
# scheme (<prefix>-admin-<suffix>) stays here in the stage.
resource "random_id" "suffix" {
  byte_length = 4
}

module "admin_project" {
  source = "../../project"

  name            = "${var.project_prefix}-admin"
  project_id      = "${var.project_prefix}-admin-${random_id.suffix.hex}"
  parent          = "organizations/${var.org_id}"
  billing_account = var.billing_account

  labels = {
    environment = "admin"
    purpose     = "administration"
    managed-by  = "terraform"
  }

  # The admin/automation project must not be deletable by a routine plan.
  deletion_policy = "PREVENT"

  # Essential APIs on the admin project.
  services = [
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
  ]
}

# Terraform Admin Service Account (= the gcp-bootstrap APPLY identity).
#
# This SA is no longer shared by every TFC workspace. It is impersonable by the
# human admin for the documented phase-0 bootstrap, and WIF-bound ONLY to the
# gcp-bootstrap workspace's apply phase. Every other stage / environment runs as
# its own per-stage plan (read-only) or apply SA — see service_accounts.tf.
module "terraform_admin_sa" {
  source = "../../iam/service-account"

  project_id   = module.admin_project.project_id
  account_id   = "terraform-admin"
  display_name = "Terraform Admin"
  description  = "Centralised Terraform Admin for managing downstream resources"

  # Phase-0 only: the human admin impersonates this SA for the first bootstrap
  # apply. Set enable_phase0_admin_impersonation = false once the gcp-bootstrap
  # workspace applies through TFC dynamic credentials (pass 2), so no standing
  # human path to the bootstrap apply identity remains.
  impersonation_members    = local.phase0_admin_impersonation_members
  impersonation_expires_at = var.phase0_admin_impersonation_expires_at
}

# The phase-0 human path reaches the org-level security-admin identity. On a
# production estate it must not be open-ended: disable it after the TFC
# handover, or at least time-box it.
check "phase0_impersonation_is_time_boxed" {
  assert {
    condition     = !var.enable_phase0_admin_impersonation || length(var.production_workload_environments) == 0 || var.phase0_admin_impersonation_expires_at != null
    error_message = "Production environments exist and ${var.admin_email} can impersonate terraform-admin (org security admin) with no expiry. After the TFC handover set enable_phase0_admin_impersonation = false, or set phase0_admin_impersonation_expires_at (RFC 3339) to time-box it."
  }
}

locals {
  phase0_admin_impersonation_members = var.enable_phase0_admin_impersonation ? ["user:${var.admin_email}"] : []
}


# ─── Workload Identity Federation ────────────────────────────────────────────

# GitHub Actions WIF: OFF by default — no workflow in this repo requests
# `id-token: write`, so a standing trust was unused privilege. When enabled it
# trusts ONE repository by its immutable numeric IDs (repository_id +
# repository_owner_id, never the renameable names), only from refs/heads/main,
# and binds it to the READ-ONLY organization PLAN SA — never an apply/admin SA.
module "gh_oidc" {
  source = "../../iam/workload-identity"
  count  = var.enable_github_wif ? 1 : 0

  project_id   = module.admin_project.project_id
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

  project_id   = module.admin_project.project_id
  pool_id      = "tfc-pool"
  display_name = "Terraform Cloud Pool"

  enable_tfc_provider = true
  tfc_hostname        = var.tfc_hostname
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
