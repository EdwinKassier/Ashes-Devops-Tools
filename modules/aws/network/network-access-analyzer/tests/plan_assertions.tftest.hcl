# Resource-assertion tests for the aws/network-access-analyzer module.
# Uses mock_provider so no AWS credentials are required. count-driven creation
# is known at plan time.

mock_provider "aws" {}

run "scope_created_when_enabled" {
  command = plan

  variables {
    enable_network_access_analyzer = true
    match_paths = [{
      source_resource_types      = ["AWS::EC2::InternetGateway"]
      destination_resource_types = ["AWS::EC2::Instance"]
    }]
  }

  assert {
    condition     = length(aws_ec2_network_insights_access_scope.this) == 1
    error_message = "The access scope must be created when enable_network_access_analyzer is true."
  }
}

run "no_scope_when_disabled" {
  command = plan

  # Defaults: enable_network_access_analyzer = false.
  assert {
    condition     = length(aws_ec2_network_insights_access_scope.this) == 0
    error_message = "No access scope must be created when the analyzer is disabled (default)."
  }
}
