# Example: mirror traffic from a subnet to an IDS/IPS collector for inspection.
# Packet mirroring duplicates packets and sends them to a collector ILB.
# The collector ILB must already exist (use modules/network/internal-lb).

locals {
  project_id = "my-security-project"
  region     = "us-central1"
  network    = "projects/my-security-project/global/networks/my-vpc"
  # Self-link of the internal LB configured as the traffic collector.
  collector_ilb = "projects/my-security-project/regions/us-central1/forwardingRules/ids-collector-ilb"
  # Subnet to mirror traffic from.
  mirrored_subnet = "projects/my-security-project/regions/us-central1/subnetworks/private-us-central1"
}

module "packet_mirroring" {
  source = "../../"

  project_id        = local.project_id
  name              = "subnet-mirroring"
  region            = local.region
  network           = local.network
  collector_ilb_url = local.collector_ilb
  description       = "Mirror all TCP/UDP traffic from the private subnet to the IDS collector"

  mirrored_subnetworks = [local.mirrored_subnet]

  filter_ip_protocols = ["tcp", "udp"]
}

output "policy_id" {
  description = "Resource ID of the packet mirroring policy"
  value       = module.packet_mirroring.id
}
