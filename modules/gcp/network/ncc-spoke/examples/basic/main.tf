# Example: attach a spoke VPC to the edge group of a STAR hub, with a producer
# VPC spoke for its Private Service Access peering.

module "ncc_spoke" {
  source = "../../"

  project_id = "my-spoke-project"
  name       = "dev-vpc"
  hub_id     = "projects/my-hub-project/locations/global/hubs/landing-zone-hub"
  group      = "edge"

  linked_vpc_network = {
    uri = "https://www.googleapis.com/compute/v1/projects/my-spoke-project/global/networks/dev-vpc"
  }

  producer_vpc_networks = {
    psa = {
      network = "dev-vpc"
      peering = "servicenetworking-googleapis-com"
    }
  }
}
