# Regression test for the enable_vercel conditional output wiring.
#
# outputs.tf exposes vercel_project_id / vercel_uat_environment_id as
# `var.enable_vercel ? module.vercel_project[0].<attr> : null` (count-gated
# child module). This asserts the passthrough actually resolves to the child
# module's value when enabled, and is null when disabled — the existing
# variables_validation.tftest.hcl only proves the enable_vercel cross-variable
# input guards, never that the output actually surfaces the module's value.

mock_provider "supabase" {}
mock_provider "vercel" {}
mock_provider "null" {}

variables {
  supabase_organization_id   = "abcdefghijklmnop"
  supabase_project_name      = "my-app-qa"
  supabase_database_password = "exactly-sixteen!!"
  supabase_region            = "eu-west-2"
}

run "vercel_enabled_output_surfaces_child_module_project_id" {
  command = plan

  override_module {
    target = module.supabase_environment[0]
    outputs = {
      project_id        = "abcdefghijklmnopqrst"
      project_name      = "my-app-qa"
      api_url           = "https://abcdefghijklmnopqrst.supabase.co"
      anon_key          = "mock_anon_key"
      service_role_key  = "mock_service_role_key"
      database_password = "exactly-sixteen!!"
    }
  }

  override_module {
    target = module.vercel_project
    outputs = {
      project_id         = "prj_mock123456"
      project_name       = "my-app"
      uat_environment_id = "env_mockuat123"
    }
  }

  variables {
    enable_vercel       = true
    vercel_team_id      = "team_abc"
    vercel_project_name = "my-app"
    vercel_github_repo  = "myorg/my-app"
  }

  assert {
    condition     = output.vercel_project_id == "prj_mock123456"
    error_message = "vercel_project_id output must surface module.vercel_project[0].project_id when enable_vercel = true"
  }

  assert {
    condition     = output.vercel_uat_environment_id == "env_mockuat123"
    error_message = "vercel_uat_environment_id output must surface module.vercel_project[0].uat_environment_id when enable_vercel = true"
  }
}

run "vercel_disabled_outputs_are_null" {
  command = plan

  override_module {
    target = module.supabase_environment[0]
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
    enable_vercel       = false
    vercel_team_id      = ""
    vercel_github_repo  = ""
    vercel_project_name = ""
  }

  assert {
    condition     = output.vercel_project_id == null
    error_message = "vercel_project_id output must be null when enable_vercel = false (no child module instance exists)"
  }

  assert {
    condition     = output.vercel_uat_environment_id == null
    error_message = "vercel_uat_environment_id output must be null when enable_vercel = false (no child module instance exists)"
  }
}

# enable_supabase = false — Supabase is count-gated away; Vercel-only deployment.
# The supabase modules must not be instantiated and the supabase outputs must be
# null, while the vercel output still surfaces its child module's value. No
# Supabase inputs are supplied, proving they are no longer required.
run "supabase_disabled_vercel_only" {
  command = plan

  override_module {
    target = module.vercel_project
    outputs = {
      project_id         = "prj_mock123456"
      project_name       = "my-app"
      uat_environment_id = "env_mockuat123"
    }
  }

  variables {
    enable_supabase     = false
    enable_vercel       = true
    vercel_team_id      = "team_abc"
    vercel_project_name = "my-app"
    vercel_github_repo  = "myorg/my-app"
  }

  assert {
    condition     = length(module.supabase_environment) == 0
    error_message = "module.supabase_environment must have zero instances when enable_supabase = false"
  }

  assert {
    condition     = output.supabase_project_id == null
    error_message = "supabase_project_id output must be null when enable_supabase = false"
  }

  assert {
    condition     = output.supabase_api_url == null
    error_message = "supabase_api_url output must be null when enable_supabase = false"
  }

  assert {
    condition     = output.vercel_project_id == "prj_mock123456"
    error_message = "vercel_project_id output must surface module.vercel_project[0].project_id when enable_vercel = true"
  }
}

# enable_supabase = false AND enable_vercel = false — no SaaS at all. Plan must
# succeed with zero supabase and zero vercel instances and no required-variable
# errors, proving true "any combination" selection.
run "no_saas" {
  command = plan

  variables {
    enable_supabase = false
    enable_vercel   = false
  }

  assert {
    condition     = length(module.supabase_environment) == 0
    error_message = "module.supabase_environment must have zero instances when enable_supabase = false"
  }

  assert {
    condition     = length(module.vercel_project) == 0
    error_message = "module.vercel_project must have zero instances when enable_vercel = false"
  }

  assert {
    condition     = output.supabase_project_id == null
    error_message = "supabase_project_id output must be null when enable_supabase = false"
  }

  assert {
    condition     = output.vercel_project_id == null
    error_message = "vercel_project_id output must be null when enable_vercel = false"
  }
}
