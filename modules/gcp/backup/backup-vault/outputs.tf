/**
 * Backup Vault Module - Outputs
 */

output "vault_id" {
  description = "Terraform ID of the backup vault (projects/<project>/locations/<location>/backupVaults/<vault_id>)."
  value       = google_backup_dr_backup_vault.this.id
}

output "vault_name" {
  description = "Resource name of the backup vault."
  value       = google_backup_dr_backup_vault.this.name
}

output "service_account" {
  description = "The vault's service agent. The module grants it roles/backupdr.cloudSqlOperator in cloud_sql_source_projects. A CMEK-encrypted Cloud SQL instance also needs roles/cloudkms.cryptoKeyEncrypterDecrypter for this agent on its key."
  value       = google_backup_dr_backup_vault.this.service_account
}

output "enforced_retention_days" {
  description = "Minimum enforced retention of the vault, in days."
  value       = var.enforced_retention_days
}

output "backup_plan_id" {
  description = "ID of the daily Cloud SQL backup plan, or null when no instance is listed."
  value       = try(google_backup_dr_backup_plan.cloud_sql[0].id, null)
}

output "protected_instances" {
  description = "Cloud SQL instances associated with the plan: key => instance resource name."
  value       = { for k, a in google_backup_dr_backup_plan_association.cloud_sql : k => a.resource }
}
