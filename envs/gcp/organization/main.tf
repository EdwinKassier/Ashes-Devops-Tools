locals {
  shared_environment = {
    display_name            = "Shared Services"
    description             = "Shared platform services"
    iam_group_role_bindings = var.shared_iam_group_role_bindings
    is_production           = false
  }

  organization_units = merge(
    {
      shared = local.shared_environment
    },
    {
      for env_key, env in local.environments : env_key => {
        display_name            = env.display_name
        description             = "${env.display_name} environment"
        iam_group_role_bindings = env.iam_group_role_bindings
        is_production           = env.is_production
      }
    }
  )

  # Outputs from the gcp-bootstrap root (admin project, Terraform admin SA, WIF
  # pools). gcp-bootstrap is applied first; this root reads it via remote state
  #.
  # Remote state when read (count = 1), else the supplied contract.
  # Each upstream is read through its single `contract` output. A producer
  # state from before that output existed (N-1, not yet re-applied) exposes the
  # same keys as individual outputs, so the read falls back to them; that
  # fallback goes at v1.0 with the individual outputs (UPGRADING.md).
  bootstrap = try(data.terraform_remote_state.gcp_bootstrap[0].outputs.contract, data.terraform_remote_state.gcp_bootstrap[0].outputs, local.bootstrap_contract)

  # Deny-policy ownership follows gcp-bootstrap unless set explicitly; an older
  # bootstrap state without the output means the legacy single-owner model.
  guardrail_owner_mode = coalesce(try(local.gcp.guardrail_owner_mode, null), try(local.bootstrap.guardrail_owner_mode, null), "organization")
}

# 1. Organization: Hierarchy & Governance
module "organization" {
  source = "../../../modules/gcp/stages/organization"

  domain               = local.domain
  org_id               = data.google_organization.org.org_id
  customer_id          = data.google_organization.org.directory_customer_id
  admin_project_id     = local.bootstrap.admin_project_id
  admin_project_number = local.bootstrap.admin_project_number
  billing_account      = data.google_billing_account.billing.id
  project_prefix       = local.project_prefix
  environments         = local.organization_units

  terraform_admin_email = local.bootstrap.terraform_admin_email

  # Every tuning input: the gcp section (config/landing-zone.yaml gcp.* under
  # var.gcp_overrides), plus the values this root derives from the estate.
  gcp = merge(local.gcp, {
    # Without a break-glass principal the stage is never asked for containment
    # (it would deny everyone); the contract output's precondition fails the plan.
    enable_admin_containment      = local.enable_admin_containment && length(local.containment_exempt_principals) > 0
    containment_exempt_principals = local.containment_exempt_principals
    # Deny policies are authored and applied by gcp-guardrails (separate) or here
    # (legacy organization mode).
    guardrail_owner_mode              = local.guardrail_owner_mode
    allowed_workload_identity_issuers = coalesce(try(local.gcp.allowed_workload_identity_issuers, null), ["https://${var.tfc_hostname}", "https://token.actions.githubusercontent.com"])
  })

  # Per-environment folder-scoped VPC-SC access policies; each environment's
  # workload SAs get rights on their own policy only. try() keeps an older
  # gcp-bootstrap state (no such outputs) planning with no grants.
  workload_service_accounts = {
    for env, sas in try(local.bootstrap.workload_service_accounts, {}) : env => sas
    if contains(keys(local.environments), env)
  }

  # projects-apply delegated folder IAM, bound on each environment folder and the
  # shared folder (not the org node).
  projects_apply_service_account  = try(local.bootstrap.stage_service_accounts["projects"].apply, null)
  delegated_workload_folder_roles = try(local.bootstrap.delegated_workload_folder_roles, [])
  delegated_network_folder_roles  = try(local.bootstrap.delegated_network_folder_roles, [])

  default_region               = local.default_region
  monthly_budget_amount        = local.monthly_budget_amount
  budget_threshold_rules       = local.budget_threshold_rules
  budget_notify_alert_channels = local.notify_budget_channels

  wif_tenant_pins = {
    tfc_hostname     = var.tfc_hostname
    tfc_organization = var.pin_wif_to_tfc_organization ? local.tfc_organization : null
    github_owner_ids = var.wif_github_owner_ids
  }

  # Explicit opt-out (gcp.admin_containment: false in config, or
  # gcp_overrides.enable_admin_containment = false; unset is not a waiver), or
  # the root's own precondition already fails the plan.
  production_containment_waived = local.gcp.enable_admin_containment == false || (local.enable_admin_containment && length(local.containment_exempt_principals) == 0)
}

# The projects stage (gcp-projects) and network-hub stage (gcp-network-hub) were
# split into their own roots and states. gcp-projects reads this
# root's folders/tag values; gcp-network-hub reads gcp-projects' host project
# IDs. See docs/architecture/gcp-state-decomposition.md.

# The starter profile must have a budget: an unmetered sandbox is the failure
# mode this profile exists to prevent.
resource "terraform_data" "starter_requires_budget" {
  count = local.profile == "starter" ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.monthly_budget_amount > 0
      error_message = "org.profile is starter but no monthly budget resolves: set org.monthly_budget_usd in config/landing-zone.yaml (or var.monthly_budget_amount) to a value above 0."
    }
  }
}
