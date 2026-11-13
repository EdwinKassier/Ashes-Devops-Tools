# Example: create a complete Supabase environment (project + settings + API keys).
# Replace locals with real values or remote state. The database password is a
# sensitive variable (TF_VAR_database_password or a sensitive TFC variable).

locals {
  organization_id = "abcdefghijklmnop"
}

module "qa_environment" {
  source = "../../"

  organization_id   = local.organization_id
  project_name      = "my-app-qa"
  database_password = var.database_password
  region            = "eu-west-2"

  # Auth settings — relax for QA, tighten for production
  mailer_autoconfirm  = true  # skip email confirmation in QA
  disable_signup      = false # allow self-service signup in QA
  password_min_length = 12    # the module default; keep it for QA too
  jwt_expiry          = 3600
}
