output "ca_pool_id" {
  description = "Fully qualified CA pool ID."
  value       = module.private_ca.ca_pool_id
}

output "certificate_authority_id" {
  description = "Fully qualified certificate authority ID."
  value       = module.private_ca.certificate_authority_id
}
