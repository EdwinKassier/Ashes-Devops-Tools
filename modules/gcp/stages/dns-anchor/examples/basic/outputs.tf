output "network_self_link" {
  description = "Self-link of the DNS-anchor VPC (target for DNS peering zones)"
  value       = module.example.network_self_link
}

output "dns_names" {
  description = "DNS suffix served by each anchored zone"
  value       = module.example.dns_names
}
