# Resource-assertion tests for the aws/iam-organizations-features module.
#
# Asserts on the configured enabled_features list, which is known at plan time
# under mock_provider. No AWS credentials are required.

mock_provider "aws" {}

run "default_features_enabled" {
  command = plan

  assert {
    condition     = contains(aws_iam_organizations_features.this.enabled_features, "RootCredentialsManagement")
    error_message = "RootCredentialsManagement must be enabled by default"
  }

  assert {
    condition     = contains(aws_iam_organizations_features.this.enabled_features, "RootSessions")
    error_message = "RootSessions must be enabled by default"
  }
}
