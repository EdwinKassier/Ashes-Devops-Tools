output "registered_services" {
  description = "Service principals for which a delegated administrator was registered (the keys of the effective registration map)."
  value       = keys(local.effective_registrations)
}
