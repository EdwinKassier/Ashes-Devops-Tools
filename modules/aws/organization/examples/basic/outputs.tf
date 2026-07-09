output "organization_id" {
  description = "The ID of the AWS organization created by the module."
  value       = module.organization.organization_id
}

output "ou_ids" {
  description = "Map of OU name to OU ID."
  value       = module.organization.ou_ids
}
