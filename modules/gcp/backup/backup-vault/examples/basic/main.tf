# Example: a Backup and DR vault that keeps every backup immutable for 35 days
# and a daily plan for one Cloud SQL instance in another project of the same
# region. The vault's service agent gets roles/backupdr.cloudSqlOperator in
# that project. No retention lock is set (lock_effective_time is irreversible).
#
# Replace the placeholder project IDs before use.
#
# Run `terraform init && terraform validate` here.

module "backup_vault" {
  source = "../../"

  project_id              = "my-host-project"
  location                = "europe-west2"
  vault_id                = "prod-vault"
  enforced_retention_days = 35

  cloud_sql_instances = {
    orders = "projects/my-service-project/instances/orders-db"
  }
  cloud_sql_source_projects = {
    service = "my-service-project"
  }

  labels = {
    managed-by = "terraform"
  }
}
