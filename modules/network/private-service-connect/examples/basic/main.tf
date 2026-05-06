# Example: create a Private Service Connect endpoint so VMs in the VPC
# can reach Google APIs (storage, BigQuery, etc.) via a private internal IP
# without traversing the internet.

locals {
  project_id = "my-workload-project"
  network    = "projects/my-workload-project/global/networks/my-vpc"
  subnetwork = "projects/my-workload-project/regions/us-central1/subnetworks/private-us-central1"
  region     = "us-central1"
}

module "psc_google_apis" {
  source = "../../"

  project_id = local.project_id
  name       = "google-apis-psc"
  network    = local.network
  subnetwork = local.subnetwork
  target     = "all-apis"  # Forwards to all Google APIs via PSC
  region     = local.region
}

output "psc_ip_address" {
  description = "Internal IP address for the PSC endpoint — create an A record for 'googleapis.com' pointing here"
  value       = module.psc_google_apis.address
}
