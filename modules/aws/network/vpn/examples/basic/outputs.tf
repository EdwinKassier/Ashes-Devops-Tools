output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection."
  value       = module.vpn.vpn_connection_id
}

output "tunnel1_address" {
  description = "Public IP address of the first AWS tunnel endpoint."
  value       = module.vpn.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP address of the second AWS tunnel endpoint."
  value       = module.vpn.tunnel2_address
}

output "transit_gateway_attachment_id" {
  description = "ID of the Transit Gateway attachment created for the VPN."
  value       = module.vpn.transit_gateway_attachment_id
}
