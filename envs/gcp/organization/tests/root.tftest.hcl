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
  domain                    = "acme.io"
  project_prefix            = "acme"
  admin_email               = "admin@acme.io"
  break_glass_user          = "break-glass@acme.io"
  billing_account           = "ABCDEF-123456-789012"
  tfc_organization          = "acme-tfc"
  alert_notification_emails = ["secops@acme.io"]
  organization_admin_groups = ["gcp-org-admins@acme.io"]
  billing_admin_groups      = ["gcp-billing-admins@acme.io"]
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
}

override_data {
  target = data.terraform_remote_state.gcp_bootstrap
  values = {
    outputs = {
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
      for c in ["gcp.resourceLocations", "iam.allowedPolicyMemberDomains", "compute.vmExternalIpAccess"] :
      contains(module.organization.org_policy_constraints, c)
    ])
    error_message = "the root must plan the org-node list-policy baseline."
  }

  assert {
    condition = alltrue([
      for c in ["iam.disableServiceAccountKeyCreation", "storage.publicAccessPrevention", "storage.uniformBucketLevelAccess"] :
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
    condition     = contains(module.organization.org_policy_constraints, "compute.requireOsLogin")
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
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
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

run "containment_rejects_preset_placeholder" {
  command = plan

  variables {
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]
  }

  expect_failures = [var.containment_exempt_principals]
}

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
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
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

  assert {
    condition     = module.organization.production_environment_keys == tolist(["prod"])
    error_message = "is_production must flow into the organization stage."
  }
}
