output "registered_services" {
  description = "Service principals for which a delegated administrator was registered."
  value       = module.security_delegated_admin.registered_services
}
