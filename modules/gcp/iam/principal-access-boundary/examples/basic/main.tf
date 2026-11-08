# Example: an organization-level principal access boundary bound to every
# service account in the landing-zone automation and CI projects. Those
# principals can use their permissions only inside this organization, so a
# stolen automation token cannot act on resources in another organization.
# The enforcement version is pinned so behaviour does not shift when Google
# extends coverage.
#
# Validate on a non-production organization first. The applying identity
# needs roles/iam.principalAccessBoundaryAdmin at the organization and
# resourcemanager.projects.createPolicyBinding on each bound project.
# Replace the placeholder organization and project IDs before use.
#
# Run `terraform init && terraform validate` here.

module "automation_boundary" {
  source = "../../"

  organization_id     = "123456789012"
  policy_id           = "automation-boundary"
  display_name        = "Landing zone automation boundary"
  enforcement_version = "1"

  # Empty means "this organization only"; listed explicitly for clarity.
  allowed_resources = [
    "//cloudresourcemanager.googleapis.com/organizations/123456789012",
  ]

  project_bindings = {
    admin = "my-admin-project"
    ci    = "my-ci-project"
  }
}
