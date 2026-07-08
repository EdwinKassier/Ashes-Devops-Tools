# Regression test for the Terraform admin service account's additive org-level
# IAM roles.
#
# google_organization_iam_member.terraform_admin_standard_org_roles is a
# for_each over a static, non-empty list of roles, so it always plans at least
# one binding. This asserts the bindings are (a) actually planned, (b) scoped
# to the correct org_id, and (c) bound to the terraform_admin_sa service
# account identity — not a hardcoded or wrong principal.
#
# override_module is required for module.terraform_admin_sa because its
# service account email is an apply-time value used elsewhere as a for_each
# key (see variables_validation.tftest.hcl for the same requirement).

mock_provider "google" {}
mock_provider "random" {}

variables {
  project_prefix   = "mock-org"
  org_id           = "123456789"
  billing_account  = "ABCDEF-123456-789012"
  admin_email      = "admin@example.com"
  github_org       = "my-org"
  github_repo      = "my-repo"
  tfc_organization = "my-tfc-org"
  enable_tfc_oidc  = false
  tfc_workspaces   = []
}

run "terraform_admin_gets_additive_standard_org_roles" {
  command = plan

  override_module {
    target = module.terraform_admin_sa
    outputs = {
      email                 = "terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
      name                  = "projects/mock-org-admin-abcd1234/serviceAccounts/terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
      unique_id             = "123456789012345678901"
      member                = "serviceAccount:terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
      project_roles         = []
      impersonation_members = []
    }
  }

  assert {
    # length check first — alltrue([]) is vacuously true (see CONTRIBUTING.md Testing).
    condition = length(google_organization_iam_member.terraform_admin_standard_org_roles) > 0 && alltrue([
      for m in google_organization_iam_member.terraform_admin_standard_org_roles :
      m.org_id == "123456789" && m.member == "serviceAccount:terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
    ])
    error_message = "at least one standard org role must be planned, scoped to var.org_id, and bound to the terraform_admin_sa identity (additive google_organization_iam_member, not a policy resource)"
  }

  assert {
    condition     = contains([for m in google_organization_iam_member.terraform_admin_standard_org_roles : m.role], "roles/compute.xpnAdmin")
    error_message = "the Shared VPC admin role (roles/compute.xpnAdmin) must be among the granted standard org roles"
  }
}
