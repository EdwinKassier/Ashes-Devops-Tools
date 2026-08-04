output "vpn_gateway_ip_addresses" {
  description = "GCP HA VPN gateway public IP addresses — configure these on the on-premises device"
  value       = module.on_prem_vpn.gateway_ip_addresses
}
