# Behaviour assertions for the stages/organization module (beyond the tag
# binding regression): audit store wiring, org-policy baseline, control-plane
# alerting, the C2/C3 admin-containment deny policy, and the dedicated logging
# project. mock_provider only — no GCP credentials needed.

mock_provider "google" {}

variables {
  domain                                = "acme.io"
  org_id                                = "123456789"
  admin_project_id                      = "acme-admin-project"
  admin_project_number                  = "123456789012"
  customer_id                           = "C01abc123"
  admin_email                           = "admin@acme.io"
  break_glass_user                      = "break-glass@acme.io"
  terraform_admin_email                 = "terraform-admin@acme-admin-project.iam.gserviceaccount.com"
  billing_account                       = "ABCDEF-123456-789012"
  project_prefix                        = "acme"
  organization_admin_groups             = ["org-admins@acme.io"]
  billing_admin_groups                  = ["billing-admins@acme.io"]
  default_region                        = "europe-west1"
  allowed_regions                       = ["europe-west1"]
  strict_folder_policy_environment_keys = ["prod"]
  monthly_budget_amount                 = 0
  budget_currency                       = "USD"
  alert_notification_emails             = ["secops@acme.io"]
  environments = {
    dev = {
      display_name            = "Development"
      description             = "Development environment"
      iam_group_role_bindings = {}
    }
  }
}

override_module {
  target = module.cmek
  outputs = {
    keyring_id   = "projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek"
    keyring_name = "acme-org-cmek"
    key_ids      = {}
    key_names = {
      "audit-logs"        = "projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/audit-logs"
      "audit-analytics"   = "projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/audit-analytics"
      "billing-alerts"    = "projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/billing-alerts"
      "scc-notifications" = "projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/scc-notifications"
      "billing-export"    = "projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek/cryptoKeys/billing-export"
    }
  }
}

override_module {
  target = module.audit_cmek
  outputs = {
    keyring_id   = "projects/acme-logging/locations/europe-west1/keyRings/acme-audit-cmek"
    keyring_name = "acme-audit-cmek"
    key_ids      = {}
    key_names = {
      "audit-logs"      = "projects/acme-logging/locations/europe-west1/keyRings/acme-audit-cmek/cryptoKeys/audit-logs"
      "audit-analytics" = "projects/acme-logging/locations/europe-west1/keyRings/acme-audit-cmek/cryptoKeys/audit-analytics"
    }
  }
}

override_module {
  target  = module.organization
  outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "acme.io", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
}

run "default_audit_store_and_org_policies" {
  command = plan

  assert {
    condition     = output.audit_project_id == "acme-admin-project" && module.audit_logs.storage_bucket_name == "acme-admin-project-audit-logs"
    error_message = "with no logging_project_id the audit bucket must live in the admin project."
  }

  assert {
    condition     = module.audit_logs.org_log_sink_name == "org-audit-sink"
    error_message = "the org-level audit sink must be created (org_id is set)."
  }

  assert {
    condition = alltrue([
      for c in ["iam.disableServiceAccountKeyCreation", "iam.disableServiceAccountKeyUpload", "storage.publicAccessPrevention", "iam.automaticIamGrantsForDefaultServiceAccounts", "compute.skipDefaultNetworkCreation"] :
      contains(keys(module.org_policies.boolean_policy_names), c)
    ])
    error_message = "the org-policy baseline must enforce SA-key, public-access, default-SA-grant and default-network constraints at the org node."
  }

  assert {
    condition = alltrue([
      for c in ["gcp.resourceLocations", "iam.allowedPolicyMemberDomains", "compute.vmExternalIpAccess", "compute.restrictVpcPeering"] :
      contains(keys(module.org_policies.list_policy_names), c)
    ])
    error_message = "the org-policy baseline must set resource locations, domain-restricted sharing, external-IP and peering list constraints."
  }

  assert {
    condition     = length(output.admin_containment_rules) == 0 && length(module.iam_deny.deny_policy_names) == 0
    error_message = "admin containment must be off by default (no deny policy)."
  }

  assert {
    condition     = length(google_tags_location_tag_binding.containment_buckets) == 0 && length(google_tags_location_tag_binding.containment_audit_keyring) == 0
    error_message = "no containment tag bindings when containment is off."
  }
}

run "control_plane_alerting_wired_by_default" {
  command = plan

  assert {
    condition = alltrue([
      for w in ["org_iam_change", "org_policy_change", "vpc_sc_change", "log_sink_change", "custom_role_change", "deny_policy_change", "break_glass_use"] :
      contains(module.control_plane_alerting.watched_names, w)
    ])
    error_message = "control-plane alerting must watch org IAM, org policy, VPC-SC, sinks, custom roles, deny policies and break-glass use."
  }

  assert {
    condition     = module.control_plane_alerting.org_log_route_sink_name == "org-control-plane-to-monitoring"
    error_message = "org Admin Activity logs must be routed into the monitoring project for the log-match alerts."
  }
}

run "control_plane_alerting_can_be_disabled" {
  command = plan

  variables {
    enable_control_plane_alerting = false
    alert_notification_emails     = []
  }

  assert {
    condition     = length(module.control_plane_alerting.watched_names) == 0 && module.control_plane_alerting.org_log_route_sink_name == null
    error_message = "enable_control_plane_alerting = false must create no watches and no route sink."
  }
}

run "no_alert_destination_warns" {
  command = plan

  variables {
    alert_notification_emails = []
  }

  expect_failures = [check.control_plane_alerts_have_a_destination]
}

run "containment_denies_mutation_and_tag_scopes_audit_store" {
  command = plan

  variables {
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
  }

  assert {
    condition     = contains(module.iam_deny.deny_policy_names, "contain-admin-identity")
    error_message = "enabling containment must create the contain-admin-identity deny policy."
  }

  assert {
    condition = length(output.admin_containment_rules) == 2 && alltrue([
      for p in [
        "logging.googleapis.com/sinks.update",
        "logging.googleapis.com/sinks.delete",
        "logging.googleapis.com/exclusions.create",
        "logging.googleapis.com/exclusions.update",
        "logging.googleapis.com/exclusions.delete",
        "accesscontextmanager.googleapis.com/servicePerimeters.update",
        "accesscontextmanager.googleapis.com/servicePerimeters.delete",
        "accesscontextmanager.googleapis.com/policies.delete",
      ] : contains(output.admin_containment_rules[0].denied_permissions, p)
    ]) && !output.admin_containment_rules[0].tag_scoped
    error_message = "rule 1 must deny sink/exclusion/perimeter mutation org-wide (unconditioned)."
  }

  assert {
    condition = alltrue([
      for p in [
        "storage.googleapis.com/buckets.delete",
        "storage.googleapis.com/buckets.setIamPolicy",
        "storage.googleapis.com/objects.delete",
        "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
        "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
      ] : contains(output.admin_containment_rules[1].denied_permissions, p)
    ]) && output.admin_containment_rules[1].tag_scoped
    error_message = "rule 2 must deny audit-store bucket/object/key destruction, scoped by the containment tag."
  }

  assert {
    condition = alltrue([
      for r in output.admin_containment_rules :
      length(r.exception_principals) == 1 && contains(r.exception_principals, "principalSet://goog/group/break-glass@acme.io")
    ])
    error_message = "every containment rule must exempt the break-glass principal."
  }

  # Unsupported in IAM deny — must never appear (they would fail the API call).
  assert {
    condition = !anytrue([
      for r in output.admin_containment_rules : anytrue([
        for p in r.denied_permissions : can(regex("denypolicies|accessPolicies", p))
      ])
    ])
    error_message = "iam.denypolicies.* and accessPolicies.delete are not deny-supported and must not be listed."
  }

  assert {
    condition = length(google_tags_location_tag_binding.containment_buckets) == 2 && alltrue([
      for b in google_tags_location_tag_binding.containment_buckets : startswith(b.parent, "//storage.googleapis.com/projects/_/buckets/acme-admin-project-audit-logs")
    ])
    error_message = "the containment tag must be bound to the audit bucket and its access-log bucket."
  }

  assert {
    condition     = google_tags_location_tag_binding.containment_audit_keyring[0].parent == "//cloudkms.googleapis.com/projects/acme-admin-project/locations/europe-west1/keyRings/acme-org-cmek"
    error_message = "the containment tag must be bound to the keyring holding the audit CMEK keys."
  }
}

run "containment_rejects_placeholder_break_glass" {
  command = plan

  variables {
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]
  }

  expect_failures = [var.containment_exempt_principals]
}

run "dedicated_logging_project_holds_audit_store_and_cmek" {
  command = plan

  variables {
    logging_project_id            = "acme-logging"
    logging_project_number        = "999999999999"
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
  }

  assert {
    condition     = output.audit_project_id == "acme-logging" && module.audit_logs.storage_bucket_name == "acme-logging-audit-logs"
    error_message = "with logging_project_id set the audit bucket must live in the logging project."
  }

  assert {
    condition     = output.cmek_key_names["audit-logs"] == "projects/acme-logging/locations/europe-west1/keyRings/acme-audit-cmek/cryptoKeys/audit-logs"
    error_message = "the audit CMEK key must come from the logging project's keyring."
  }

  assert {
    condition     = google_tags_location_tag_binding.containment_audit_keyring[0].parent == "//cloudkms.googleapis.com/projects/acme-logging/locations/europe-west1/keyRings/acme-audit-cmek"
    error_message = "containment must protect the logging-project audit keyring."
  }
}

run "logging_project_requires_number" {
  command = plan

  variables {
    logging_project_id = "acme-logging"
  }

  expect_failures = [var.logging_project_number]
}
