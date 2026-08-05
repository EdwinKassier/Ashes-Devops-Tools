output "vault_arn" {
  description = "The ARN of the AWS Backup vault created by the module."
  value       = module.backup_vault.vault_arn
}

output "restore_testing_plan_arn" {
  description = "The ARN of the restore testing plan."
  value       = module.backup_vault.restore_testing_plan_arn
}
