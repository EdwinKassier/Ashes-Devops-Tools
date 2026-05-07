# Example: create a Partner Interconnect VLAN attachment.
# Partner Interconnect is the common path — use DEDICATED when you have a
# physical cross-connect at a colocation facility.
#
# After terraform apply, take the pairing key from the output and provide it
# to your service provider to activate the interconnect.

locals {
  project_id = "my-connectivity-project"
  region     = "us-central1"
  network    = "projects/my-connectivity-project/global/networks/my-vpc"
}

module "partner_interconnect" {
  source = "../../"

  project_id        = local.project_id
  region            = local.region
  network           = local.network
  attachment_name   = "partner-vlan-central1"
  interconnect_type = "PARTNER"

  description = "Partner Interconnect VLAN to on-premises via Equinix"

  router_name = "interconnect-router"
  router_asn  = 64514
}

output "pairing_key" {
  description = "Share this key with your service provider to activate the interconnect"
  value       = module.partner_interconnect.attachment
  sensitive   = true
}
