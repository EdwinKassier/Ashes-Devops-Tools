output "ca_arn" {
  description = "ARN of the ACM Private CA, or null when the module is disabled."
  value       = try(aws_acmpca_certificate_authority.this[0].arn, null)
}

output "resource_share_arn" {
  description = "ARN of the RAM resource share, or null when sharing is disabled."
  value       = try(aws_ram_resource_share.this[0].arn, null)
}
