# The SaaS root reads its per-stack settings from saas.stacks.<stack> over
# saas.defaults in config/landing-zone.yaml, so VCS-driven runs need only the
# database password as a (sensitive) TFC variable.

mock_provider "supabase" {}
mock_provider "vercel" {}
mock_provider "null" {}

variables {
  landing_zone_config_path   = "tests/fixtures/landing-zone-saas-stacks.yaml"
  stack                      = "web"
  supabase_database_password = "correct-horse-battery-staple"
}

run "stack_settings_come_from_config" {
  command = plan

  assert {
    condition = (
      local.supabase_organization_id == "acmeorgid1234" &&
      local.supabase_project_name == "acme-web" &&
      local.supabase_region == "eu-central-1" &&
      local.vercel_team_id == "team_acme" &&
      local.vercel_github_repo == "acme/web" &&
      local.vercel_production_branch == "release"
    )
    error_message = "per-stack values must come from saas.stacks.<stack> over saas.defaults."
  }
}

run "explicit_variables_win" {
  command = plan

  variables {
    supabase_project_name = "override-name"
    supabase_region       = "us-east-1"
  }

  assert {
    condition     = local.supabase_project_name == "override-name" && local.supabase_region == "us-east-1"
    error_message = "explicit variables must win over the config file."
  }
}

# An empty stack config fails with errors naming the config keys.
run "missing_stack_config_names_the_keys" {
  command = plan

  variables {
    stack = "unconfigured"
  }

  # Isolate the root's own checks from the stage's duplicate validations.
  override_module {
    target  = module.saas_workload
    outputs = {}
  }

  expect_failures = [output.stack]
}
