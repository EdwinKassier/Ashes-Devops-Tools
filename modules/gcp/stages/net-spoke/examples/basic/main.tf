# Example: an environment spoke network peered to the hub, with a DNS peering
# zone onto the hub's internal domain. Replace the placeholder project IDs and
# hub network self-link (normally read from the gcp-network-hub contract).

locals {
  hub_vpc_self_link = "projects/myorg-hub-abc123/global/networks/hub-vpc-core"
}

module "example" {
  source = "../../"

  project_id     = "myorg-dev-host-abc123"
  project_prefix = "myorg-dev"
  region         = "us-central1"

  network = {
    name           = "myorg-dev-vpc"
    cidr_block     = "10.20.0.0/16"
    explicit_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
  }

  peerings = {
    "hub-peering" = {
      peer_network         = local.hub_vpc_self_link
      export_custom_routes = true
      import_custom_routes = true
    }
  }

  dns_zones = {
    "internal-peering" = {
      dns_name        = "internal.example.com."
      visibility      = "private"
      peering_network = local.hub_vpc_self_link
    }
  }
}
