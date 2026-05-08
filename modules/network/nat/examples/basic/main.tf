# Example: attach a Cloud NAT gateway to an existing VPC subnet.
# Replace locals with data sources or remote state in real deployments.

locals {
  project_id = "my-project"
  region     = "us-central1"
  network    = "projects/my-project/global/networks/my-vpc"
}

module "nat" {
  source = "../../"

  project_id = local.project_id
  name       = "egress-nat"
  region     = local.region
  network    = local.network

  # create_router = true (default) creates a new Cloud Router alongside the NAT.
  # Set create_router = false and provide router_name to attach to an existing router.
}
