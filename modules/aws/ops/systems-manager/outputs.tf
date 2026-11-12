output "session_document_name" {
  description = "Name of the Session Manager preferences document."
  value       = aws_ssm_document.session_preferences.name
}

output "patch_baseline_id" {
  description = "ID of the patch baseline for the first operating system in patch_operating_systems (sorted). Use patch_baseline_ids when the module manages more than one OS."
  value       = aws_ssm_patch_baseline.this[sort(tolist(local.patch_operating_systems))[0]].id
}

output "patch_baseline_ids" {
  description = "Patch baseline ID per operating system."
  value       = { for os, b in aws_ssm_patch_baseline.this : os => b.id }
}

output "patch_install_association_id" {
  description = "ID of the weekly patch install association, or null when enable_patch_install is false."
  value       = try(aws_ssm_association.patch_install[0].association_id, null)
}

output "patch_install_schedule" {
  description = "Cron schedule of the weekly patch install association, or null when enable_patch_install is false."
  value       = try(aws_ssm_association.patch_install[0].schedule_expression, null)
}

output "patch_operating_systems" {
  description = "Operating systems that have a custom default patch baseline in this account and region."
  value       = sort(tolist(local.patch_operating_systems))
}
