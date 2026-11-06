# Safe state migration for the audit C2 identity refactor.
#
# Bindings whose (role, member) are UNCHANGED are moved so they are not
# destroyed-then-recreated (which would briefly drop the bootstrap SA's org IAM
# admin mid-apply). Bindings that are intentionally REVOKED from the shared
# terraform-admin SA (orgpolicy/ACM/logging/SCC/xpn/tag admin, billing
# costsManager, the GitHub trust) are NOT moved: Terraform destroys them, which is
# the point of the fix. Their replacements live on the per-stage apply SAs.

moved {
  from = google_organization_iam_member.terraform_admin_standard_org_roles["roles/resourcemanager.organizationViewer"]
  to   = google_organization_iam_member.stage_org_roles["bootstrap-apply|roles/resourcemanager.organizationViewer"]
}

moved {
  from = google_organization_iam_member.terraform_admin_exception_org_roles["roles/iam.securityAdmin"]
  to   = google_organization_iam_member.stage_org_security_admin["bootstrap-apply|roles/iam.securityAdmin"]
}

# The GitHub pool is now count-gated (enable_github_wif, default false). Moving
# it to index [0] keeps it intact for anyone who sets enable_github_wif = true;
# with the default (false) Terraform destroys the unused pool, provider and the
# binding to the terraform-admin SA. NOTE: GCP soft-deletes WIF pools for 30 days
# and the pool ID cannot be reused in that window — set github_wif_pool_id to a
# new ID if you re-enable within 30 days.
moved {
  from = module.gh_oidc
  to   = module.gh_oidc[0]
}

# Audit Modularity-H: the admin project moved from a raw google_project into the
# shared project primitive (modules/gcp/project). Both the project and its
# for_each services move wholesale (same keys), so nothing is replaced.
moved {
  from = google_project.admin_project
  to   = module.admin_project.google_project.this
}

moved {
  from = google_project_service.admin_project_services
  to   = module.admin_project.google_project_service.this
}

# The org-node projects-apply delegation became optional (count) when the
# delegation moved to per-folder bindings in gcp-organization. With the legacy
# flag on, the existing binding keeps its address; with it off (default) the
# moved instance is planned for removal.
moved {
  from = google_organization_iam_member.projects_delegated_folder_iam
  to   = google_organization_iam_member.projects_delegated_folder_iam[0]
}
