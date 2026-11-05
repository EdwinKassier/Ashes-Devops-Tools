# Production hardening overlay for envs/gcp/bootstrap. Apply IN ADDITION to your own tfvars:
#   terraform -chdir=envs/gcp/bootstrap plan -var-file=your.tfvars -var-file=../../../examples/presets/prod-gcp-bootstrap.tfvars
#
# Routes the high-privilege org roles to a separate resman SA so a compromise of the
# CI-impersonable SA does not hold them (docs/runbooks/production-hardening.md, "Contain
# the automation identity").
# PREVIEW: mock-tested only. Validate on a throwaway org first; it also requires the WIF
# binding and downstream impersonation switch described in the runbook.
enable_privilege_split = true
