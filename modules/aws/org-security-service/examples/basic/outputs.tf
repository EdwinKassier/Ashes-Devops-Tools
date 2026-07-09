output "enabled_services" {
  description = "The set of org-security services enabled by the module."
  value       = module.org_security_service.enabled_services
}

output "macie_account_id" {
  description = "The Macie account ID, or null when Macie is not enabled."
  value       = module.org_security_service.macie_account_id
}
