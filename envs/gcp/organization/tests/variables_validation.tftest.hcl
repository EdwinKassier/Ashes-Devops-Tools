# Input validation for the gcp-organization root. Same mocks and overrides as
# config.tftest.hcl, so a run fails only on the validation it names.

mock_provider "google" {}

mock_provider "google-beta" {}

mock_provider "random" {}

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
        organization_apply_grantable_roles = [
          "roles/billing.admin", "roles/cloudkms.cryptoKeyEncrypterDecrypter", "roles/logging.bucketWriter",
          "roles/logging.logWriter", "roles/storage.objectCreator",
        ]
        organization_admin_members = ["group:gcp-org-admins@acme.io"]
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

# CMP-2: a listed framework sets a floor (hipaa: 2190 days).
run "retention_below_framework_floor_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
    audit_log_retention_days = 365
  }

  expect_failures = [var.audit_log_retention_days]
}

run "retention_zero_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    audit_log_retention_days = 0
  }

  expect_failures = [var.audit_log_retention_days]
}

# Every bucket this root locked before audit_log_retention_days was a root
# input is locked at 365 days, and GCS never shortens a locked retention
# period. With the lock on, a lower value is refused at plan, not at apply.
run "locked_bucket_below_365_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-audit-lock.yaml"
    audit_log_retention_days = 364
  }

  expect_failures = [var.audit_log_retention_days]
}

run "locked_bucket_at_365_plans" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-audit-lock.yaml"
    audit_log_retention_days = 365
  }

  assert {
    condition     = local.gcp.enable_audit_bucket_lock && module.organization.audit_log_retention_days == 365
    error_message = "the lock at 365 days must plan."
  }
}

# Without the lock a short retention stays allowed (no framework listed).
run "unlocked_short_retention_plans" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    audit_log_retention_days = 30
  }

  assert {
    condition     = module.organization.audit_log_retention_days == 30
    error_message = "an unlocked bucket may use any retention of 1 day or more."
  }
}
