# Single-provider regression test: Vercel-only.
#
# ONLY the vercel provider is mocked. The supabase provider is the REAL
# supabase/supabase plugin, configured by envs/saas/providers.tf — so this run
# proves a Vercel-only plan does not need SUPABASE_ACCESS_TOKEN: with
# enable_supabase = false the provider gets an inert placeholder token and
# configures without calling the Supabase API. Before the fix this failed with
# "Missing Supabase API Access Token" (run with SUPABASE_ACCESS_TOKEN unset).
#
# No real credentials or network access needed.

mock_provider "vercel" {}

run "vercel_only_plans_without_supabase_token" {
  command = plan

  variables {
    enable_supabase     = false
    enable_vercel       = true
    vercel_project_name = "acme-web"
    vercel_team_id      = "team_abc"
    vercel_github_repo  = "acme/web"
  }

  assert {
    condition     = output.supabase_project_id == null
    error_message = "with enable_supabase = false, supabase_project_id must be null"
  }
}
