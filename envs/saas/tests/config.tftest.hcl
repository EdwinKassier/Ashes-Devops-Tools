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

# The non-sensitive bridge_version signal comes from saas.bridge_rotation; a
# workload's write-only *_wo_version reads it, so bumping it re-pushes the
# bridged secret.
run "bridge_version_comes_from_config" {
  command = plan

  assert {
    condition     = output.bridge_version == 3
    error_message = "bridge_version must come from saas.bridge_rotation in config/landing-zone.yaml."
  }
}

run "bridge_rotation_variable_wins" {
  command = plan

  variables {
    bridge_rotation = 7
  }

  assert {
    condition     = output.bridge_version == 7
    error_message = "an explicit bridge_rotation variable must win over saas.bridge_rotation."
  }
}

run "bridge_rotation_must_be_a_positive_whole_number" {
  command = plan

  variables {
    bridge_rotation = 0
  }

  expect_failures = [var.bridge_rotation]
}
