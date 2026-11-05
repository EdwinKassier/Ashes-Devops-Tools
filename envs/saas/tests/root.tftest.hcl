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

# Frontend-URL seam (audit H9, option C): by default no cross-cloud references,
# so the root stays standalone with no injected env vars.
run "cross_cloud_seam_off_by_default" {
  command = plan

  variables {
    enable_supabase = false
    enable_vercel   = false
  }

  assert {
    condition     = length(output.cross_cloud_injected_env_keys) == 0
    error_message = "with no cross_cloud_references, no env vars are injected and the root stays standalone."
  }
}

# When a reference is set, the upstream output is read from state and injected as
# a Vercel shared env var (no cloud credentials needed).
run "cross_cloud_seam_injects_env_var" {
  command = plan

  variables {
    enable_supabase     = false
    enable_vercel       = true
    tfc_organization    = "acme-tfc"
    vercel_project_name = "acme-web"
    vercel_team_id      = "team_abc"
    vercel_github_repo  = "acme/web"
    cross_cloud_references = {
      api_url = {
        workspace_name = "gcp-workload-prod"
        output_key     = "api_endpoint"
        vercel_env_key = "NEXT_PUBLIC_API_URL"
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.cross_cloud["gcp-workload-prod"]
    values = {
      outputs = { api_endpoint = "https://api.example.com" }
    }
  }

  assert {
    condition     = contains(output.cross_cloud_injected_env_keys, "NEXT_PUBLIC_API_URL")
    error_message = "a cross_cloud_references entry must inject its vercel_env_key into the Vercel shared env vars."
  }
}
