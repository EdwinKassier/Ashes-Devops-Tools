# Variable validation tests for the iam/service_account module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  account_id   = "my-service-account"
  display_name = "My Service Account"
}

run "accepts_valid_inputs" {
  command = plan
}

# ── account_id ─────────────────────────────────────────────────────────────────

run "accepts_minimum_length_account_id" {
  command = plan
  variables {
    account_id = "abcdef"
  }
}

run "accepts_maximum_length_account_id" {
  command = plan
  variables {
    account_id = "a23456789012345678901234567890"
  }
}

run "rejects_account_id_too_short" {
  command         = plan
  expect_failures = [var.account_id]
  variables {
    account_id = "ab"
  }
}

run "rejects_account_id_with_uppercase" {
  command         = plan
  expect_failures = [var.account_id]
  variables {
    account_id = "MyServiceAccount"
  }
}

run "rejects_account_id_starting_with_number" {
  command         = plan
  expect_failures = [var.account_id]
  variables {
    account_id = "1service-account"
  }
}

# ── project_roles ──────────────────────────────────────────────────────────────

run "accepts_predefined_project_role" {
  command = plan
  variables {
    project_roles = ["roles/storage.objectViewer"]
  }
}

run "accepts_custom_project_role" {
  command = plan
  variables {
    project_roles = ["projects/mock-project/roles/customRole"]
  }
}

run "rejects_basic_org_role_in_project_roles" {
  command         = plan
  expect_failures = [var.project_roles]
  variables {
    project_roles = ["organizations/123/roles/custom"]
  }
}

# ── impersonation_members ──────────────────────────────────────────────────────

run "accepts_valid_impersonation_members" {
  command = plan
  variables {
    impersonation_members = [
      "user:admin@example.com",
      "group:eng@example.com",
      "serviceAccount:runner@mock-project.iam.gserviceaccount.com"
    ]
  }
}

run "rejects_invalid_impersonation_member_prefix" {
  command         = plan
  expect_failures = [var.impersonation_members]
  variables {
    impersonation_members = ["admin@example.com"]
  }
}

# ── workload_identity_members ──────────────────────────────────────────────────

run "accepts_principal_set_workload_identity_member" {
  command = plan
  variables {
    workload_identity_members = ["principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/pool/attribute.repository/my-org/my-repo"]
  }
}

run "accepts_service_account_workload_identity_member" {
  command = plan
  variables {
    workload_identity_members = ["serviceAccount:mock-project.svc.id.goog[default/my-ksa]"]
  }
}

run "rejects_invalid_workload_identity_member_prefix" {
  command         = plan
  expect_failures = [var.workload_identity_members]
  variables {
    workload_identity_members = ["user:someone@example.com"]
  }
}
