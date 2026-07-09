output "session_document_name" {
  description = "Name of the Session Manager preferences document."
  value       = module.systems_manager.session_document_name
}

output "patch_baseline_id" {
  description = "ID of the SSM patch baseline."
  value       = module.systems_manager.patch_baseline_id
}
