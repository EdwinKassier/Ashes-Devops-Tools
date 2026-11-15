# Example: create a Supabase project for a QA environment.
# Replace locals with real values or remote state. The database password is a
# sensitive variable (TF_VAR_database_password or a sensitive TFC variable).

locals {
  organization_id = "abcdefghijklmnop" # from Supabase dashboard → Org Settings
}

module "supabase_project" {
  source = "../../"

  organization_id   = local.organization_id
  project_name      = "my-app-qa"
  database_password = var.database_password
  region            = "eu-west-2"
}
