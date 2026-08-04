# Example: allocate an IP range for Private Service Access so managed services
# like Cloud SQL can use private IPs in your VPC.

locals {
  project_id  = "my-workload-project"
  vpc_network = "projects/my-workload-project/global/networks/my-vpc"
}

module "psa" {
  source = "../../"

  project_id    = local.project_id
  vpc_network   = local.vpc_network
  name          = "psa-range"
  address       = "10.200.0.0"
  prefix_length = 16
}
