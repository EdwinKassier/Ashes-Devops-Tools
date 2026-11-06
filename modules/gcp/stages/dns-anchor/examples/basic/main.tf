# Example: a DNS-anchor VPC hosting the organization's root private zone.
# Spokes resolve it with a DNS peering zone targeting network_self_link.
# Replace the placeholder project ID and domain before use.

module "example" {
  source = "../../"

  project_id = "myorg-dns-abc123"
  region     = "us-central1"

  network = {
    name           = "dns-vpc-core"
    cidr_block     = "10.1.0.0/16"
    explicit_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
  }

  dns_zones = {
    "internal-root" = {
      dns_name    = "internal.example.com."
      description = "Root Internal Zone for Organization"
    }
  }
}
