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

# Scaffold matrix: committed scaffolder output (make scaffold-fixtures) must plan.
run "scaffold_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.saas.yaml"
    stack                    = "web"
  }
}

run "scaffold_gcp_aws_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.gcp-aws-saas.yaml"
    stack                    = "web"
  }
}

# ── SaaS residency check (CMP-11) ────────────────────────────────────────────
# saas.allowed_regions (else aws.allowed_regions) lists the AWS regions where
# SaaS data may be processed. Supabase regions are AWS region names; Vercel
# function regions map to the AWS region they run in.
run "supabase_region_outside_allowed_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    supabase_region          = "us-east-1"
  }

  expect_failures = [terraform_data.saas_residency_guard]
}

run "vercel_region_mapped_and_checked" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    vercel_serverless_region = "iad1"
  }

  expect_failures = [terraform_data.saas_residency_guard]
}

run "eu_regions_pass" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    supabase_region          = "eu-west-2"
    vercel_serverless_region = "lhr1"
  }

  assert {
    condition     = length(local.saas_regions_outside_allowed) == 0 && join(",", local.saas_regions_in_use) == "eu-west-2,eu-west-2"
    error_message = "London Supabase and Vercel lhr1 (eu-west-2) must pass an eu-west-2 allow list."
  }
}

# A disabled provider's region is not checked.
run "disabled_provider_region_not_checked" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    enable_vercel            = false
    vercel_serverless_region = "iad1"
  }

  assert {
    condition     = length(local.saas_regions_outside_allowed) == 0
    error_message = "a disabled Vercel project must not be checked against the allow list."
  }
}

# A Vercel code with no known AWS region fails closed when an allow list is set.
run "unmapped_vercel_region_fails_closed" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    vercel_serverless_region = "zzz1"
  }

  # The stage rejects unknown codes itself; isolate the root's own guard.
  override_module {
    target  = module.saas_workload
    outputs = {}
  }

  expect_failures = [terraform_data.saas_residency_guard]
}

run "aws_allowed_regions_is_the_fallback" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency-aws.yaml"
    vercel_serverless_region = "fra1"
  }

  expect_failures = [terraform_data.saas_residency_guard]
}

# No allow list anywhere: no check (the stacks fixture has neither key).
run "no_allow_list_no_check" {
  command = plan

  variables {
    supabase_region          = "us-east-1"
    vercel_serverless_region = "iad1"
  }

  assert {
    condition     = length(local.saas_allowed_regions) == 0 && length(local.saas_regions_outside_allowed) == 0
    error_message = "without saas.allowed_regions or aws.allowed_regions the residency check must not run."
  }
}
