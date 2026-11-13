# Production hardening overlay for envs/gcp/network-hub. Apply IN ADDITION to your own tfvars.
#
# ENFORCE the hub VPC-SC perimeter (the default is dry-run).
# PREREQUISITES: vpc_sc_access_policy_name must be set in your own tfvars (no perimeter
# is created without it), and the dry-run violation logs must be clean, because an
# enforced perimeter with a bad rule blocks legitimate API traffic.
#
# Not set by this preset, but needed once any environment is production:
#   - Pinned hub zones: gcp.network.zones in config/landing-zone.yaml (or the
#     hub_zones variable). The plan fails without them.
#   - secure_web_proxy (PREVIEW) on this root, when a production gcp-workload
#     sends its egress through the hub proxy (gcp.environments.<env>.egress_proxy)
#     instead of setting production_egress_proxy_waiver.
vpc_sc_enable_dry_run = false
