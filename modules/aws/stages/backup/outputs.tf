output "vault_arn" {
  description = "ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account."
  value       = module.backup_vault.vault_arn
}

output "backup_policy_id" {
  description = "ID of the organization BACKUP_POLICY attached to the Workloads OU."
  value       = module.backup_org_policy.policy_id
}

output "backup_role_arn" {
  description = "Member-account backup role ARN rendered into the org BACKUP_POLICY ($account-templated when the stage's StackSet deploys the role)."
  value       = local.backup_role_arn
}

output "restore_testing_role_arn" {
  description = "ARN of the restore-testing role in the backup account (created by the stage unless restore_testing_role_arn was set). With enable_central_copy it is the copy vault's role."
  value       = var.enable_central_copy ? try(module.copy_vault[0].restore_testing_role_arn, null) : module.backup_vault.restore_testing_role_arn
}

output "copy_destination_vault_arns" {
  description = "Vault ARNs the BACKUP_POLICY copies each recovery point to: the central copy vault (enable_central_copy) and the member DR vault ($account, dr_region). Empty by default."
  value       = [for c in local.copy_actions : c.destination_vault_arn]
}

output "policy_target_vault_name" {
  description = "Member-account vault the BACKUP_POLICY daily rule writes to."
  value       = local.member_vault_name
}

output "copy_vault_arn" {
  description = "ARN of the locked central copy vault in the backup account. Null unless enable_central_copy."
  value       = try(module.copy_vault[0].vault_arn, null)
}
