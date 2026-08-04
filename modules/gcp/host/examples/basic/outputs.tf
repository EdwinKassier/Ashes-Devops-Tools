output "network_self_link" {
  description = "Self-link of the created VPC network"
  value       = module.example.network_self_link
}

output "network_name" {
  description = "Name of the created VPC network"
  value       = module.example.network_name
}
