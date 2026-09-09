# Plan assertions for the supabase/project module: verify the supabase_project is
# planned with the caller-supplied name, organization and region wired through.
# All runs use mock_provider so no Supabase credentials are required.

mock_provider "supabase" {}

variables {
  organization_id   = "abcdefghijklmnop"
  project_name      = "my-app-qa"
  database_password = "exactly-sixteen!!"
  region            = "eu-west-2"
}

run "project_wired" {
  command = plan

  assert {
    condition     = supabase_project.this.name == var.project_name
    error_message = "Supabase project name must be the caller-supplied project_name."
  }

  assert {
    condition     = supabase_project.this.organization_id == var.organization_id
    error_message = "Supabase project must belong to the caller-supplied organization."
  }

  assert {
    condition     = supabase_project.this.region == var.region
    error_message = "Supabase project region must be the caller-supplied region."
  }
}
