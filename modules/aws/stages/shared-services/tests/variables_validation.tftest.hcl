# Variable-validation tests for the aws-shared-services stage.
#
# A single mock provider. The accept case reaches (and passes) plan with the
# bare defaults (both capabilities off). The reject case fails the ca_type
# validation before any resource is evaluated.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: all defaults (both gates off) must pass validation and plan.
  command = plan
}

run "invalid_ca_type_rejected" {
  # Reject case: a ca_type outside {ROOT, SUBORDINATE} must fail validation.
  command = plan

  variables {
    ca_type = "INTERMEDIATE"
  }

  expect_failures = [var.ca_type]
}
