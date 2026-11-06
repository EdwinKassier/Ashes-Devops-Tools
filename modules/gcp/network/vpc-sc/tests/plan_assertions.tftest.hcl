# Plan assertions for the vpc-sc module: verify the regular service perimeter is
# planned with the caller-supplied title, and that dry-run wiring is honored.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  organization_id    = "organizations/123456789"
  perimeter_name     = "test_perimeter"
  perimeter_title    = "Test Perimeter"
  access_policy_name = "1234567890"
}

run "regular_perimeter_planned_with_title" {
  command = plan

  assert {
    condition     = length(google_access_context_manager_service_perimeter.perimeter) == 1
    error_message = "A regular (PERIMETER_TYPE_REGULAR) perimeter must be planned by default."
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].title == var.perimeter_title
    error_message = "Perimeter title must be the caller-supplied perimeter_title."
  }
}

run "dry_run_toggles_explicit_dry_run_spec" {
  command = plan

  variables {
    enable_dry_run = true
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].use_explicit_dry_run_spec == true
    error_message = "enable_dry_run = true must set use_explicit_dry_run_spec on the perimeter."
  }
}

# ── SOTA M: enforced status + staged dry-run spec ──────────────────────────────

run "enforced_without_overrides_has_no_spec" {
  command = plan

  variables {
    enable_dry_run      = false
    restricted_services = ["storage.googleapis.com"]
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].use_explicit_dry_run_spec == false
    error_message = "An enforced perimeter without dry_run_* overrides must not use an explicit dry-run spec (backward compatible)."
  }

  assert {
    condition     = length(google_access_context_manager_service_perimeter.perimeter[0].status) == 1 && length(google_access_context_manager_service_perimeter.perimeter[0].spec) == 0
    error_message = "An enforced perimeter without overrides must render status only."
  }
}

run "enforced_with_dry_run_override_stages_spec" {
  command = plan

  variables {
    enable_dry_run              = false
    restricted_services         = ["storage.googleapis.com"]
    dry_run_restricted_services = ["storage.googleapis.com", "bigquery.googleapis.com"]
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].use_explicit_dry_run_spec == true
    error_message = "A dry_run_* override on an enforced perimeter must enable the explicit dry-run spec."
  }

  assert {
    condition     = toset(google_access_context_manager_service_perimeter.perimeter[0].status[0].restricted_services) == toset(["storage.googleapis.com"])
    error_message = "status must keep enforcing restricted_services."
  }

  assert {
    condition     = toset(google_access_context_manager_service_perimeter.perimeter[0].spec[0].restricted_services) == toset(["storage.googleapis.com", "bigquery.googleapis.com"])
    error_message = "spec must stage dry_run_restricted_services."
  }

  assert {
    condition     = output.enforced && output.dry_run_spec_staged
    error_message = "outputs must report an enforced perimeter with a staged dry-run spec."
  }
}

run "pure_dry_run_has_spec_only" {
  command = plan

  variables {
    enable_dry_run      = true
    restricted_services = ["storage.googleapis.com"]
  }

  assert {
    condition     = length(google_access_context_manager_service_perimeter.perimeter[0].status) == 0 && length(google_access_context_manager_service_perimeter.perimeter[0].spec) == 1
    error_message = "enable_dry_run = true must keep the legacy behaviour: spec only, nothing enforced."
  }

  assert {
    condition     = !output.enforced && !output.dry_run_spec_staged
    error_message = "a pure dry-run perimeter is neither enforced nor 'staged'."
  }
}

# The module reads optional() attributes directly (no try() wrappers): unset
# attributes take their declared defaults and minimal policy objects still plan.
run "optional_attributes_take_declared_defaults" {
  command = plan

  variables {
    access_levels = [
      {
        name       = "corp_ips"
        title      = "Corporate IPs"
        conditions = [{ ip_subnetworks = ["203.0.113.0/24"] }]
      }
    ]
    ingress_policies = [
      {
        identity_type = "ANY_IDENTITY"
        operations    = [{ service_name = "storage.googleapis.com" }]
      }
    ]
    egress_policies = [
      {
        identity_type = "ANY_IDENTITY"
        resources     = ["*"]
      }
    ]
  }

  assert {
    condition     = google_access_context_manager_access_level.levels["corp_ips"].basic[0].combining_function == "AND" && google_access_context_manager_access_level.levels["corp_ips"].basic[0].conditions[0].negate == false
    error_message = "unset combining_function / negate must fall back to their optional() defaults (AND / false)."
  }

  assert {
    condition     = length(google_access_context_manager_access_level.levels["corp_ips"].basic[0].conditions[0].device_policy) == 0
    error_message = "an unset device_policy must render no device_policy block."
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].status[0].ingress_policies[0].ingress_to[0].operations[0].service_name == "storage.googleapis.com" && length(google_access_context_manager_service_perimeter.perimeter[0].status[0].ingress_policies[0].ingress_from[0].sources) == 0
    error_message = "a minimal ingress policy must plan with its operations and no sources."
  }
}
