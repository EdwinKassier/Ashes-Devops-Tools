# Regression test for modules/vercel/project shared environment variables.
#
# Vercel v4 treats `target` and `custom_environment_ids` as mutually exclusive.
# The shared set is split into two resources: `shared` (standard targets, no
# custom env) and `shared_uat` (target = [], UAT custom environment). No single
# env-var resource may set both a non-empty target and custom_environment_ids.
#
# NOTE: custom_environment_ids is left unset (and therefore unknown at plan
# time) on the `shared`/`prod`/`qa` resources, so assertions here compare the
# CONFIGURED, plan-known attributes: `target` (always set explicitly) and the
# length of the explicitly-assigned custom_environment_ids list (known even when
# the referenced id value is not).

mock_provider "vercel" {}

variables {
  project_name = "my-app"
  github_repo  = "myorg/my-app"
  shared_environment_variables = [
    { key = "SHARED_A", value = "value-a", sensitive = false },
    { key = "SHARED_B", value = "value-b", sensitive = true },
  ]
}

run "shared_resources_are_planned" {
  command = plan

  assert {
    condition     = length(vercel_project_environment_variable.shared) == 2
    error_message = "shared env-var resource (standard targets) must be planned for each shared variable"
  }

  assert {
    condition     = length(vercel_project_environment_variable.shared_uat) == 2
    error_message = "shared_uat env-var resource (custom environment) must be planned for each shared variable"
  }
}

run "shared_uses_standard_targets" {
  command = plan

  # The standard-target shared resource must set preview+production targets.
  assert {
    condition = alltrue([
      for v in vercel_project_environment_variable.shared :
      length(v.target) > 0
    ])
    error_message = "shared resource must use standard (non-empty) targets"
  }
}

run "shared_uat_uses_custom_environment_only" {
  command = plan

  # The custom-environment shared resource must set an empty target and exactly
  # one custom_environment_ids entry (mutually exclusive with a real target).
  assert {
    condition = alltrue([
      for v in vercel_project_environment_variable.shared_uat :
      length(v.target) == 0 && length(v.custom_environment_ids) == 1
    ])
    error_message = "shared_uat resource must use an empty target and a single custom_environment_ids entry"
  }
}

run "no_env_var_combines_target_and_custom_environment" {
  command = plan

  # Vercel v4: no single env-var resource may set BOTH a non-empty target and a
  # non-empty custom_environment_ids. Only shared_uat and uat explicitly assign
  # custom_environment_ids; both must keep target empty.
  assert {
    condition = alltrue(concat(
      [for v in vercel_project_environment_variable.shared_uat : length(v.target) == 0],
      [for v in vercel_project_environment_variable.uat : length(v.target) == 0],
    ))
    error_message = "resources that assign custom_environment_ids must keep target empty"
  }

  # And every standard-target resource must keep target non-empty (its
  # custom_environment_ids is left unset).
  assert {
    condition = alltrue(concat(
      [for v in vercel_project_environment_variable.shared : length(v.target) > 0],
      [for v in vercel_project_environment_variable.prod : length(v.target) > 0],
      [for v in vercel_project_environment_variable.qa : length(v.target) > 0],
    ))
    error_message = "standard-target env-var resources must keep a non-empty target"
  }
}
