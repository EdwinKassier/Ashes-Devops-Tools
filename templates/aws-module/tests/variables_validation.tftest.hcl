# Variable validation tests for the MODULE_NAME module.
# All runs use mock_provider so no AWS credentials are required (requires Terraform >= 1.7).
# Validation blocks fire before resource evaluation, so these pass regardless of
# mock provider behaviour.
#
# INSTRUCTIONS FOR USE:
#   1. Replace MODULE_NAME with your module's name throughout.
#   2. Replace the example variable blocks with the actual variables from variables.tf.
#   3. Add one accept run + one reject run per validation block in variables.tf.
#   4. Run: cd modules/your-module && terraform test
#   5. All tests must pass before submitting a PR.

mock_provider "aws" {}

# Minimum required variables shared across all runs (set defaults here to avoid
# repeating them in every run block).
variables {
  name = "example-param"
  # Add other required variables here
}

# ── Example: var.name ─────────────────────────────────────────────────────────
# Replace this section with tests for each validation block in variables.tf.
# name is the template's only validated variable, so it is used here as the
# worked example — swap in your module's real variable names.

run "valid_name_accepted" {
  # Accept case: confirm that a valid input passes without error.
  command = plan

  variables {
    name = "/app/config/example" # REPLACE: use a valid value for your variable
  }
}

run "invalid_name_rejected" {
  # Reject case: confirm that an invalid input triggers the validation error.
  command = plan

  expect_failures = [var.name] # REPLACE: reference the actual variable

  variables {
    name = "invalid name with spaces" # REPLACE: use a value that violates the constraint
  }
}
