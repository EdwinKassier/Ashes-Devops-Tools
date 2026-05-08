# Example: deploy the hub VPC and DNS hub that all spoke projects peer to.
# In a full landing zone this is called from envs/organization/main.tf.
# Replace locals with outputs from the organization stage or remote state.

locals {
  org_id         = "organizations/123456789012"
  hub_project_id = "myorg-hub-abc123"
  dns_project_id = "myorg-dns-abc123"
}

module "network_hub" {
  source = "../../"

  project_prefix         = "myorg"
  hub_project_id         = local.hub_project_id
  dns_project_id         = local.dns_project_id
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  default_region         = "us-central1"
  org_id                 = local.org_id
  internal_domain        = "internal.example.com."

  # Map of spoke project names to project IDs that will peer to the hub VPC.
  spoke_project_ids = {}

  # Folders from the organization stage — used to attach hub DNS policies.
  folders = {
    dev = {
      id           = "123456789001"
      name         = "folders/123456789001"
      display_name = "Development"
    }
  }
}
