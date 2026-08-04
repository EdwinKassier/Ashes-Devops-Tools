# Variable validation tests for the MODULE_NAME module.
# All runs use mock_provider so no GCP credentials are required (requires Terraform >= 1.7).
# Validation blocks fire before resource evaluation, so these pass regardless of
# mock provider behaviour.
#
# INSTRUCTIONS FOR USE:
#   1. Replace MODULE_NAME with your module's name throughout.
#   2. Replace the example variable blocks with the actual variables from variables.tf.
#   3. Add one accept run + one reject run per validation block in variables.tf.
#   4. Run: cd modules/your-module && terraform test
#   5. All tests must pass before submitting a PR.

mock_provider "google" {}
mock_provider "google-beta" {}

# Minimum required variables shared across all runs (set defaults here to avoid
# repeating them in every run block).
variables {
  project_id = "mock-project-id"
  # Add other required variables here
}

# ── Example: var.project_id ───────────────────────────────────────────────────
# Replace this section with tests for each validation block in variables.tf.
# project_id is the template's only declared variable, so it is used here as
# the worked example — swap in your module's real variable names.

run "valid_project_id_accepted" {
  # Accept case: confirm that a valid input passes without error.
  command = plan

  variables {
    project_id = "my-project-id" # REPLACE: use a valid value for your variable
  }
}

run "invalid_project_id_rejected" {
  # Reject case: confirm that an invalid input triggers the validation error.
  command = plan

  expect_failures = [var.project_id] # REPLACE: reference the actual variable

  variables {
    project_id = "INVALID PROJECT!" # REPLACE: use a value that violates the constraint
  }
}

# ── TEMPLATE: boundary value test (numeric ranges) ────────────────────────────
# Uncomment and adapt this section for variables with numeric range constraints
# (e.g., log_config_flow_sampling in [0.0, 1.0]).

# run "numeric_lower_bound_accepted" {
#   command = plan
#   variables { some_rate = 0.0 }
# }
#
# run "numeric_upper_bound_accepted" {
#   command = plan
#   variables { some_rate = 1.0 }
# }
#
# run "numeric_below_lower_bound_rejected" {
#   command = plan
#   expect_failures = [var.some_rate]
#   variables { some_rate = -0.1 }
# }
#
# run "numeric_above_upper_bound_rejected" {
#   command = plan
#   expect_failures = [var.some_rate]
#   variables { some_rate = 1.1 }
# }

# ── TEMPLATE: cross-variable conditional guard ────────────────────────────────
# Uncomment and adapt for !var.enable_x || condition_on_y patterns.

# run "feature_disabled_empty_dependency_accepted" {
#   command = plan
#   variables { enable_feature = false; feature_config = "" }
# }
#
# run "feature_enabled_valid_dependency_accepted" {
#   command = plan
#   variables { enable_feature = true; feature_config = "valid-value" }
# }
#
# run "feature_enabled_missing_dependency_rejected" {
#   command = plan
#   expect_failures = [var.feature_config]
#   variables { enable_feature = true; feature_config = "" }
# }
