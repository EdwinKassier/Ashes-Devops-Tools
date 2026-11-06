# State Migration Mappings
# These blocks ensure Terraform treats the refactor as a renaming operation
# rather than a destroy/create operation.
#
# CLEANUP INSTRUCTION: These are one-time migration helpers for deployments that
# were created before resources were encapsulated into stage modules. If you are
# starting from a fresh fork with no existing Terraform state, these blocks are
# no-ops and can be safely deleted. After running `terraform apply` once against
# an existing deployment to complete the migration, delete this file.

# NOTE: the former "Bootstrap Module Mappings" were removed when the bootstrap
# stage was split into its own root and state (envs/gcp/bootstrap).
# Relocating those resources out of this state is a cross-STATE migration
# (terraform state mv / removed + import), which a `moved` block cannot express.
# See docs/architecture/gcp-state-decomposition.md.

# Organization Module Mappings
#
# The former `moved { from = module.organization  to = module.organization.module.organization }`
# was removed (2026-11-05 audit): `module.organization` is still declared (it is
# now the organization STAGE), so Terraform rejects that block with "Moved object
# still exists" and EVERY plan of this root failed. A legacy state whose root-level
# module.organization was the iam/organization module needs a one-off
#   terraform state mv module.organization.<addr> module.organization.module.organization.<addr>
# per resource instead.

moved {
  from = module.tags
  to   = module.organization.module.tags
}

moved {
  from = module.org_policies
  to   = module.organization.module.org_policies
}

moved {
  from = module.prod_folder_policies
  to   = module.organization.module.prod_folder_policies
}

moved {
  from = module.audit_logs
  to   = module.organization.module.audit_logs
}

moved {
  from = module.scc_notifications
  to   = module.organization.module.scc_notifications
}

moved {
  from = google_essential_contacts_contact.security
  to   = module.organization.google_essential_contacts_contact.security
}

moved {
  from = google_essential_contacts_contact.billing
  to   = module.organization.google_essential_contacts_contact.billing
}

moved {
  from = module.org_budget
  to   = module.organization.module.org_budget
}

moved {
  from = google_bigquery_dataset.billing_export
  to   = module.organization.google_bigquery_dataset.billing_export
}

# NOTE: the former "Projects Module Mappings" and "Network Hub Module Mappings"
# were removed when the projects and network-hub stages were split into their own
# roots and states (envs/gcp/projects, envs/gcp/network-hub). Relocating
# those resources is a cross-STATE migration (terraform state mv / import), not a
# `moved` block. See docs/architecture/gcp-state-decomposition.md.
