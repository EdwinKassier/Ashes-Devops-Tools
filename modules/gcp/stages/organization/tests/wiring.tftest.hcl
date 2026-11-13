# Wiring tests for the organization stage: the CMEK children (module.cmek and
# module.audit_cmek) are NOT overridden, so the key references the stage hands
# to the audit store, SCC notifications and billing must pass the consumers'
# own input validation (full projects/.../cryptoKeys/<key> resource IDs).
# Only module.organization is overridden (its data sources and folders).

mock_provider "google" {}

variables {
  domain                = "acme.io"
  org_id                = "123456789"
  admin_project_id      = "acme-admin-project"
  admin_project_number  = "123456789012"
  customer_id           = "C01abc123"
  terraform_admin_email = "terraform-admin@acme-admin-project.iam.gserviceaccount.com"
  billing_account       = "ABCDEF-123456-789012"
  project_prefix        = "acme"
  default_region        = "europe-west1"
  monthly_budget_amount = 0
  environments = {
    dev = {
      display_name            = "Development"
      description             = "Development environment"
      iam_group_role_bindings = {}
    }
  }
  gcp = {
    admin_email                           = "admin@acme.io"
    break_glass_user                      = "break-glass@acme.io"
    organization_admin_groups             = ["org-admins@acme.io"]
    billing_admin_groups                  = ["billing-admins@acme.io"]
    allowed_regions                       = ["europe-west1"]
    strict_folder_policy_environment_keys = ["prod"]
    budget_currency                       = "USD"
    alert_notification_emails             = ["secops@acme.io"]
  }
}

override_module {
  target  = module.organization
  outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "acme.io", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
}

run "org_cmek_feeds_audit_store_scc_and_billing" {
  command = plan

  assert {
    condition     = sort(keys(module.cmek.key_ids)) == sort(["audit-logs", "audit-analytics", "billing-alerts", "scc-notifications", "billing-export"])
    error_message = "without a logging project the org keyring must hold the audit, SCC and billing keys."
  }

  assert {
    condition     = module.audit_logs.storage_bucket_name == "acme-admin-project-audit-logs"
    error_message = "the audit store must plan in the admin project with the org CMEK."
  }
}

run "audit_cmek_in_logging_project" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      logging_project_id     = "acme-logging"
      logging_project_number = "999999999999"
    })
  }

  assert {
    condition     = sort(keys(module.audit_cmek[0].key_ids)) == sort(["audit-logs", "audit-analytics"]) && !contains(keys(module.cmek.key_ids), "audit-logs")
    error_message = "with a logging project the audit keys must move to the logging-project keyring."
  }

  assert {
    condition     = module.audit_logs.storage_bucket_name == "acme-logging-audit-logs"
    error_message = "the audit store must plan in the logging project with the audit CMEK."
  }
}

# CMP-02: the network and edge log sink is off unless the root asks for it.
run "network_log_export_off_by_default" {
  command = plan

  assert {
    condition     = module.audit_logs.network_log_sink == null && output.network_log_sink == null
    error_message = "without gcp.enable_network_log_export the stage must plan no network log sink."
  }
}

# On, it writes to the same audit bucket (here in the logging project) and the
# writer's logging.logWriter grant is checked against organization-apply's
# hasOnly allow-list.
run "network_log_export_to_audit_store" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      logging_project_id        = "acme-logging"
      logging_project_number    = "999999999999"
      enable_network_log_export = true
    })
  }

  assert {
    condition     = output.network_log_sink.destination == "storage.googleapis.com/acme-logging-audit-logs"
    error_message = "the network log sink must write to the protected audit bucket in the logging project."
  }

  assert {
    condition     = contains(local.organization_apply_granted_roles, "roles/logging.logWriter") && contains(local.organization_apply_granted_roles, "roles/storage.objectCreator")
    error_message = "the sink writer grants must be listed for the organization-apply hasOnly check."
  }
}

run "network_log_export_grant_not_allowed_fails" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_control_plane_alerting = false
      enable_network_log_export     = true
    })
    organization_apply_grantable_roles = ["roles/billing.admin", "roles/logging.bucketWriter"]
  }

  expect_failures = [terraform_data.organization_apply_grants_allowed]
}
