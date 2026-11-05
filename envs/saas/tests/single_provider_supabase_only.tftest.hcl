# Single-provider regression test: Supabase-only.
#
# ONLY the supabase provider is mocked. The vercel provider is the REAL
# vercel/vercel plugin, configured by envs/saas/providers.tf — so this run
# proves a Supabase-only plan does not need VERCEL_API_TOKEN: with
# enable_vercel = false the provider gets an inert placeholder token and
# configures without calling the Vercel API. Before the fix this failed with
# "Unable to find api_token" (run with VERCEL_API_TOKEN unset to reproduce).
#
# No real credentials or network access needed.

mock_provider "supabase" {}

run "supabase_only_plans_without_vercel_token" {
  command = plan

  variables {
    enable_supabase            = true
    enable_vercel              = false
    supabase_organization_id   = "abcdefghijklmnopqrst"
    supabase_project_name      = "acme"
    supabase_database_password = "Sup3rS3cretPassw0rd1"
  }

  assert {
    condition     = output.vercel_project_id == null
    error_message = "with enable_vercel = false, vercel_project_id must be null"
  }
}

run "no_saas_plans_without_any_token" {
  command = plan

  variables {
    enable_supabase = false
    enable_vercel   = false
  }

  assert {
    condition     = output.supabase_project_id == null && output.vercel_project_id == null
    error_message = "a no-op SaaS root must plan with null outputs"
  }
}
