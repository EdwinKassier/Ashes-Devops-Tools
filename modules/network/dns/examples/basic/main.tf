# Example: create a private DNS zone and wire it to a VPC.
# Replace locals with data sources or remote state in real deployments.

locals {
  project_id = "my-project"
  network    = "projects/my-project/global/networks/my-vpc"
}

module "internal_dns" {
  source = "../../"

  project_id = local.project_id
  zone_name  = "internal"
  dns_name   = "internal.example.com."

  # Restrict visibility to the VPC network.
  private_visibility_networks = [local.network]

  # Static A records for internal services.
  records = [
    {
      name    = "api"
      type    = "A"
      ttl     = 300
      rrdatas = ["10.0.1.10"]
    },
    {
      name    = "db"
      type    = "A"
      ttl     = 300
      rrdatas = ["10.0.2.5"]
    },
  ]
}
