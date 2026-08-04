# Example: create a Private Service Connect endpoint so VMs in the VPC
# can reach Google APIs (storage, BigQuery, etc.) via a private internal IP
# without traversing the internet.
#
# This module implements global PSC for Google APIs only (target = "all-apis"
# or "vpc-sc"). For regional PSC to third-party services use the GCP provider
# directly.

locals {
  project_id = "my-workload-project"
  network    = "projects/my-workload-project/global/networks/my-vpc"
}

module "psc_google_apis" {
  source = "../../"

  project_id = local.project_id
  name       = "google-apis-psc"
  network    = local.network
  target     = "all-apis" # Forwards to all Google APIs via PSC
}
