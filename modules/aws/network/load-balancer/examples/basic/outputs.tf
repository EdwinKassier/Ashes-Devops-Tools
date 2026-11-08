output "arn" {
  description = "ARN of the load balancer."
  value       = module.load_balancer.arn
}

output "dns_name" {
  description = "DNS name of the load balancer."
  value       = module.load_balancer.dns_name
}

output "security_group_id" {
  description = "ID of the module-managed security group (add ingress rules to it)."
  value       = module.load_balancer.security_group_id
}

output "target_group_arns" {
  description = "Map of target group key to its ARN."
  value       = module.load_balancer.target_group_arns
}
