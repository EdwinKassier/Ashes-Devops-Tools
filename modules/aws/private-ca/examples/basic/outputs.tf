output "ca_arn" {
  description = "ARN of the ACM Private CA created by the module."
  value       = module.private_ca.ca_arn
}

output "resource_share_arn" {
  description = "ARN of the RAM resource share."
  value       = module.private_ca.resource_share_arn
}
