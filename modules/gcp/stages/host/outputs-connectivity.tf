# Host stage (connectivity) outputs. Part of modules/gcp/stages/host.

# =============================================================================
# VPN OUTPUTS
# =============================================================================

output "vpn" {
  description = "The VPN module outputs (if enabled)"
  value       = var.enable_vpn ? module.vpn[0] : null
}

output "vpn_gateway_ips" {
  description = "The VPN gateway external IP addresses"
  value       = var.enable_vpn ? module.vpn[0].gateway_ip_addresses : null
}

output "vpn_tunnel_statuses" {
  description = "The status of each VPN tunnel"
  value       = var.enable_vpn ? module.vpn[0].tunnel_statuses : null
}

# =============================================================================
# VPC PEERING OUTPUTS
# =============================================================================

output "vpc_peerings" {
  description = "All VPC peering outputs"
  value       = module.vpc_peering
}

output "peering_states" {
  description = "The state of each VPC peering connection"
  value = {
    for k, v in module.vpc_peering : k => v.peering_state
  }
}

# =============================================================================
# STANDALONE NAT GATEWAY OUTPUTS
# =============================================================================

output "standalone_nat_gateways" {
  description = "All standalone NAT gateway outputs"
  value       = module.standalone_nat
}

output "standalone_nat_ips" {
  description = "The NAT IP addresses for each standalone NAT gateway"
  value = {
    for k, v in module.standalone_nat : k => v.nat_ips
  }
}

# =============================================================================
# INTERCONNECT OUTPUTS
# =============================================================================

output "interconnects" {
  description = "All Cloud Interconnect attachment outputs"
  value       = module.interconnects
}

output "interconnect_pairing_keys" {
  description = "Pairing keys for partner interconnects (share with provider)"
  sensitive   = true
  value = {
    for k, v in module.interconnects : k => v.pairing_key
  }
}

output "interconnect_states" {
  description = "The state of each interconnect attachment"
  value = {
    for k, v in module.interconnects : k => v.state
  }
}

