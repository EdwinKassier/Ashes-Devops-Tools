# Example: create a complete Supabase environment (project + settings + API keys).
# Replace locals with real values or remote state.

locals {
  organization_id   = "abcdefghijklmnop"
  database_password = "change-me-min-16ch"
}

module "qa_environment" {
  source = "../../"

  organization_id   = local.organization_id
  project_name      = "my-app-qa"
  database_password = local.database_password
  region            = "eu-west-2"

  # Auth settings — relax for QA, tighten for production
  mailer_autoconfirm  = true  # skip email confirmation in QA
  disable_signup      = false # allow self-service signup in QA
  password_min_length = 8     # lower bar for QA test accounts
  jwt_expiry          = 3600
}

