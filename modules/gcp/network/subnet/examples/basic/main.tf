# Example: create a private subnet with flow logs enabled.
# Replace locals with data sources or remote state.

locals {
  project_id = "my-project"
  region     = "us-central1"
  network    = "projects/my-project/global/networks/my-vpc"
}

module "private_subnet" {
  source = "../../"

  project_id    = local.project_id
  subnet_name   = "private-us-central1"
  ip_cidr_range = "10.10.0.0/24"
  region        = local.region
  network       = local.network

  # private_ip_google_access = true (default) — VMs can reach Google APIs without external IPs.
  # enable_flow_logs = true (default) — captures traffic metadata for security auditing.
}
