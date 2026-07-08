# Supabase Settings Module
#
# Manages the API and auth configuration for an existing Supabase project.
#
# ⚠️  Destroying this resource is a NO-OP — the Supabase Management API has no
# "reset settings to defaults" endpoint. Terraform will remove the resource from
# state but the project settings remain unchanged. This is expected behaviour for
# supabase_settings.

resource "supabase_settings" "this" {
  project_ref = var.project_ref

  # Diverges from collects: collects hardcodes db_schema and db_extra_search_path
  # (both to empty string defaults). We parameterise them for flexibility.
  api = jsonencode({
    db_schema            = var.db_schema
    db_extra_search_path = var.db_extra_search_path
    max_rows             = var.api_max_rows
  })

  # Diverges from collects: collects hardcodes jwt_exp = 3600 (1 hour).
  # We parameterise it; the default of 3600 preserves collects' behaviour.
  #
  # The Management API / supabase provider field is `jwt_exp` (see the provider's
  # UpdateAuthConfigBody struct tag and settings_resource_test.go). The provider
  # unmarshals this JSON with lenient decoding, so a misnamed key like
  # `jwt_expiry` is silently dropped and never applied — keep this as `jwt_exp`.
  auth = jsonencode({
    disable_signup      = var.disable_signup
    jwt_exp             = var.jwt_expiry
    mailer_autoconfirm  = var.mailer_autoconfirm
    password_min_length = var.password_min_length
  })
}
