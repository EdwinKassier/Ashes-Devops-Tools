# Variable validation tests for modules/stages/saas-workload.

mock_provider "supabase" {}
mock_provider "vercel" {}
mock_provider "null" {}

variables {
  supabase_organization_id   = "abcdefghijklmnop"
  supabase_project_name      = "my-app-qa"
  supabase_database_password = "exactly-sixteen!!"
  supabase_region            = "eu-west-2"
}

# ── supabase_organization_id ───────────────────────────────────────────────────

run "valid_org_id_accepted" {
  command = plan

  override_module {
    target  = module.supabase_environment
    outputs = {
      project_id        = "abcdefghijklmnopqrst"
      project_name      = "my-app-qa"
      api_url           = "https://abcdefghijklmnopqrst.supabase.co"
      anon_key          = "mock_anon_key"
      service_role_key  = "mock_service_role_key"
      database_password = "exactly-sixteen!!"
    }
  }
}

run "short_org_id_rejected" {
  command = plan
  expect_failures = [var.supabase_organization_id]
  variables { supabase_organization_id = "abc" }
}

# ── enable_vault_secrets cross-variable guard ──────────────────────────────────

run "vault_disabled_no_url_accepted" {
  command = plan

  override_module {
    target  = module.supabase_environment
    outputs = {
      project_id        = "abcdefghijklmnopqrst"
      project_name      = "my-app-qa"
      api_url           = "https://abcdefghijklmnopqrst.supabase.co"
      anon_key          = "mock_anon_key"
      service_role_key  = "mock_service_role_key"
      database_password = "exactly-sixteen!!"
    }
  }

  variables {
    enable_vault_secrets = false
    postgres_url         = ""
  }
}

run "vault_enabled_missing_url_rejected" {
  command = plan
  expect_failures = [var.postgres_url]
  variables {
    enable_vault_secrets = true
    postgres_url         = ""
  }
}

# ── enable_vercel cross-variable guards ────────────────────────────────────────

run "vercel_disabled_no_team_accepted" {
  command = plan

  override_module {
    target  = module.supabase_environment
    outputs = {
      project_id        = "abcdefghijklmnopqrst"
      project_name      = "my-app-qa"
      api_url           = "https://abcdefghijklmnopqrst.supabase.co"
      anon_key          = "mock_anon_key"
      service_role_key  = "mock_service_role_key"
      database_password = "exactly-sixteen!!"
    }
  }

  variables {
    enable_vercel   = false
    vercel_team_id  = ""
    vercel_github_repo = ""
    vercel_project_name = ""
  }
}

run "vercel_enabled_missing_team_rejected" {
  command = plan
  expect_failures = [var.vercel_team_id]
  variables {
    enable_vercel       = true
    vercel_team_id      = ""
    vercel_project_name = "my-app"
    vercel_github_repo  = "myorg/my-app"
  }
}

run "vercel_enabled_invalid_repo_rejected" {
  command = plan
  expect_failures = [var.vercel_github_repo]
  variables {
    enable_vercel       = true
    vercel_team_id      = "team_abc"
    vercel_project_name = "my-app"
    vercel_github_repo  = "not-a-valid-repo"
  }
}

run "vercel_enabled_invalid_project_name_rejected" {
  command = plan
  expect_failures = [var.vercel_project_name]
  variables {
    enable_vercel       = true
    vercel_team_id      = "team_abc"
    vercel_project_name = "INVALID_NAME"
    vercel_github_repo  = "myorg/my-app"
  }
}
