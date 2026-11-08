# Example: VPC Service Controls perimeter protecting BigQuery and Cloud Storage
# in a single project. Starts in dry-run mode so violations are logged before
# enforcement. Flip enable_dry_run to false once the policy is validated.
#
# Prerequisites:
#   - An existing Access Policy for the organization (or set create_access_policy
#     = true to create a new one).
#   - The project number (not ID) of every project that should be inside the perimeter.

module "vpc_sc" {
  source = "../../modules/gcp/network/vpc-sc"

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

  # Allow CI/CD from one GitHub repository federated through the admin
  # project's Workload Identity pool.
  #
  # - identities: the federated principals (never ANY_IDENTITY for CI). A WIF
  #   principalSet only matches when the job calls the API with its federated
  #   token. If the job impersonates a service account instead, list
  #   "serviceAccount:<sa-email>" here.
  # - sources: where the request comes from. Only an access level ("*" = any
  #   network origin) or a project / folder / org / VPC network is valid; a WIF
  #   pool is not a source. GitHub-hosted runners call from the internet, so
  #   "*" is used here; prefer an IP-based access level for self-hosted runners.
  # - resources: required; the perimeter projects the rule opens
  #   ("projects/<number>", or "*" for every project in the perimeter).
  ingress_policies = [
    {
      identity_type = null
      identities = [
        # Pinned to one repo AND ref (attribute.repo_ref, mapped by modules/gcp/iam/workload-identity).
        # attribute.repository_id alone would trust every branch of the repo.
        "principalSet://iam.googleapis.com/projects/555666777888/locations/global/workloadIdentityPools/github-pool/attribute.repo_ref/123456789/refs/heads/main",
      ]
      sources = [
        {
          access_level = "*"
          resource     = null
        }
      ]
      resources = ["projects/111222333444"]
      operations = [
        # Every method, stated explicitly; narrow to the methods CI actually calls.
        { service_name = "bigquery.googleapis.com", method_selectors = [{ method = "*" }] },
        { service_name = "storage.googleapis.com", method_selectors = [{ method = "*" }] },
      ]
    }
  ]

  egress_policies = []

  # Start in dry-run: violations are logged but not blocked.
  enable_dry_run = true
}
