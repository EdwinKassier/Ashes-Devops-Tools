output "self_link" {
  description = "Self-link of the created VPC — use this to reference the VPC in other modules"
  value       = module.example.self_link
}

output "name" {
  description = "Name of the created VPC"
  value       = module.example.name
}
