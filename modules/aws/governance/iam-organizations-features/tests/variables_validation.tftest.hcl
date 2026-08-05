# Variable validation tests for the aws/iam-organizations-features module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: the default feature set must pass validation.
  command = plan
}

run "bogus_feature_rejected" {
  # Reject case: an unknown feature must trip the allowed-values validation.
  command = plan

  variables {
    enabled_features = ["BogusFeature"]
  }

  expect_failures = [var.enabled_features]
}
