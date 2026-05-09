# Example: create a Supabase project for a QA environment.
# Replace locals with real values or remote state.

locals {
  organization_id   = "abcdefghijklmnop"   # from Supabase dashboard → Org Settings
  database_password = "change-me-min-16ch" # store in a secret manager; min 16 chars
}

module "supabase_project" {
  source = "../../"

  organization_id   = local.organization_id
  project_name      = "my-app-qa"
  database_password = local.database_password
  region            = "eu-west-2"
}

