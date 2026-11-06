# Production hardening overlay for envs/gcp/network-hub. Apply IN ADDITION to your own tfvars.
#
# ENFORCE the hub VPC-SC perimeter (the default is dry-run).
# PREREQUISITES: vpc_sc_access_policy_name must be set in your own tfvars (no perimeter
# is created without it), and the dry-run violation logs must be clean, because an
# enforced perimeter with a bad rule blocks legitimate API traffic.
vpc_sc_enable_dry_run = false
