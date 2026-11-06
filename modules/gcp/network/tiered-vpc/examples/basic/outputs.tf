output "network_self_link" {
  description = "Self-link of the created VPC network"
  value       = module.example.network_self_link
}

output "private_subnet_ids" {
  description = "Private (compute) subnet IDs keyed by zone"
  value       = { for z, s in module.example.subnets.private : z => s.id }
}
