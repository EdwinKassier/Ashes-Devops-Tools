# Example: VPC Service Controls perimeter protecting BigQuery and Cloud Storage
# in a single project. Starts in dry-run mode so violations are logged before
# enforcement. Flip enable_dry_run to false once the policy is validated.
#
# Prerequisites:
#   - An existing Access Policy for the organization (or set create_access_policy
#     = true to create a new one).
#   - The project number (not ID) of every project that should be inside the perimeter.

module "vpc_sc" {
  source = "../../modules/network/vpc-sc"

  organization_id = "organizations/123456789"

  # Use an existing access policy (recommended for shared orgs).
  # access_policy_name must be the bare numeric ID — do NOT include the "accessPolicies/" prefix.
  # To create a new one, set create_access_policy = true instead.
  create_access_policy = false
  access_policy_name   = "1234567890"

  perimeter_name  = "prod_perimeter"
  perimeter_title = "Production Data Perimeter"
  description     = "Protects BigQuery and Cloud Storage in the production project"

  # Bare numeric project numbers (NOT IDs, NOT "projects/NNN" format).
  # Get the number with: gcloud projects describe <id> --format='value(projectNumber)'
  protected_projects = ["111222333444"]

  restricted_services = [
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
  ]

  # Allow CI/CD from the admin project's Workload Identity pool.
  ingress_policies = [
    {
      identity_type = "ANY_IDENTITY"
      identities    = null
      sources = [
        {
          access_level = null
          resource     = "//iam.googleapis.com/projects/555666777888/locations/global/workloadIdentityPools/github-pool"
        }
      ]
      resources = null
      operations = [
        { service_name = "bigquery.googleapis.com", method_selectors = null },
        { service_name = "storage.googleapis.com", method_selectors = null },
      ]
    }
  ]

  egress_policies = []

  # Start in dry-run: violations are logged but not blocked.
  enable_dry_run = true
}

