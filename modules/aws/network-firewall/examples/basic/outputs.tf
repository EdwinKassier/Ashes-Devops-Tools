output "firewall_arn" {
  description = "ARN of the Network Firewall created by the module."
  value       = module.network_firewall.firewall_arn
}

output "firewall_endpoint_ids" {
  description = "Firewall endpoint IDs (or fallback firewall ID)."
  value       = module.network_firewall.firewall_endpoint_ids
}
