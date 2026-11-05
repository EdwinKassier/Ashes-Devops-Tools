# Production hardening overlay for envs/gcp/workload (per prod environment). Apply IN
# ADDITION to your own tfvars.
#
# ENFORCE the environment VPC-SC perimeter (the default is dry-run).
# PREREQUISITES: vpc_sc_access_policy_name set in your own tfvars, and clean dry-run logs.
vpc_sc_enable_dry_run = false

# Cloud Armor WAF on the environment edge, with the OWASP managed rule set.
# Review rule sensitivity against your traffic in preview mode before relying on it.
enable_cloud_armor = true
enable_owasp_rules = true
