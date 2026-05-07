# Example: establish an HA VPN (2 tunnels) between a GCP VPC and an on-premises
# firewall using dynamic routing (BGP). Replace locals with real values.
#
# Pre-requisites:
#   - VPC network already exists (or is managed in the same root).
#   - Your on-premises device has two public IPs for HA VPN.
#   - BGP session configuration on the on-premises device to match peer_asn/IPs here.

locals {
  project_id = "my-connectivity-project"
  region     = "us-central1"
  network    = "projects/my-connectivity-project/global/networks/my-vpc"

  # On-premises public IPs (one per tunnel for HA VPN).
  peer_ips = ["203.0.113.1", "203.0.113.2"]

  # Treat the shared secret like a password — pass via TF_VAR_vpn_secret or a secrets manager.
  vpn_shared_secret = "replace-with-strong-pre-shared-key"
}

module "on_prem_vpn" {
  source = "../../"

  project_id               = local.project_id
  name                     = "onprem-ha-vpn"
  network                  = local.network
  region                   = local.region
  peer_external_gateway_ip = local.peer_ips[0]
  shared_secret            = local.vpn_shared_secret

  router_asn = 64514
  peer_asn   = 65000

  # Two tunnels for high-availability.
  tunnel_count       = 2
  peer_ip_addresses  = local.peer_ips
  local_ip_addresses = ["169.254.0.1", "169.254.1.1"]
}

output "vpn_gateway_ip_addresses" {
  description = "GCP HA VPN gateway public IP addresses — configure these on the on-premises device"
  value       = module.on_prem_vpn.gateway_ip_addresses
}
