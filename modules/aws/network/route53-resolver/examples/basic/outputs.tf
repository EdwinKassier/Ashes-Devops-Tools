output "inbound_endpoint_id" {
  description = "The ID of the inbound resolver endpoint."
  value       = module.route53_resolver.inbound_endpoint_id
}

output "outbound_endpoint_id" {
  description = "The ID of the outbound resolver endpoint."
  value       = module.route53_resolver.outbound_endpoint_id
}

output "resolver_profile_id" {
  description = "The ID of the org-shared Route 53 Profile."
  value       = module.route53_resolver.resolver_profile_id
}

output "firewall_rule_group_id" {
  description = "The ID of the DNS Firewall rule group."
  value       = module.route53_resolver.firewall_rule_group_id
}
