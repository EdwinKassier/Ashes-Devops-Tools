# CONTRACT test for the saas root.
#
# The saas root's defining property (provider-selection thesis) is that it plans
# standalone with NO aws/google provider and no cloud credentials, with each SaaS
# feature independently gated. This test exercises both the no-op path and a
# single-feature path under mocked Supabase/Vercel providers.

mock_provider "supabase" {}
mock_provider "vercel" {}

# No-op: both features off. Must plan credential-free; disabled outputs are null.
run "saas_noop_plans_credential_free" {
  command = plan

  variables {
    enable_supabase = false
    enable_vercel   = false
  }

  assert {
    condition     = output.supabase_project_id == null && output.vercel_project_id == null
    error_message = "a no-op SaaS root (both features off) must plan with null supabase/vercel outputs"
  }
}

# Supabase enabled, Vercel off: the Supabase side composes; the Vercel output is
# null. Proves the two features gate independently within one root.
run "saas_supabase_only" {
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
    error_message = "with enable_vercel=false, vercel_project_id must be null"
  }
}
