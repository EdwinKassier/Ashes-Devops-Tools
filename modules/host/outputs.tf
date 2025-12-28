/**
 * Copyright 2023 Ashes
 *
 * Host Module - Outputs
 */

# =============================================================================
# VPC OUTPUTS
# =============================================================================

output "vpc" {
  description = "The VPC module outputs (if enabled)"
  value       = var.enable_networking ? module.vpc[0] : null
}

output "network_id" {
  description = "The VPC network ID"
  value       = var.enable_networking ? module.vpc[0].network_id : var.existing_network_id
}

output "network_self_link" {
  description = "The VPC network self link"
  value       = var.enable_networking ? module.vpc[0].network_self_link : var.existing_network_self_link
}

output "network_name" {
  description = "The VPC network name"
  value       = var.enable_networking ? module.vpc[0].network_name : null
}

output "subnets" {
  description = "All subnet outputs organized by tier"
  value = var.enable_networking ? {
    public   = module.vpc[0].public_subnets
    private  = module.vpc[0].private_subnets
    database = module.vpc[0].database_subnets
  } : null
}

output "network_tags" {
  description = "Network tags for tiered security"
  value       = var.enable_networking ? module.vpc[0].network_tags : null
}

output "nat_ip" {
  description = "The NAT gateway IP addresses"
  value       = var.enable_networking ? module.vpc[0].nat_ip : null
}

# =============================================================================
# CLOUD ARMOR OUTPUTS
# =============================================================================

output "cloud_armor" {
  description = "The Cloud Armor security policy (if enabled)"
  value       = var.enable_cloud_armor ? module.cloud_armor[0] : null
}

output "security_policy_id" {
  description = "The Cloud Armor security policy ID"
  value       = var.enable_cloud_armor ? module.cloud_armor[0].policy_id : null
}

output "security_policy_self_link" {
  description = "The Cloud Armor security policy self link"
  value       = var.enable_cloud_armor ? module.cloud_armor[0].policy_self_link : null
}

# =============================================================================
# CDN OUTPUTS
# =============================================================================

output "cdn" {
  description = "The CDN module outputs (if enabled)"
  value       = var.enable_cdn ? module.cdn[0] : null
}

output "cdn_ip" {
  description = "The global load balancer IP address"
  value       = var.enable_cdn ? module.cdn[0].load_balancer_ip : null
}

output "cdn_backend_service_id" {
  description = "The CDN backend service ID"
  value       = var.enable_cdn ? module.cdn[0].backend_service_id : null
}

# =============================================================================
# DNS OUTPUTS
# =============================================================================

output "dns_zones" {
  description = "All DNS zone outputs"
  value       = module.dns
}

output "dns_name_servers" {
  description = "Name servers for each public DNS zone"
  value = {
    for k, v in module.dns : k => v.name_servers
  }
}

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
# API GATEWAY OUTPUTS
# =============================================================================

output "api_gateway" {
  description = "The API Gateway module outputs (if enabled)"
  value       = var.enable_api_gateway ? module.api_gateway[0] : null
}

output "api_gateway_hostname" {
  description = "The default hostname of the API Gateway"
  value       = var.enable_api_gateway ? module.api_gateway[0].gateway_default_hostname : null
}

output "api_gateway_neg_id" {
  description = "The serverless NEG ID for load balancer integration"
  value       = var.enable_api_gateway ? module.api_gateway[0].serverless_neg_id : null
}

# =============================================================================
# ADDITIONAL FIREWALL RULES OUTPUTS
# =============================================================================

output "additional_firewall_rules" {
  description = "All additional firewall rule outputs"
  value       = module.additional_firewall_rules
}

output "additional_firewall_rule_ids" {
  description = "The IDs of all additional firewall rules"
  value = {
    for k, v in module.additional_firewall_rules : k => v.id
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
# VPC FLOW LOGS EXPORT OUTPUTS
# =============================================================================

output "vpc_flow_logs" {
  description = "The VPC Flow Logs export module outputs (if enabled)"
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0] : null
}

output "vpc_flow_logs_sink_id" {
  description = "The ID of the VPC Flow Logs sink"
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0].id : null
}

output "vpc_flow_logs_writer_identity" {
  description = "The service account identity for the flow logs sink writer"
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0].writer_identity : null
}

# =============================================================================
# SHARED VPC SERVICE PROJECT OUTPUTS
# =============================================================================

output "shared_vpc_service_projects" {
  description = "All Shared VPC service project attachment outputs"
  value       = module.shared_vpc_service_projects
}

output "shared_vpc_service_project_ids" {
  description = "The IDs of all Shared VPC service project attachments"
  value = {
    for k, v in module.shared_vpc_service_projects : k => v.id
  }
}

# =============================================================================
# HIERARCHICAL FIREWALL POLICY OUTPUTS
# =============================================================================

output "hierarchical_firewall_policies" {
  description = "All hierarchical firewall policy outputs"
  value       = module.hierarchical_firewall_policies
}

output "hierarchical_firewall_policy_ids" {
  description = "The IDs of all hierarchical firewall policies"
  value = {
    for k, v in module.hierarchical_firewall_policies : k => v.id
  }
}

# =============================================================================
# VPC SERVICE CONTROLS OUTPUTS
# =============================================================================

output "vpc_service_controls" {
  description = "All VPC Service Controls perimeter outputs"
  value       = module.vpc_service_controls
}

output "vpc_service_control_perimeter_names" {
  description = "The names of all VPC Service Controls perimeters"
  value = {
    for k, v in module.vpc_service_controls : k => v.name
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

# =============================================================================
# PACKET MIRRORING OUTPUTS
# =============================================================================

output "packet_mirroring_policies" {
  description = "All packet mirroring policy outputs"
  value       = module.packet_mirroring
}

output "packet_mirroring_policy_ids" {
  description = "The IDs of all packet mirroring policies"
  value = {
    for k, v in module.packet_mirroring : k => v.id
  }
}

# =============================================================================
# INTERNAL LOAD BALANCER OUTPUTS
# =============================================================================

output "internal_load_balancers" {
  description = "All internal load balancer outputs"
  value       = module.internal_load_balancers
}

output "internal_load_balancer_ips" {
  description = "The IP addresses of all internal load balancers"
  value = {
    for k, v in module.internal_load_balancers : k => v.ip_address
  }
}

output "internal_load_balancer_backend_services" {
  description = "The backend service self_links for all internal load balancers"
  value = {
    for k, v in module.internal_load_balancers : k => v.backend_service_self_link
  }
}

