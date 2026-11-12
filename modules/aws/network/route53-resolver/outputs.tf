output "inbound_endpoint_id" {
  description = "The ID of the inbound Route 53 Resolver endpoint, or null when enable_resolver_endpoints is false."
  value       = try(aws_route53_resolver_endpoint.inbound[0].id, null)
}

output "outbound_endpoint_id" {
  description = "The ID of the outbound Route 53 Resolver endpoint, or null when enable_resolver_endpoints is false."
  value       = try(aws_route53_resolver_endpoint.outbound[0].id, null)
}

output "inbound_endpoint_ips" {
  description = "IP addresses of the inbound Route 53 Resolver endpoint (the targets for on-premises conditional forwarders), or an empty list when enable_resolver_endpoints is false."
  value       = try([for ip in aws_route53_resolver_endpoint.inbound[0].ip_address : ip.ip], [])
}

output "resolver_profile_id" {
  description = "The ID of the Route 53 Profile shared org-wide over RAM."
  value       = aws_route53profiles_profile.this.id
}

output "firewall_rule_group_id" {
  description = "The ID of the DNS Firewall rule group, or null when DNS Firewall is disabled."
  value       = try(aws_route53_resolver_firewall_rule_group.this[0].id, null)
}
