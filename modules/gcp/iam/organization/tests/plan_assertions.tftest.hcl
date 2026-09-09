# Plan assertions for the iam/organization module: verify org-level IAM member
# bindings are planned for the caller-supplied members with the expected roles.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  domain                = "example.com"
  project_id            = "mock-project"
  org_admin_members     = ["group:org-admins@example.com"]
  billing_admin_members = ["group:billing-admins@example.com"]
}

run "org_role_bindings_planned" {
  command = plan

  assert {
    condition     = google_organization_iam_member.org_admins["group:org-admins@example.com"].role == "roles/resourcemanager.organizationAdmin"
    error_message = "Org admin members must be granted roles/resourcemanager.organizationAdmin."
  }

  assert {
    condition     = google_organization_iam_member.billing_admins["group:billing-admins@example.com"].role == "roles/billing.admin"
    error_message = "Billing admin members must be granted roles/billing.admin."
  }
}
