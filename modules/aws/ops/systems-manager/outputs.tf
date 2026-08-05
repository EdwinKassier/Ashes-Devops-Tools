output "session_document_name" {
  description = "Name of the Session Manager preferences document."
  value       = aws_ssm_document.session_preferences.name
}

output "patch_baseline_id" {
  description = "ID of the SSM patch baseline created by this module."
  value       = aws_ssm_patch_baseline.this.id
}
