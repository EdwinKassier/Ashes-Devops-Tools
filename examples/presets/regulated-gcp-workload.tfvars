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
vpc_sc_enable_dry_run = false

# Cloud Armor WAF on the environment edge, with the OWASP managed rule set.
enable_cloud_armor = true
enable_owasp_rules = true

# Record every flow (1 = 100% sampling) and keep the flow-log export for a year.
# Full sampling raises the Cloud Logging and BigQuery cost.
log_config_flow_sampling     = 1
vpc_flow_logs_retention_days = 365
