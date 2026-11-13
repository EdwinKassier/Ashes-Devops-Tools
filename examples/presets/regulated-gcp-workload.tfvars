# Regulated environment overlay for envs/gcp/workload (CMP-7). An environment
# with gcp.environments.<env>.compliance_class: regulated in
# config/landing-zone.yaml gets these values from the YAML twin automatically.
# Use this file only for a -var-file run of that environment.
# See docs/architecture/regulated-environments.md.
#
# ENFORCE the environment VPC-SC perimeter. A regulated environment fails its
# plan on a dry-run or absent perimeter, and it does not accept
# production_vpc_sc_dry_run_waiver.
# PREREQUISITES: clean dry-run violation logs.
#
# Also required for a regulated environment, outside this preset:
#   - gcp-organization: a hardened audit store (gcp.logging_project_id,
#     gcp.logging_project_number and gcp.enable_audit_bucket_lock: true, which
#     is IRREVERSIBLE), or gcp.audit_store_waiver { reason, expires }.
#   - database.encryption_key_name (a CMEK) on every app-service database.
#   - The Backup and DR vault stays on (it defaults to on for regulated; do not
#     set enable_backup_vault = false or backup_vault.enabled: false).
#   - The production prerequisites in prod-gcp-workload.tfvars when the
#     environment is also is_production.
vpc_sc_enable_dry_run = false

# Cloud Armor WAF on the environment edge, with the OWASP managed rule set.
enable_cloud_armor = true
enable_owasp_rules = true

# Record every flow (1 = 100% sampling) and keep the flow-log export for a year.
# Full sampling raises the Cloud Logging and BigQuery cost.
log_config_flow_sampling     = 1
vpc_flow_logs_retention_days = 365
