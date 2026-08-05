# Supabase Environment Module
#
# Composite module: creates a Supabase project, applies auth and API settings,
# and reads the project's API keys. This is the primary building block for
# per-environment deployments (QA, UAT, production).
#
# API keys are read via data.supabase_apikeys after project creation.
# The anon_key output is deliberately NOT marked sensitive — it is a public
# credential safe to embed in client-side code. Marking it sensitive would
# break Terraform for-expression filter conditions in callers that iterate
# over multiple environment outputs. The service_role_key IS marked sensitive.

module "project" {
  source = "../project"

  organization_id   = var.organization_id
  project_name      = var.project_name
  database_password = var.database_password
  region            = var.region
}

module "settings" {
  source = "../settings"

  project_ref  = module.project.id
  api_max_rows = var.api_max_rows
  # Extends collects supabase-environment: collects does not pass db_schema,
  # db_extra_search_path, or jwt_expiry to module.settings (they are hardcoded
  # inside the settings module itself). We parameterise them at the environment
  # level for callers that need per-environment overrides.
  db_schema            = var.db_schema
  db_extra_search_path = var.db_extra_search_path
  disable_signup       = var.disable_signup
  mailer_autoconfirm   = var.mailer_autoconfirm
  jwt_expiry           = var.jwt_expiry
  password_min_length  = var.password_min_length
}

# Audit finding S1: Supabase is deprecating the legacy JWT keys (anon_key /
# service_role_key) by end of 2026 in favour of publishable (sb_publishable_...)
# and secret (sb_secret_...) keys. This module still consumes the legacy pair
# because the supabase/supabase Terraform provider (pinned ~> 1.0, currently
# 1.9.0) does NOT yet expose the new key types on the supabase_apikeys data
# source — referencing sb_publishable_key / sb_secret_key here today would fail
# `terraform validate`. TODO: once the provider adds new-key attributes, expose
# them as additional outputs (publishable_key / secret_key) so callers can cut
# over without a breaking change, then deprecate the anon_key/service_role_key
# outputs. Tracking: https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys
data "supabase_apikeys" "this" {
  # project_ref = module.project.id creates an implicit dependency on module.project.
  # No explicit depends_on needed — adding it would defer the data source to apply
  # phase unnecessarily, propagating (known after apply) to anon_key/service_role_key
  # consumers and degrading plan output quality.
  project_ref = module.project.id
}
