output "vault_arn" {
  description = "The ARN of the AWS Backup vault."
  value       = aws_backup_vault.this.arn
}

output "vault_name" {
  description = "The name of the AWS Backup vault."
  value       = aws_backup_vault.this.name
}

output "restore_testing_plan_arn" {
  description = "The ARN of the restore testing plan, if one was created."
  value       = try(aws_backup_restore_testing_plan.this.arn, null)
}
