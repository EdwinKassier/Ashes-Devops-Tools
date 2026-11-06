# Plan assertions for the iam/principal-access-boundary module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  organization_id  = "123456789"
  project_bindings = { admin = "acme-admin-abcd1234" }
}

run "boundary_defaults_to_the_organization" {
  command = plan

  assert {
    condition     = length(output.boundary_resources) == 1 && contains(google_iam_principal_access_boundary_policy.this.details[0].rules[0].resources, "//cloudresourcemanager.googleapis.com/organizations/123456789") && google_iam_principal_access_boundary_policy.this.details[0].rules[0].effect == "ALLOW"
    error_message = "With no allowed_resources the boundary must be this organization."
  }

  assert {
    condition     = google_iam_principal_access_boundary_policy.this.details[0].enforcement_version == "1" && google_iam_principal_access_boundary_policy.this.location == "global"
    error_message = "The enforcement version must be pinned by default and the policy global."
  }
}

run "project_principal_set_is_bound" {
  command = plan

  assert {
    condition     = google_iam_projects_policy_binding.this["admin"].target[0].principal_set == "//cloudresourcemanager.googleapis.com/projects/acme-admin-abcd1234" && google_iam_projects_policy_binding.this["admin"].policy_kind == "PRINCIPAL_ACCESS_BOUNDARY"
    error_message = "Every SA in the bound project must be targeted with a PAB binding."
  }

  assert {
    condition     = google_iam_projects_policy_binding.this["admin"].policy_binding_id == "automation-boundary-admin" && google_iam_projects_policy_binding.this["admin"].project == "acme-admin-abcd1234"
    error_message = "Binding IDs must be <policy_id>-<key> in the bound project."
  }
}

run "explicit_allowed_resources" {
  command = plan

  variables {
    allowed_resources = ["//cloudresourcemanager.googleapis.com/folders/42", "//cloudresourcemanager.googleapis.com/projects/acme-shared"]
  }

  assert {
    condition     = length(output.boundary_resources) == 2 && contains(output.boundary_resources, "//cloudresourcemanager.googleapis.com/folders/42")
    error_message = "allowed_resources must replace the org default."
  }
}
