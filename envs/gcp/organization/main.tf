locals {
  shared_environment = {
    display_name            = "Shared Services"
    description             = "Shared platform services"
    iam_group_role_bindings = var.shared_iam_group_role_bindings
  }

  organization_units = merge(
    {
      shared = local.shared_environment
    },
    {
      for env_key, env in var.environments : env_key => {
        display_name            = env.display_name
        description             = "${env.display_name} environment"
        iam_group_role_bindings = env.iam_group_role_bindings
      }
    }
  )

  # Outputs from the gcp-bootstrap root (admin project, Terraform admin SA, WIF
  # pools). gcp-bootstrap is applied first; this root reads it via remote state
  # (audit H3 — control-plane state decomposition).
  bootstrap = data.terraform_remote_state.gcp_bootstrap.outputs
}

# 1. Organization: Hierarchy & Governance
module "organization" {
  source = "../../../modules/gcp/stages/organization"

  domain               = var.domain
  org_id               = data.google_organization.org.org_id
  customer_id          = data.google_organization.org.directory_customer_id
  admin_project_id     = local.bootstrap.admin_project_id
  admin_project_number = local.bootstrap.admin_project_number
  billing_account      = data.google_billing_account.billing.id
  project_prefix       = var.project_prefix
  environments         = local.organization_units

  admin_email               = var.admin_email
  break_glass_user          = var.break_glass_user
  terraform_admin_email     = local.bootstrap.terraform_admin_email
  organization_admin_groups = var.organization_admin_groups
  billing_admin_groups      = var.billing_admin_groups

  default_region                        = var.default_region
  allowed_regions                       = var.allowed_regions
  strict_folder_policy_environment_keys = var.strict_folder_policy_environment_keys
  security_contact_email                = var.security_contact_email
  billing_contact_email                 = var.billing_contact_email
  monthly_budget_amount                 = var.monthly_budget_amount
  budget_currency                       = var.budget_currency

  # Audit G4: dedicated logging project for the org audit sink (default null = admin project).
  logging_project_id = var.logging_project_id

  # G6: opt-in custom org-policy constraints (default [] = none).
  custom_org_constraints = var.custom_org_constraints

  # G8: opt-in WORM lock on the audit-log bucket (default false).
  enable_audit_bucket_lock = var.enable_audit_bucket_lock

  # G9: opt-in IAM deny policies at the org node (default [] = none).
  iam_deny_policies = var.iam_deny_policies
}

# The projects stage (gcp-projects) and network-hub stage (gcp-network-hub) were
# split into their own roots and states (audit H3). gcp-projects reads this
# root's folders/tag values; gcp-network-hub reads gcp-projects' host project
# IDs. See docs/architecture/gcp-state-decomposition.md.
