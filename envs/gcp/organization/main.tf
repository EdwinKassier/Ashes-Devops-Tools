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
    # gcp.restrictTLSVersion (TLS 1.0/1.1 denied on Google APIs): on for the
    # production profile unless gcp_overrides.restrict_tls_versions is set.
    restrict_tls_versions = local.restrict_tls_versions
  })

  # Per-environment folder-scoped VPC-SC access policies; each environment's
  # workload SAs get rights on their own policy only. try() keeps an older
  # gcp-bootstrap state (no such outputs) planning with no grants.
  workload_service_accounts = {
    for env, sas in try(local.bootstrap.workload_service_accounts, {}) : env => sas
    if contains(keys(local.environments), env)
  }

  # The non-delegable workload folder roles (projectIamAdmin, secretmanager.admin
  # and the like) are granted by this stage, never through projects-apply's
  # delegation.
  workload_folder_roles = try(local.bootstrap.workload_folder_roles, { plan = [], apply = [] })

  # projects-apply delegated folder IAM, bound on each environment folder and the
  # shared folder (not the org node). The stage drops the non-delegable roles.
  projects_apply_service_account  = try(local.bootstrap.stage_service_accounts["projects"].apply, null)
  delegated_workload_folder_roles = try(local.bootstrap.delegated_workload_folder_roles, [])
  delegated_network_folder_roles  = try(local.bootstrap.delegated_network_folder_roles, [])

  # organization-apply's org securityAdmin is role-conditioned by gcp-bootstrap,
  # which also grants the standing organizationAdmin. The stage checks its
  # grants and its expected org admins against both lists at plan time.
  organization_apply_grantable_roles   = try(local.bootstrap.organization_apply_grantable_roles, null)
  bootstrap_organization_admin_members = try(local.bootstrap.organization_admin_members, null)

  default_region               = local.default_region
  audit_log_retention_days     = local.audit_log_retention_days
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

# Apply order guard. This root no longer grants organizationAdmin to the org
# admin groups: gcp-bootstrap does. A gcp-bootstrap state from before that
# change has no organization_apply_grantable_roles / organization_admin_members
# in its contract. Applying this root then would delete the standing
# organizationAdmin bindings (organization-apply still holds an unconditional
# securityAdmin until gcp-bootstrap is applied), so the plan fails instead.
locals {
  bootstrap_contract_is_current = try(local.bootstrap.organization_apply_grantable_roles, null) != null && try(local.bootstrap.organization_admin_members, null) != null
}

resource "terraform_data" "bootstrap_grants_org_admins" {
  count = local.bootstrap_contract == null ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.bootstrap_contract_is_current
      error_message = "The gcp-bootstrap contract has no organization_apply_grantable_roles / organization_admin_members: gcp-bootstrap has not been applied with this release. Apply gcp-bootstrap first (it takes over the standing organizationAdmin grant and conditions organization-apply's securityAdmin), then follow UPGRADING.md (remove module.organization.module.organization.google_organization_iam_member.org_admins from this root's state) before you apply this root."
    }
  }
}

# A hand-supplied contract (bootstrap_contract or gcp.contracts.bootstrap) may
# omit the two lists; the plan then cannot check them.
check "supplied_bootstrap_contract_is_current" {
  assert {
    condition     = local.bootstrap_contract == null || local.bootstrap_contract_is_current
    error_message = "The supplied bootstrap contract has no organization_apply_grantable_roles / organization_admin_members. This root grants no organizationAdmin and cannot check its grants against organization-apply's role condition. Make sure gcp-bootstrap was applied with this release and copy both lists from its contract output."
  }
}

# CMP-4: a regulated estate keeps its audit store WORM-locked in a project the
# automation identity does not own. Both settings are irreversible, so they are
# never defaults: the plan fails until they are set or explicitly waived. The
# waiver (CMP-05) names a reason and an expiry date, and stops waiving after
# that date.
resource "terraform_data" "regulated_audit_store_guard" {
  input = local.regulated_environment_keys

  lifecycle {
    precondition {
      condition     = !local.cfg.audit_store_waived_removed
      error_message = "gcp.audit_store_waived was removed. Replace it with gcp.audit_store_waiver: { reason: \"why the audit store is not hardened\", expires: \"YYYY-MM-DD\" } in config/landing-zone.yaml (UPGRADING.md)."
    }
    precondition {
      condition     = local.audit_store_waiver_valid
      error_message = "gcp.audit_store_waiver needs a non-empty reason and expires as a real calendar date, YYYY-MM-DD (UTC), quoted in YAML."
    }
    precondition {
      condition     = length(local.regulated_environment_keys) == 0 || local.audit_store_hardened || local.audit_store_waived
      error_message = "Regulated environments (${join(", ", local.regulated_environment_keys)}) need a hardened audit store: gcp.logging_project_id + gcp.logging_project_number (a project other than the admin project, directly under the organization; decide before the first apply because the audit keys cannot be moved) and gcp.enable_audit_bucket_lock: true (IRREVERSIBLE).${local.audit_store_waiver_until == null ? "" : " gcp.audit_store_waiver expired on ${try(tostring(local.cfg.audit_store_waiver.expires), "")}."} Or set gcp.audit_store_waiver: { reason, expires: \"YYYY-MM-DD\" } and record the risk. See docs/runbooks/production-hardening.md."
    }
  }
}

# The production profile only warns: the lock is irreversible and the logging
# project is created outside Terraform, so neither can be a default. It warns
# once the estate has a production environment (is_production), because the
# profile defaults to production even for an estate that has none yet.
check "production_audit_store" {
  assert {
    condition     = local.profile != "production" || length(local.production_environment_keys) == 0 || local.audit_store_hardened || local.audit_store_waived
    error_message = "Production profile with production environments (${join(", ", local.production_environment_keys)}): the audit bucket is not WORM-locked (gcp.enable_audit_bucket_lock) or shares the admin project (gcp.logging_project_id is unset). Auditors testing NIST 800-53 AU-9 or PCI DSS 10.3.3 will flag this. See docs/runbooks/production-hardening.md."
  }
}

# The logging project must sit directly under the organization node. In a
# folder, organization-apply's org-level folderIamAdmin could grant itself
# roles on it through the folder. A warning only: a check never fails the plan,
# also when the identity cannot read a project created outside Terraform.
check "logging_project_under_organization" {
  # A scoped data source cannot take count. Without a logging project it reads
  # the admin project, and the assertion ignores the result.
  data "google_project" "logging" {
    project_id = coalesce(try(local.gcp.logging_project_id, null), local.bootstrap.admin_project_id)
  }

  assert {
    condition     = try(local.gcp.logging_project_id, null) == null || try(data.google_project.logging.folder_id, "") == ""
    error_message = "gcp.logging_project_id (${coalesce(try(local.gcp.logging_project_id, null), "unset")}) is in a folder. Move it directly under the organization: organization-apply holds folderIamAdmin at the organization node and could grant itself roles on any project in a folder."
  }
}
