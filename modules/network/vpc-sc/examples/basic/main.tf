# Example: VPC Service Controls perimeter protecting BigQuery and Cloud Storage.
#
# VPC-SC prevents data exfiltration by restricting which identities and networks
# can access GCP APIs. This example creates a dry-run (enforced = false) perimeter
# so you can review violations in Cloud Audit Logs before enforcing.
#
# Replace all locals with real values or data sources from remote state.

locals {
  # Organization and project identifiers
  organization_id = "organizations/123456789012"

  # Existing access policy (only one per organization is allowed).
  # Get yours with: gcloud access-context-manager policies list --organization=<ID>
  access_policy_name = "1234567890"

  # Project numbers (NOT IDs) to protect. Get them with:
  #   gcloud projects describe <project-id> --format='value(projectNumber)'
  protected_project_numbers = [
    "111111111111", # data-platform project
    "222222222222", # ml-pipeline project
  ]

  # Corporate egress IP range to allow access from (CIDR notation)
  corp_ip_range = "203.0.113.0/24"
}

module "data_perimeter" {
  source = "../../"

  organization_id      = local.organization_id
  create_access_policy = false
  access_policy_name   = local.access_policy_name

  perimeter_name  = "data_protection_perimeter"
  perimeter_title = "Data Protection Perimeter"
  description     = "Prevents exfiltration of BigQuery and GCS data"

  # Dry-run mode: violations are logged but not blocked.
  # Set to false only after reviewing all audit log violations.
  enable_dry_run = true

  protected_projects = local.protected_project_numbers

  restricted_services = [
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "bigquerystorage.googleapis.com",
  ]

  # Allow access from corporate IP range without additional conditions
  access_levels = [
    {
      name        = "corp_network_access"
      title       = "Corporate Network Access"
      description = "Allow access from corporate egress IPs"
      conditions = [
        {
          ip_subnetworks = [local.corp_ip_range]
        }
      ]
    }
  ]
}

output "perimeter_name" {
  description = "The resource name of the service perimeter"
  value       = module.data_perimeter.name
}

output "access_policy_name" {
  description = "The access policy under which the perimeter was created"
  value       = module.data_perimeter.access_policy_name
}
