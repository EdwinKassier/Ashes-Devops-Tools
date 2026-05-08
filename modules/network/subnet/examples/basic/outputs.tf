output "subnet_self_link" {
  description = "Self-link of the created subnet — use this to reference the subnet in other modules"
  value       = module.private_subnet.self_link
}
