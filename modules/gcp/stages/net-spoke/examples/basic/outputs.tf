output "network_self_link" {
  description = "Self-link of the spoke VPC network"
  value       = module.example.network_self_link
}

output "security_policy_self_link" {
  description = "Cloud Armor policy to attach to the environment's load balancers"
  value       = module.example.security_policy_self_link
}
