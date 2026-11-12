# Production hardening overlay for envs/gcp/workload (per prod environment). Apply IN
# ADDITION to your own tfvars.
#
# ENFORCE the environment VPC-SC perimeter (the default is dry-run).
# The perimeter is built in the environment's own folder-scoped access policy
# (gcp-organization creates it; gcp-projects passes its ID through
# environment_config), so leave vpc_sc_access_policy_name unset unless you are
# deliberately staying on the legacy org-wide policy.
# PREREQUISITES: clean dry-run violation logs. Set the environment's is_production
# attribute to true in the shared environments map so the production checks run.
# A production environment with a dry-run (or absent) perimeter FAILS its plan.
# During a first rollout only, set the production_vpc_sc_dry_run_waiver object
# (a reason and an expires date, YYYY-MM-DD) for that workspace in
# config/tfc-workspaces.yaml. It stops waiving after the expiry date.
vpc_sc_enable_dry_run = false

# Cloud Armor WAF on the environment edge, with the OWASP managed rule set.
# Review rule sensitivity against your traffic in preview mode before relying on it.
enable_cloud_armor = true
enable_owasp_rules = true
