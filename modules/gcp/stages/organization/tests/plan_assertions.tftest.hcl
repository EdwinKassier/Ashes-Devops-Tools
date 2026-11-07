# Behaviour assertions for the stages/organization module (beyond the tag
# binding regression): audit store wiring, org-policy baseline, control-plane
# alerting, the C2/C3 admin-containment deny policy, and the dedicated logging
# project. mock_provider only — no GCP credentials needed.

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
      for c in ["iam.managed.disableServiceAccountKeyCreation", "iam.managed.disableServiceAccountKeyUpload", "storage.publicAccessPrevention", "iam.managed.preventPrivilegedBasicRolesForDefaultServiceAccounts", "compute.skipDefaultNetworkCreation"] :
      contains(output.org_policy_constraints, c)
    ])
    error_message = "the org-policy baseline must enforce SA-key, public-access, default-SA-grant and default-network constraints at the org node (managed versions where Google offers them)."
  }

  assert {
    condition = alltrue([
      for c in ["gcp.resourceLocations", "iam.allowedPolicyMemberDomains", "compute.restrictVpcPeering", "run.allowedIngress"] :
      contains(keys(module.org_policies.list_policy_names), c)
    ]) && contains(keys(module.org_policies.managed_policy_names), "compute.managed.vmExternalIpAccess")
    error_message = "the org-policy baseline must set resource locations, domain-restricted sharing, external-IP, peering and Cloud Run ingress list constraints."
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
    gcp = merge(var.gcp, {
      enable_control_plane_alerting = false
      alert_notification_emails     = []
    })
  }

  assert {
    condition     = length(module.control_plane_alerting.watched_names) == 0 && module.control_plane_alerting.org_log_route_sink_name == null
    error_message = "enable_control_plane_alerting = false must create no watches and no route sink."
  }
}

run "no_alert_destination_warns" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      alert_notification_emails = []
    })
  }

  expect_failures = [check.control_plane_alerts_have_a_destination]
}

run "containment_denies_mutation_and_tag_scopes_audit_store" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  # Default guardrail_owner_mode = "separate": this stage neither applies nor
  # renders the deny policies (the gcp-guardrails workspace owns them), but it
  # still creates and binds the containment tag they are scoped by.
  assert {
    condition     = length(module.iam_deny.deny_policy_names) == 0 && length(output.guardrail_deny_policy_specs) == 0 && length(output.admin_containment_rules) == 0 && length(module.guardrails) == 0
    error_message = "in separate mode this stage must not build the containment policy or its spec."
  }

  assert {
    condition     = output.containment_tag.key_short_name == "containment" && output.containment_tag.value_short_name == "protected"
    error_message = "the containment tag the gcp-guardrails root looks up must be exposed."
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
    gcp = merge(var.gcp, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]
    })
  }

  expect_failures = [var.gcp]
}

run "dedicated_logging_project_holds_audit_store_and_cmek" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      logging_project_id            = "acme-logging"
      logging_project_number        = "999999999999"
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
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
    gcp = merge(var.gcp, {
      logging_project_id = "acme-logging"
    })
  }

  expect_failures = [var.gcp]
}

# Audit C2: the phase-0 bootstrap SA holds no standing folder-admin rights by
# default; per-stage plan/apply SAs replace the legacy single-identity grants.
run "no_legacy_admin_folder_grants_by_default" {
  command = plan

  assert {
    condition     = length(google_folder_iam_member.terraform_admin_folder_roles) == 0
    error_message = "terraform-admin must not receive folder roles unless enable_legacy_admin_folder_roles = true"
  }
}

run "legacy_admin_folder_grants_opt_in" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_legacy_admin_folder_roles = true
    })
  }

  assert {
    condition     = length(google_folder_iam_member.terraform_admin_folder_roles) > 0
    error_message = "enable_legacy_admin_folder_roles = true must restore the legacy folder grants"
  }
}

# CIS GCP 4.4: OS Login is required org-wide by default, with no exemptions.
run "os_login_enforced_org_wide_by_default" {
  command = plan

  assert {
    condition     = contains(keys(module.org_policies.managed_policy_names), "compute.managed.requireOsLogin")
    error_message = "OS Login must be enforced at the org node by default (managed constraint)."
  }

  assert {
    condition     = length(module.os_login_exemptions) == 0 && length(output.os_login_exempt_environment_keys) == 0
    error_message = "no OS Login folder exemptions by default."
  }
}

run "os_login_folder_exemption" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      os_login_exempt_environment_keys = ["dev"]
    })
  }

  assert {
    condition     = length(output.os_login_exempt_environment_keys) == 1 && contains(output.os_login_exempt_environment_keys, "dev") && contains(keys(module.os_login_exemptions["dev"].managed_policy_names), "compute.managed.requireOsLogin")
    error_message = "an exempt folder must get a folder-level compute.requireOsLogin override."
  }

  assert {
    condition     = contains(keys(module.org_policies.managed_policy_names), "compute.managed.requireOsLogin")
    error_message = "exempting a folder must not drop the org-wide OS Login default."
  }
}

run "os_login_org_enforcement_can_be_disabled" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enforce_os_login                 = false
      os_login_exempt_environment_keys = ["dev"]
    })
  }

  assert {
    condition     = !contains(output.org_policy_constraints, "compute.requireOsLogin") && !contains(output.org_policy_constraints, "compute.managed.requireOsLogin") && length(module.os_login_exemptions) == 0
    error_message = "enforce_os_login = false must drop the org-level constraint and the (now pointless) exemptions."
  }
}

# CIS GCP 2.4-2.11 log metrics ride on control-plane alerting.
run "cis_log_metrics_wired_by_default" {
  command = plan

  assert {
    condition     = length(output.control_plane_cis_log_metric_names) == 8 && output.control_plane_cis_log_metric_names["vpc_firewall_rule_change"] == "cis-vpc_firewall_rule_change"
    error_message = "the org stage must create the 8 CIS 2.4-2.11 log metrics in the alerting project by default."
  }
}

# ── Admin principals: groups only by default ────────────────────────────────

run "standing_admin_is_group_only_by_default" {
  command = plan

  assert {
    condition     = output.org_admin_members == tolist(["group:org-admins@acme.io"]) && output.billing_admin_members == tolist(["group:billing-admins@acme.io"])
    error_message = "standing org/billing admin must be granted to groups only (no user:admin_email / user:break_glass_user) by default."
  }

  assert {
    condition     = length([for m in concat(output.org_admin_members, output.billing_admin_members) : m if startswith(m, "user:")]) == 0
    error_message = "no user: principal may hold standing org or billing admin without the escape hatch."
  }
}

run "user_principals_only_with_break_glass_escape" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      allow_user_principals_for_break_glass = true
    })
  }

  assert {
    condition     = contains(output.org_admin_members, "user:admin@acme.io") && contains(output.org_admin_members, "user:break-glass@acme.io") && contains(output.billing_admin_members, "user:admin@acme.io")
    error_message = "allow_user_principals_for_break_glass must add admin_email / break_glass_user as user principals."
  }
}

# ── VPC-SC: per-environment scoped access policies ──────────────────────────

run "scoped_access_policy_per_environment" {
  command = plan

  variables {
    workload_service_accounts = {
      dev = {
        plan  = "acme-wl-dev-plan@acme-admin-project.iam.gserviceaccount.com"
        apply = "acme-wl-dev-apply@acme-admin-project.iam.gserviceaccount.com"
      }
    }
  }

  assert {
    condition     = sort(keys(google_access_context_manager_access_policy.environment)) == sort(["dev"]) && tolist(google_access_context_manager_access_policy.environment["dev"].scopes) == tolist(["folders/111111111"]) && google_access_context_manager_access_policy.environment["dev"].parent == "organizations/123456789"
    error_message = "each environment folder must get its own access policy scoped to that folder only."
  }

  assert {
    condition     = google_access_context_manager_access_policy_iam_member.environment["dev|apply"].role == "roles/accesscontextmanager.policyEditor" && google_access_context_manager_access_policy_iam_member.environment["dev|apply"].member == "serviceAccount:acme-wl-dev-apply@acme-admin-project.iam.gserviceaccount.com" && google_access_context_manager_access_policy_iam_member.environment["dev|plan"].role == "roles/accesscontextmanager.policyReader"
    error_message = "the environment workload apply SA gets policyEditor (plan SA policyReader) on its OWN scoped policy."
  }

  assert {
    condition     = length(google_access_context_manager_access_policy_iam_member.environment) == 2
    error_message = "no other access-policy grants may be made."
  }
}

run "scoped_access_policies_can_be_disabled" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_scoped_access_policies = false
    })
  }

  assert {
    condition     = length(google_access_context_manager_access_policy.environment) == 0 && length(output.scoped_access_policy_ids) == 0
    error_message = "enable_scoped_access_policies = false must create no scoped policies."
  }
}

# ── projects-apply delegated folder IAM: per folder, never org-wide ─────────

run "projects_delegation_is_bound_per_folder" {
  command = plan

  variables {
    environments = {
      shared = {
        display_name            = "Shared"
        description             = "Shared"
        iam_group_role_bindings = {}
      }
      dev = {
        display_name            = "Development"
        description             = "Development environment"
        iam_group_role_bindings = {}
      }
    }
    projects_apply_service_account  = "acme-projects-apply@acme-admin-project.iam.gserviceaccount.com"
    delegated_workload_folder_roles = ["roles/compute.admin", "roles/run.admin"]
    delegated_network_folder_roles  = ["roles/compute.networkAdmin"]
  }

  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "acme.io", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = {}, folders = { dev = { id = "111111111", name = "folders/111111111", display_name = "Development" }, shared = { id = "222222222", name = "folders/222222222", display_name = "Shared" } } }
  }

  assert {
    condition     = sort(keys(google_folder_iam_member.projects_delegated_folder_iam)) == sort(["dev", "shared"]) && google_folder_iam_member.projects_delegated_folder_iam["dev"].folder == "folders/111111111" && google_folder_iam_member.projects_delegated_folder_iam["shared"].folder == "folders/222222222"
    error_message = "projects-apply folderIamAdmin must be bound on each target folder, not the org node."
  }

  assert {
    condition     = strcontains(google_folder_iam_member.projects_delegated_folder_iam["dev"].condition[0].expression, "'roles/compute.admin'") && !strcontains(google_folder_iam_member.projects_delegated_folder_iam["dev"].condition[0].expression, "networkAdmin") && strcontains(google_folder_iam_member.projects_delegated_folder_iam["shared"].condition[0].expression, "'roles/compute.networkAdmin'") && !strcontains(google_folder_iam_member.projects_delegated_folder_iam["shared"].condition[0].expression, "run.admin")
    error_message = "env folders admit only the workload roles, the shared folder only the network roles."
  }

  assert {
    condition     = sort(keys(google_access_context_manager_access_policy.environment)) == sort(["dev"])
    error_message = "the shared folder must not get a scoped access policy (the hub perimeter lives in the org-wide policy)."
  }
}

# ── Containment: production fails the plan, deny coverage ───────────────────

run "production_without_containment_fails" {
  command = plan

  variables {
    environments = {
      prod = {
        display_name            = "Production"
        description             = "Production environment"
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
  }

  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "acme.io", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = {}, folders = { prod = { id = "333333333", name = "folders/333333333", display_name = "Production" } } }
  }

  expect_failures = [terraform_data.production_requires_admin_containment]

  assert {
    condition     = output.production_environment_keys == tolist(["prod"])
    error_message = "is_production must drive the production environment list."
  }
}

run "explicit_waiver_plans" {
  command = plan

  variables {
    production_containment_waived = true
    environments = {
      prod = {
        display_name            = "Production"
        description             = "Production environment"
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
    gcp = merge(var.gcp, {
      enable_admin_containment = false
    })
  }

  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "acme.io", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = {}, folders = { prod = { id = "333333333", name = "folders/333333333", display_name = "Production" } } }
  }

  assert {
    condition     = output.production_environment_keys == tolist(["prod"])
    error_message = "an explicit enable_admin_containment = false waiver must let a production estate plan."
  }
}

# ── PAM: just-in-time org admin ─────────────────────────────────────────────

run "pam_entitlement_off_by_default" {
  command = plan

  assert {
    condition     = length(google_privileged_access_manager_entitlement.org_admin) == 0
    error_message = "the PAM entitlement must be opt-in."
  }
}

run "pam_entitlement_requires_approval" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_pam          = true
      pam_eligible_groups = ["org-admin-requesters@acme.io"]
      pam_approver_groups = ["org-admin-approvers@acme.io"]
    })
  }

  assert {
    condition     = google_privileged_access_manager_entitlement.org_admin[0].parent == "organizations/123456789" && google_privileged_access_manager_entitlement.org_admin[0].max_request_duration == "3600s"
    error_message = "the entitlement must be at the org node with a 1h maximum grant."
  }

  assert {
    condition     = google_privileged_access_manager_entitlement.org_admin[0].eligible_users[0].principals == toset(["group:org-admin-requesters@acme.io"]) && google_privileged_access_manager_entitlement.org_admin[0].approval_workflow[0].manual_approvals[0].steps[0].approvers[0].principals == toset(["group:org-admin-approvers@acme.io"])
    error_message = "eligible users and approvers must be the configured groups."
  }

  assert {
    condition     = google_privileged_access_manager_entitlement.org_admin[0].privileged_access[0].gcp_iam_access[0].role_bindings[0].role == "roles/resourcemanager.organizationAdmin"
    error_message = "the entitlement must grant organizationAdmin just in time."
  }
}

# Legacy single-owner mode: this stage applies the deny policy itself.
run "containment_applied_in_stage_in_organization_mode" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      guardrail_owner_mode          = "organization"
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  assert {
    condition     = contains(module.iam_deny.deny_policy_names, "contain-admin-identity")
    error_message = "guardrail_owner_mode = organization must apply the contain-admin-identity deny policy in this stage."
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
        "accesscontextmanager.googleapis.com/accessLevels.update",
        "accesscontextmanager.googleapis.com/accessLevels.delete",
        "accesscontextmanager.googleapis.com/accessLevels.replaceAll",
        "accesscontextmanager.googleapis.com/policies.setIamPolicy",
      ] : contains(output.admin_containment_rules[0].denied_permissions, p)
    ]) && !output.admin_containment_rules[0].tag_scoped
    error_message = "rule 1 must deny sink/exclusion/perimeter mutation org-wide (unconditioned)."
  }

  assert {
    condition = alltrue([
      for p in [
        "storage.googleapis.com/buckets.delete",
        "storage.googleapis.com/buckets.setIamPolicy",
        "storage.googleapis.com/buckets.deleteTagBinding",
        "storage.googleapis.com/objects.delete",
        "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
        "cloudkms.googleapis.com/cryptoKeyVersions.update",
        "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
        "storage.googleapis.com/buckets.update",
        "cloudkms.googleapis.com/keyRings.setIamPolicy",
        "logging.googleapis.com/buckets.update",
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
}

run "containment_tags_the_log_analytics_bucket" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  assert {
    condition     = length(google_tags_location_tag_binding.containment_log_analytics_bucket) == 1
    error_message = "the audit Log Analytics bucket must carry the containment tag."
  }
}

run "legacy_constraints_when_managed_not_preferred" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      prefer_managed_constraints = false
    })
  }

  assert {
    condition     = contains(keys(module.org_policies.boolean_policy_names), "iam.disableServiceAccountKeyCreation") && length(module.org_policies.managed_policy_names) == 0
    error_message = "prefer_managed_constraints = false must keep the legacy baseline."
  }
}

run "log_analytics_on_by_default" {
  command = plan

  assert {
    condition     = module.audit_logs.log_analytics_bucket_location == "europe-west1"
    error_message = "the audit Log Analytics bucket must be created by default."
  }

  assert {
    condition     = length(google_logging_organization_settings.this) == 0 && length(module.automation_boundary) == 0
    error_message = "logging org settings and the principal access boundary must be opt-in."
  }
}

run "logging_org_settings_and_boundary_opt_in" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      enable_logging_organization_settings = true
      enable_principal_access_boundary     = true
      enable_admin_containment             = true
      containment_exempt_principals        = ["principalSet://goog/group/break-glass@acme.io"]
      guardrail_owner_mode                 = "organization"
    })
  }

  assert {
    condition     = google_logging_organization_settings.this[0].storage_location == "europe-west1" && google_logging_organization_settings.this[0].disable_default_sink == false
    error_message = "logging org settings must default the storage location to default_region and keep the default sink."
  }

  assert {
    condition     = module.automation_boundary[0].bound_principal_sets["admin"] == "//cloudresourcemanager.googleapis.com/projects/acme-admin-project"
    error_message = "the principal access boundary must bind every SA in the admin project."
  }

  assert {
    condition     = contains(output.admin_containment_rules[0].denied_permissions, "iam.googleapis.com/principalaccessboundarypolicies.unbind")
    error_message = "with containment on, the automation boundary must not be unbindable by the automation identity."
  }
}

# The gcloud spec now comes from the gcp-guardrails root (stage guardrails).
# In separate mode this stage renders nothing; in the legacy organization mode
# the spec output still mirrors what this stage applies.
run "guardrail_spec_empty_in_separate_mode" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      iam_deny_policies = [
        {
          name = "deny-sa-keys"
          rules = [
            {
              denied_principals  = ["principalSet://goog/public:all"]
              denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"]
            },
          ]
        },
      ]
    })
  }

  # The ignored input is flagged, not silently dropped.
  expect_failures = [check.iam_deny_policies_belong_to_guardrails]

  assert {
    condition     = length(output.guardrail_deny_policy_specs) == 0 && length(module.iam_deny.deny_policy_names) == 0
    error_message = "in separate mode user deny policies belong to gcp-guardrails: no spec and nothing applied here."
  }
}

run "guardrail_spec_and_apply_in_organization_mode" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      guardrail_owner_mode = "organization"
      iam_deny_policies = [
        {
          name = "deny-sa-keys"
          rules = [
            {
              denied_principals  = ["principalSet://goog/public:all"]
              denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"]
              denial_condition   = { title = "t", expression = "resource.matchTag('123/env', 'prod')" }
            },
          ]
        },
      ]
    })
  }

  assert {
    condition     = jsondecode(output.guardrail_deny_policy_specs["deny-sa-keys"]).rules[0].denyRule.denialCondition.title == "t" && contains(module.iam_deny.deny_policy_names, "deny-sa-keys")
    error_message = "organization mode must apply user deny policies in this stage and still render their spec."
  }
}

# Bare regions become in:<region>-locations so zonal resources are allowed;
# value groups pass through unchanged.
run "resource_locations_use_region_value_groups" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      allowed_regions = ["europe-west2", "in:eu-locations"]
    })
  }

  assert {
    condition     = jsonencode(one([for p in local.effective_list_policies : p if p.constraint == "gcp.resourceLocations"]).allowed_values) == jsonencode(["in:europe-west2-locations", "in:eu-locations"])
    error_message = "bare regions must render as in:<region>-locations value groups."
  }
}

# WIF provider creation is limited to the trusted issuers; AWS-account
# federation is denied unless listed.
run "workload_identity_federation_restricted" {
  command = plan

  assert {
    condition = (
      one([for p in local.effective_list_policies : p if p.constraint == "iam.workloadIdentityPoolProviders"]).allowed_values == tolist(["https://app.terraform.io", "https://token.actions.githubusercontent.com"]) &&
      one([for p in local.effective_list_policies : p if p.constraint == "iam.workloadIdentityPoolAwsAccounts"]).deny_all == true &&
      contains(local.default_boolean_constraints, "compute.disableVpcExternalIpv6")
    )
    error_message = "the baseline must allow-list WIF issuers, deny AWS-account federation and disable external IPv6."
  }
}

# org_policy_overrides: change, drop and add constraints without forking.
run "org_policy_overrides_merge_over_baseline" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      org_policy_overrides = {
        "compute.requireShieldedVm"                    = { enforce = false }
        "cloudfunctions.requireVPCConnector"           = { disabled = true }
        "compute.restrictVpcPeering"                   = { allow_all = true }
        "compute.restrictLoadBalancerCreationForTypes" = { allowed_values = ["INTERNAL_HTTP_HTTPS"] }
      }
    })
  }

  assert {
    condition = (
      one([for p in local.effective_boolean_policies : p if p.constraint == "compute.requireShieldedVm"]).enforce == false &&
      length([for p in local.effective_boolean_policies : p if p.constraint == "cloudfunctions.requireVPCConnector"]) == 0 &&
      one([for p in local.effective_list_policies : p if p.constraint == "compute.restrictVpcPeering"]).allow_all == true &&
      one([for p in local.effective_list_policies : p if p.constraint == "compute.restrictLoadBalancerCreationForTypes"]).allowed_values == tolist(["INTERNAL_HTTP_HTTPS"])
    )
    error_message = "overrides must set enforce, drop disabled constraints, replace list values and add new constraints."
  }
}

# WIF tenant pins become a custom DENY constraint on provider create/update.
run "wif_tenant_pin_custom_constraint" {
  command = plan

  variables {
    wif_tenant_pins = {
      tfc_organization = "acme-tfc"
      github_owner_ids = ["123456"]
    }
  }

  assert {
    condition = (
      one([for c in local.wif_tenant_constraints : c if c.name == "custom.wifProviderTenantPinned"]).resource_types == ["iam.googleapis.com/WorkloadIdentityPoolProvider"] &&
      strcontains(one(local.wif_tenant_constraints).condition, "matches(\"^assertion[.]terraform_organization_name == 'acme-tfc'( && [^|?]*)?$\")") &&
      strcontains(one(local.wif_tenant_constraints).condition, "(resource.oidc.issuerUri.startsWith('https://token.actions.githubusercontent.com') && !(resource.attributeCondition == \"assertion.repository_owner_id == \\\"123456\\\"\"))") &&
      !strcontains(one(local.wif_tenant_constraints).condition, "repository_owner_id == '") &&
      !strcontains(one(local.wif_tenant_constraints).condition, ".contains(")
    )
    error_message = "tenant pins must render a DENY custom constraint referencing the TFC org and GitHub owner IDs."
  }
}

run "no_wif_tenant_constraint_without_pins" {
  command = plan

  assert {
    condition     = length(local.wif_tenant_constraints) == 0
    error_message = "without pins no tenant constraint is created."
  }
}

# The tenant pin is checked against a bypass corpus with Terraform's own RE2
# (the engine CEL matches() uses): real conditions this repo renders must
# pass, and every OR / ternary / negation / reorder trick must fail.
run "wif_tenant_pin_bypass_corpus" {
  command = plan

  variables {
    wif_tenant_pins = {
      tfc_organization = "acme"
      github_owner_ids = ["123"]
    }
  }

  assert {
    condition = alltrue([
      for c in [
        "assertion.terraform_organization_name == 'acme' && assertion.terraform_organization_id == 'org-x' && assertion.terraform_run_phase in ['plan', 'apply']",
        "assertion.terraform_organization_name == 'acme' && assertion.terraform_run_phase in ['plan', 'apply']",
      ] : can(regex(local.wif_tfc_pattern, c))
    ])
    error_message = "the conditions the bootstrap TFC pool renders must satisfy the pin."
  }

  assert {
    condition = !anytrue([
      for c in [
        "assertion.terraform_organization_name != 'acme'",
        "assertion.terraform_organization_name == 'acme' || true",
        "assertion.terraform_organization_name == 'acme' && true || true",
        "assertion.terraform_organization_name == 'acme' && true ? true : true",
        "assertion.terraform_organization_name == 'acme' && (true) ? true : true",
        "true && assertion.terraform_organization_name == 'acme'",
        "assertion.terraform_organization_name == 'acmeevil'",
        "assertion.terraform_organization_name == 'acme'\n|| true",
      ] : can(regex(local.wif_tfc_pattern, c))
    ])
    error_message = "no OR / ternary / reorder / prefix trick may satisfy the TFC tenant pin."
  }

  # GitHub: an exact match on the canonical condition. Only the string the
  # modules render is accepted; every tail, quote style or operator is not.
  assert {
    condition     = local.wif_github_conditions == ["assertion.repository_owner_id == \"123\""]
    error_message = "the GitHub tenant pin must be the single canonical condition per owner ID."
  }

  assert {
    condition     = contains(local.wif_github_conditions, "assertion.repository_owner_id == \"123\"")
    error_message = "the canonical condition app-services, bootstrap and the workload-identity primitive render must satisfy the pin."
  }

  assert {
    condition = !anytrue([
      for c in [
        # The paren-in-literal bypass the old structural regex admitted.
        "assertion.repository_owner_id == \"123\" && (assertion.ref == \"x)\" || true || (\"\" == \"\")",
        "assertion.repository_owner_id == \"123\" && true",
        "assertion.repository_owner_id == \"123\" && ((assertion.repository_id == \"9\"))",
        "assertion.repository_owner_id == '123'",
        "assertion.repository_owner_id == '123' && assertion.repository_id == '9' && assertion.ref == 'refs/heads/main'",
        "assertion.repository_owner_id == \"123\" || true",
        "assertion.repository_owner_id == \"123\" && (true) || (true)",
        "assertion.repository_owner_id == \"123\" && (true) ? true : true",
        "assertion.repository_owner_id == \"123\" && true ? true : true",
        "assertion.repository_owner_id == \"1234\"",
        "assertion.repository_owner_id == \"12\"",
        "assertion.repository_owner_id != \"123\"",
        "assertion.repository_owner_id == \"123' && x\" == false",
        "assertion.repository_owner_id == '123\" && x' == false",
        "assertion.repository_owner_id == \"123' && x\" != true",
        "assertion.repository_owner_id == \"123' && x\" in [false]",
        "assertion.repository_owner_id == '123' == false",
        " assertion.repository_owner_id == \"123\"",
        "assertion.repository_owner_id == \"123\" ",
        "assertion.repository_owner_id==\"123\"",
        "\"123\" == assertion.repository_owner_id",
      ] : contains(local.wif_github_conditions, c)
    ])
    error_message = "no tail, OR, ternary, quote or reorder trick may satisfy the GitHub owner pin."
  }
}

# The constraint condition must fit GCP's 1000-character custom-constraint
# limit with three GitHub owner IDs plus the TFC clause.
run "wif_tenant_constraint_fits_condition_limit" {
  command = plan

  variables {
    wif_tenant_pins = {
      tfc_hostname     = "app.eu.terraform.io"
      tfc_organization = "acme-platform-engineering-production-org"
      github_owner_ids = ["12345678901", "23456789012", "34567890123"]
    }
  }

  assert {
    condition     = alltrue([for c in local.wif_tenant_constraints : length(c.condition) <= 1000]) && length(local.wif_tenant_constraints) >= 1
    error_message = "every custom.wifProviderTenantPinned condition must be at most 1000 characters."
  }

  assert {
    condition     = alltrue([for id in ["12345678901", "23456789012", "34567890123"] : strcontains(join(" ", [for c in local.wif_tenant_constraints : c.condition]), "assertion.repository_owner_id == \\\"${id}\\\"")])
    error_message = "every GitHub owner ID must appear in the tenant constraint."
  }
}

# The WIF tenant pin is enforced, not just defined.
run "wif_tenant_pin_is_enforced" {
  command = plan

  variables {
    wif_tenant_pins = { tfc_organization = "acme" }
  }

  assert {
    condition     = one(local.wif_tenant_constraints).enforcement == "enforce" && module.org_policies.custom_constraint_policies["custom.wifProviderTenantPinned"] == "enforce"
    error_message = "custom.wifProviderTenantPinned must be enforced by default."
  }
}

# The tags module exposes namespaced IDs (tagKeys/<n>, tagValues/<n>); the
# containment bindings and the legacy in-stage deny condition use them as is.
run "containment_uses_namespaced_tag_ids" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      guardrail_owner_mode          = "organization"
      enable_admin_containment      = true
      containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
    })
  }

  override_module {
    target = module.tags
    outputs = {
      tag_keys   = { "environment" = "tagKeys/111", "containment" = "tagKeys/444" }
      tag_values = { "environment-dev" = "tagValues/999", "containment-protected" = "tagValues/555" }
    }
  }

  assert {
    condition     = alltrue([for b in google_tags_location_tag_binding.containment_buckets : b.tag_value == "tagValues/555"]) && google_tags_location_tag_binding.containment_audit_keyring[0].tag_value == "tagValues/555"
    error_message = "containment tag bindings must reference tagValues/<n>."
  }

  assert {
    condition     = module.guardrails[0].deny_policies[0].rules[1].denial_condition.expression == "resource.matchTagId('tagKeys/444', 'tagValues/555')"
    error_message = "the audit-store deny condition must match the namespaced tag IDs."
  }
}

run "budget_channels_over_limit_fails" {
  command = plan

  variables {
    monthly_budget_amount        = 100
    budget_notify_alert_channels = true
    gcp = merge(var.gcp, {
      alert_notification_emails = ["a@acme.io", "b@acme.io", "c@acme.io", "d@acme.io", "e@acme.io", "f@acme.io"]
    })
  }

  expect_failures = [terraform_data.budget_channel_limit]
}

# Budget alerts can reuse the control-plane email channels (opt-in).
run "budget_channels_opt_in" {
  command = plan

  variables {
    monthly_budget_amount        = 100
    budget_notify_alert_channels = true
  }

  assert {
    condition     = length(module.org_budget) == 1 && length(module.org_budget[0].budget_name) > 0
    error_message = "the org budget must plan with the control-plane channels attached."
  }
}
