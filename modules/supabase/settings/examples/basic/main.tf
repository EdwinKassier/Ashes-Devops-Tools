# Example: configure auth and API settings for an existing Supabase project.

locals {
  project_ref = "abcdefghijklmnopqrst" # 20-char project ref from supabase/project output
}

module "supabase_settings" {
  source = "../../"

  project_ref         = local.project_ref
  api_max_rows        = 1000
  disable_signup      = false  # set true for production
  mailer_autoconfirm  = true   # QA only — disable in production
  password_min_length = 12
  jwt_expiry          = 3600
}
