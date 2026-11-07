# Root behaviour test for the gcp-organization root (it had no tests before the
# 2026-11-05 audit). Overrides the gcp-bootstrap remote state and the org /
# billing lookups, plus the two nested modules whose mock outputs would trip
# downstream validation (KMS key names, org ID), then asserts what the root
# actually plans: audit sink destination, org-policy baseline, control-plane
# alerting, and the C2/C3 admin-containment deny policy.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  domain                   = "acme.io"
  project_prefix           = "acme"
  billing_account          = "ABCDEF-123456-789012"
  tfc_organization         = "acme-tfc"
  environments = {
    dev = {
      display_name            = "Development"
      region                  = "europe-west1"
      cidr_block              = "10.10.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
    }
    prod = {
      display_name            = "Production"
      region                  = "europe-west1"
      cidr_block              = "10.30.0.0/16"
      budget_monthly_limit    = 1000
      iam_group_role_bindings = {}
    }
  }
  gcp_overrides = {
    admin_email               = "admin@acme.io"
    break_glass_user          = "break-glass@acme.io"
    alert_notification_emails = ["secops@acme.io"]
    organization_admin_groups = ["gcp-org-admins@acme.io"]
    billing_admin_groups      = ["gcp-billing-admins@acme.io"]
  }
}

override_data {
  target = data.terraform_remote_state.gcp_bootstrap
  values = {
    outputs = {
      contract = {
        admin_project_id          = "acme-admin-abcd"
        admin_project_number      = "123456789012"
        terraform_admin_email     = "terraform-admin@acme-admin-abcd.iam.gserviceaccount.com"
        github_oidc_pool_id       = "github-pool"
        github_oidc_provider_name = "projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github"
        tfc_oidc_pool_id          = null
        tfc_oidc_provider_name    = null
        workload_service_accounts = {
          dev  = { plan = "acme-wl-dev-plan@acme-admin-abcd.iam.gserviceaccount.com", apply = "acme-wl-dev-apply@acme-admin-abcd.iam.gserviceaccount.com" }
          prod = { plan = "acme-wl-prod-plan@acme-admin-abcd.iam.gserviceaccount.com", apply = "acme-wl-prod-apply@acme-admin-abcd.iam.gserviceaccount.com" }
        }
        stage_service_accounts = {
          projects = { plan = "acme-projects-plan@acme-admin-abcd.iam.gserviceaccount.com", apply = "acme-projects-apply@acme-admin-abcd.iam.gserviceaccount.com" }
        }
        delegated_workload_folder_roles = ["roles/compute.admin", "roles/run.admin"]
        delegated_network_folder_roles  = ["roles/compute.networkAdmin"]
      }
    }
  }
}

override_data {
  target = data.google_organization.org
  values = {
    org_id                = "111122223333"
    directory_customer_id = "C01abc123"
  }
}

override_data {
  target = data.google_billing_account.billing
  values = {
    id = "ABCDEF-123456-789012"
  }
}

override_module {
  target = module.organization.module.cmek
  outputs = {
    keyring_id   = "projects/acme-admin-abcd/locations/europe-west1/keyRings/acme-org-cmek"
    keyring_name = "acme-org-cmek"
    key_ids      = {}
    key_names = {
      "audit-logs"        = "projects/acme-admin-abcd/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/audit-logs"
      "audit-analytics"   = "projects/acme-admin-abcd/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/audit-analytics"
      "billing-alerts"    = "projects/acme-admin-abcd/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/billing-alerts"
      "scc-notifications" = "projects/acme-admin-abcd/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/scc-notifications"
      "billing-export"    = "projects/acme-admin-abcd/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/billing-export"
    }
  }
}

override_module {
  target = module.organization.module.organization
  outputs = {
    organization_id                    = "111122223333"
    organization_name                  = "organizations/111122223333"
    organization_domain                = "acme.io"
    organization_directory_customer_id = "C01abc123"
    folder_iam_members                 = {}
    enabled_apis                       = []
    organizational_units = {
      shared = { id = "folders/100", name = "folders/100", display_name = "Shared Services" }
      dev    = { id = "folders/200", name = "folders/200", display_name = "Development" }
      prod   = { id = "folders/300", name = "folders/300", display_name = "Production" }
    }
    folders = {
      shared = { id = "folders/100", name = "folders/100", display_name = "Shared Services" }
      dev    = { id = "folders/200", name = "folders/200", display_name = "Development" }
      prod   = { id = "folders/300", name = "folders/300", display_name = "Production" }
    }
  }
}

run "audit_sink_and_org_policies" {
  command = plan

  # Org-wide audit sink -> GCS bucket in the admin project (no logging project set).
  assert {
    condition     = module.organization.audit_org_sink_name == "org-audit-sink"
    error_message = "the root must plan the org-level audit sink."
  }

  assert {
    condition     = output.audit_logs_bucket_name == "acme-admin-abcd-audit-logs" && output.audit_project_id == "acme-admin-abcd"
    error_message = "the org audit sink destination bucket must be <admin-project>-audit-logs in the admin project by default."
  }

  assert {
    condition = alltrue([
      for c in ["gcp.resourceLocations", "iam.allowedPolicyMemberDomains", "compute.managed.vmExternalIpAccess"] :
      contains(module.organization.org_policy_constraints, c)
    ])
    error_message = "the root must plan the org-node list-policy baseline."
  }

  assert {
    condition = alltrue([
      for c in ["iam.managed.disableServiceAccountKeyCreation", "storage.publicAccessPrevention", "storage.uniformBucketLevelAccess"] :
      contains(module.organization.org_policy_constraints, c)
    ])
    error_message = "the root must plan the org-node boolean-policy baseline."
  }

  # The strict prod folder bundle attaches to the prod folder.
  assert {
    condition     = contains(module.organization.strict_folder_policy_environment_keys, "prod")
    error_message = "strict folder policies must be planned for the prod folder."
  }

  # CIS GCP 4.4: OS Login is required at the org node by default.
  assert {
    condition     = contains(module.organization.org_policy_constraints, "compute.managed.requireOsLogin")
    error_message = "the root must plan compute.requireOsLogin at the org node."
  }

  assert {
    condition     = output.org_id == "111122223333"
    error_message = "org_id must be re-exported for downstream roots."
  }
}

run "control_plane_alerting_present_by_default" {
  command = plan

  assert {
    condition = alltrue([
      for w in ["org_iam_change", "org_policy_change", "vpc_sc_change", "log_sink_change", "custom_role_change", "deny_policy_change", "break_glass_use"] :
      contains(module.organization.control_plane_watched_names, w)
    ])
    error_message = "the control-plane alert module must be instantiated with the guardrail and break-glass watches."
  }

  assert {
    condition     = module.organization.control_plane_org_log_route_sink_name != null
    error_message = "org Admin Activity logs must be routed into the alerting project."
  }

  assert {
    condition     = length(output.control_plane_alert_policy_ids) >= 8
    error_message = "the root must expose the control-plane alert policy IDs."
  }

  assert {
    condition     = length(module.organization.control_plane_cis_log_metric_names) == 8
    error_message = "the root must plan the CIS GCP 2.4-2.11 log metrics by default."
  }
}

run "containment_off_by_default" {
  command = plan

  assert {
    condition     = length(module.organization.admin_containment_rules) == 0 && length(module.organization.iam_deny_policy_names) == 0
    error_message = "admin containment must be off by default."
  }
}

run "containment_deny_policy_when_enabled" {
  command = plan

  variables {
    gcp_overrides = merge(var.gcp_overrides, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  assert {
    condition     = contains(module.organization.iam_deny_policy_names, "contain-admin-identity")
    error_message = "enabling containment must plan the contain-admin-identity deny policy at the org node."
  }

  assert {
    condition = alltrue([
      for p in [
        "logging.googleapis.com/sinks.update",
        "logging.googleapis.com/sinks.delete",
        "logging.googleapis.com/exclusions.create",
        "accesscontextmanager.googleapis.com/servicePerimeters.update",
        "accesscontextmanager.googleapis.com/policies.delete",
        "storage.googleapis.com/objects.delete",
        "storage.googleapis.com/buckets.setIamPolicy",
        "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
        "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
      ] : contains(flatten([for r in module.organization.admin_containment_rules : r.denied_permissions]), p)
    ])
    error_message = "the containment deny policy must cover sink/exclusion/perimeter mutation and audit-store destruction."
  }
}

# A placeholder break-glass principal is rejected by the stage's gcp object
# validation; a root test cannot expect a child-module failure, so that case is
# modules/gcp/stages/organization tests/plan_assertions
# containment_rejects_placeholder_break_glass.

# Standing admin is group-only; the bootstrap admin user is not a standing org admin.
run "standing_admin_is_group_only" {
  command = plan

  assert {
    condition     = module.organization.org_admin_members == tolist(["group:gcp-org-admins@acme.io"]) && length([for m in module.organization.billing_admin_members : m if startswith(m, "user:")]) == 0
    error_message = "org/billing admin must be granted to groups only by default."
  }
}

# Each environment's workload SAs get rights on their OWN scoped access policy;
# projects-apply's folder-IAM delegation is bound per folder.
run "scoped_policies_and_per_folder_delegation" {
  command = plan

  assert {
    condition     = sort(keys(module.organization.scoped_access_policy_grants)) == sort(["dev|apply", "dev|plan", "prod|apply", "prod|plan"]) && module.organization.scoped_access_policy_grants["prod|apply"].member == "serviceAccount:acme-wl-prod-apply@acme-admin-abcd.iam.gserviceaccount.com" && module.organization.scoped_access_policy_grants["prod|apply"].env == "prod"
    error_message = "each workload SA must be granted on its own environment's scoped access policy only."
  }

  assert {
    condition     = sort(keys(output.delegated_folder_iam_targets)) == sort(["dev", "prod", "shared"]) && output.delegated_folder_iam_targets["shared"] == tolist(["roles/compute.networkAdmin"]) && !contains(output.delegated_folder_iam_targets["prod"], "roles/compute.networkAdmin")
    error_message = "projects-apply delegation must be bound on every env folder (workload roles) and the shared folder (network roles)."
  }
}

# is_production flows into the stage (whose check warns without containment; the
# warning path is covered by the stage tests), so pair it with containment here.
run "production_environment_with_containment" {
  command = plan

  variables {
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west1"
        cidr_block              = "10.30.0.0/16"
        budget_monthly_limit    = 1000
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
    gcp_overrides = merge(var.gcp_overrides, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  assert {
    condition     = module.organization.production_environment_keys == tolist(["prod"])
    error_message = "is_production must flow into the organization stage."
  }
}

# The bootstrap read is skippable (bootstrap_contract), mirroring gcp-projects:
# no remote-state read, and the contract feeds the stage. Its default
# guardrail_owner_mode = "separate" moves the deny policies to the gcp-guardrails
# root (nothing built or applied here).
run "bootstrap_contract_skips_remote_state" {
  command = plan

  variables {
    bootstrap_contract = {
      admin_project_id      = "acme-admin-ctr1"
      admin_project_number  = "999988887777"
      terraform_admin_email = "terraform-admin@acme-admin-ctr1.iam.gserviceaccount.com"
    }
    gcp_overrides = merge(var.gcp_overrides, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  assert {
    condition     = length(data.terraform_remote_state.gcp_bootstrap) == 0 && output.admin_project_number == "999988887777"
    error_message = "A bootstrap_contract must replace the gcp-bootstrap remote-state read."
  }

  assert {
    condition     = output.guardrail_owner_mode == "separate" && length(module.organization.iam_deny_policy_names) == 0 && length(output.guardrail_deny_policy_specs) == 0 && length(module.organization.admin_containment_rules) == 0
    error_message = "In separate mode gcp-organization must neither build nor apply the containment deny policy: the gcp-guardrails root owns it."
  }

  assert {
    condition     = output.github_oidc_pool_id == null
    error_message = "WIF outputs absent from a contract must be null, not an error."
  }
}

run "bootstrap_contract_from_config_file" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-bootstrap-contract.yaml"
  }

  assert {
    condition     = length(data.terraform_remote_state.gcp_bootstrap) == 0 && output.admin_project.project_id == "acme-admin-cfg1"
    error_message = "gcp.contracts.bootstrap in config/landing-zone.yaml must replace the remote-state read."
  }
}

# An older gcp-bootstrap state (no guardrail_owner_mode output) keeps the legacy
# in-root deny policies: its organization apply SA still holds denyAdmin.
run "legacy_bootstrap_state_keeps_in_root_deny_policies" {
  command = plan

  variables {
    gcp_overrides = merge(var.gcp_overrides, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  assert {
    condition     = output.guardrail_owner_mode == "organization" && contains(module.organization.iam_deny_policy_names, "contain-admin-identity")
    error_message = "Without a bootstrap guardrail_owner_mode output the root must keep applying the deny policies."
  }
}

# Containment derives ON for a production estate, with the break-glass group
# and alert emails taken from config/landing-zone.yaml.
run "containment_derived_on_for_production_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-containment.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = output.admin_containment_enabled == true && jsonencode(local.containment_exempt_principals) == jsonencode(["principalSet://goog/group/gcp-break-glass@acme.io"]) && jsonencode(local.gcp.alert_notification_emails) == jsonencode(["secops@acme.io"]) && length(module.organization.admin_containment_rules) > 0
    error_message = "a production estate must turn containment on with the config break-glass group and alert emails."
  }
}

# An explicit gcp.admin_containment: false in config waives the production
# containment requirement (unset is not a waiver).
run "config_false_waives_containment" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-containment-waived.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = output.admin_containment_enabled == false && length(module.organization.admin_containment_rules) == 0
    error_message = "gcp.admin_containment: false must waive containment for a production estate and plan."
  }
}

# Production without a break-glass principal fails the plan instead of
# silently shipping an unprotected audit store.
run "production_without_break_glass_fails" {
  command = plan

  variables {
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west1"
        cidr_block              = "10.30.0.0/16"
        budget_monthly_limit    = 1000
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
  }

  expect_failures = [output.contract]
}

run "production_containment_explicit_opt_out" {
  command = plan

  variables {
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west1"
        cidr_block              = "10.30.0.0/16"
        budget_monthly_limit    = 1000
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
    gcp_overrides = merge(var.gcp_overrides, {
      enable_admin_containment = false
    })
  }

  assert {
    condition     = output.admin_containment_enabled == false
    error_message = "an explicit gcp_overrides.enable_admin_containment = false must win over the production default."
  }
}

# gcp.principal_access_boundary is shared with gcp-bootstrap and gcp-guardrails:
# the boundary is bound here and (legacy organization mode) the containment
# policy denies its update/delete/unbind.
run "principal_access_boundary_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = local.gcp.enable_principal_access_boundary && contains(flatten([for r in module.organization.admin_containment_rules : r.denied_permissions]), "iam.googleapis.com/principalaccessboundarypolicies.unbind")
    error_message = "gcp.principal_access_boundary: true must turn the boundary (and its containment deny rules) on."
  }
}

run "principal_access_boundary_variable_wins_over_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides = {
      enable_principal_access_boundary = false
    }
  }

  assert {
    condition     = !local.gcp.enable_principal_access_boundary && output.principal_access_boundary_policy == null
    error_message = "an explicit gcp_overrides.enable_principal_access_boundary = false must override the config key."
  }
}

# notifications.emails feeds the control-plane alert channels when neither
# gcp_overrides.alert_notification_emails nor gcp.alert_emails is set.
run "emails_feed_gcp_channels" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = join(",", local.gcp.alert_notification_emails) == "alerts@acme.io"
    error_message = "notifications.emails must feed the GCP control-plane alert channels."
  }
}

# Precedence: gcp_overrides > gcp.alert_emails > notifications.emails.
run "gcp_alert_emails_beat_notifications_emails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications-both.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = join(",", local.gcp.alert_notification_emails) == "secops@acme.io"
    error_message = "gcp.alert_emails must win over notifications.emails."
  }
}

run "explicit_variable_beats_notifications_emails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications-both.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides = {
      alert_notification_emails = ["explicit@acme.io"]
    }
  }

  assert {
    condition     = join(",", local.gcp.alert_notification_emails) == "explicit@acme.io"
    error_message = "the explicit override must win over every config key."
  }
}

# No notifications section: the explicit override is used as-is and budgets get
# no extra channels (today's behaviour).
run "no_section_is_noop" {
  command = plan

  assert {
    condition     = join(",", local.gcp.alert_notification_emails) == "secops@acme.io" && !local.notify_budget_channels
    error_message = "without a notifications section the alert list is the override and budgets get no channels."
  }
}

# starter: the budget comes from org.monthly_budget_usd and alerts at 50/80/100%
# through the notifications.emails channels.
run "starter_budget_alerts_wired" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-starter.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = local.monthly_budget_amount == 300 && jsonencode([for r in local.budget_threshold_rules : r.percent]) == jsonencode([0.5, 0.8, 1])
    error_message = "starter must budget org.monthly_budget_usd with 50/80/100% thresholds."
  }

  assert {
    condition     = local.notify_budget_channels && join(",", local.gcp.alert_notification_emails) == "alerts@acme.io"
    error_message = "starter budget alerts must reach notifications.emails."
  }
}

# starter without a resolvable budget amount must fail the plan.
run "starter_requires_budget" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-starter-nobudget.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  expect_failures = [terraform_data.starter_requires_budget]
}

# Production keeps today's default budget and threshold set.
run "production_budget_unchanged" {
  command = plan

  assert {
    condition     = local.monthly_budget_amount == 1000 && local.budget_threshold_rules == null && length(terraform_data.starter_requires_budget) == 0
    error_message = "production must keep the 1000 default budget and the module-default thresholds."
  }
}

# org.monthly_budget_usd only applies to the starter profile; production keeps 1000.
run "production_ignores_monthly_budget_usd" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-production-budget.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = local.monthly_budget_amount == 1000
    error_message = "a production estate must keep the 1000 default despite org.monthly_budget_usd."
  }
}

# Object pass-through precedence: a set gcp_overrides key beats the config file
# (config keys and override-only keys alike) ...
run "override_wins_over_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides = {
      admin_email                      = "override-admin@acme.io"
      allowed_regions                  = ["europe-west2"]
      enable_principal_access_boundary = false
      enable_log_analytics             = false
    }
  }

  assert {
    condition     = local.gcp.admin_email == "override-admin@acme.io" && jsonencode(local.gcp.allowed_regions) == jsonencode(["europe-west2"])
    error_message = "a set gcp_overrides key must win over gcp.* in config/landing-zone.yaml."
  }

  assert {
    condition     = output.principal_access_boundary_policy == null && output.log_analytics_bucket_id == null
    error_message = "the overridden values must reach the stage (boundary and Log Analytics off)."
  }
}

# ... and an unset (or null) key keeps the config value, else the stage default.
run "unset_override_keeps_config_value" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides = {
      admin_email     = null
      allowed_regions = null
    }
  }

  assert {
    condition     = local.gcp.admin_email == "admin@acme.io" && jsonencode(local.gcp.allowed_regions) == jsonencode(["europe-west1"]) && local.gcp.enable_principal_access_boundary == true
    error_message = "an unset gcp_overrides key must keep the gcp.* config value."
  }

  assert {
    condition     = contains(flatten([for r in module.organization.admin_containment_rules : r.denied_permissions]), "iam.googleapis.com/principalaccessboundarypolicies.unbind")
    error_message = "the config value (boundary on) must reach the stage."
  }
}

# A removed variable that is still set (tfvars, TFC variable or TF_VAR_) fails
# the plan, and the message names its gcp_overrides replacement.
run "removed_input_fails_with_replacement" {
  command = plan

  variables {
    enable_pam = true
  }

  expect_failures = [terraform_data.removed_inputs_guard]

  assert {
    condition     = local.removed_inputs_message == "Removed variables are set; move each into gcp_overrides (UPGRADING.md): enable_pam -> gcp_overrides.enable_pam."
    error_message = "the guard must name the removed variable and its gcp_overrides key."
  }
}

# ... and a key unset in both the config file and gcp_overrides takes the stage
# default (strict_folder_policy_environment_keys = ["prod"]; the fixture has no
# such key and the schema has none).
run "unset_everywhere_takes_stage_default" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                   = null
    project_prefix           = null
    billing_account          = null
    tfc_organization         = null
    environments             = null
    gcp_overrides            = {}
  }

  assert {
    condition     = try(local.gcp.strict_folder_policy_environment_keys, null) == null && module.organization.strict_folder_policy_environment_keys == tolist(["prod"])
    error_message = "a key unset in config and gcp_overrides must reach the stage as its default (strict folder bundle on prod)."
  }
}
