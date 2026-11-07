output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection."
  value       = aws_vpn_connection.this.id
}

output "customer_gateway_id" {
  description = "ID of the customer gateway."
  value       = aws_customer_gateway.this.id
}

output "tunnel1_address" {
  description = "Public IP address of the first VPN tunnel (AWS side)."
  value       = aws_vpn_connection.this.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP address of the second VPN tunnel (AWS side)."
  value       = aws_vpn_connection.this.tunnel2_address
}

output "transit_gateway_attachment_id" {
  description = "ID of the transit gateway attachment the VPN connection creates (null when attach_to = vpn_gateway). Associate it with a TGW route table to route through it."
  value       = aws_vpn_connection.this.transit_gateway_attachment_id
}

output "preshared_key_arn" {
  description = "ARN of the Secrets Manager secret holding the tunnel pre-shared keys (null when preshared_key_storage = Standard). Read the keys from there to configure the on-premises device."
  value       = aws_vpn_connection.this.preshared_key_arn
}
