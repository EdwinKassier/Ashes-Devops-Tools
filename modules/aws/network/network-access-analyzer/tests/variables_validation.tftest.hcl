# Variable validation tests for the aws/network-access-analyzer module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "enabled_with_paths_accepted" {
  # An enabled scope with at least one match path must pass validation.
  command = plan

  variables {
    enable_network_access_analyzer = true
    match_paths = [{
      source_resource_types      = ["AWS::EC2::InternetGateway"]
      destination_resource_types = ["AWS::EC2::Instance"]
    }]
  }
}

run "disabled_empty_paths_accepted" {
  # When disabled, empty match_paths is acceptable (no scope is created).
  command = plan

  variables {
    enable_network_access_analyzer = false
    match_paths                    = []
  }
}

run "enabled_empty_paths_rejected" {
  # An enabled scope with no match paths can never flag a violation and
  # must trip the validation.
  command = plan

  variables {
    enable_network_access_analyzer = true
    match_paths                    = []
  }

  expect_failures = [var.match_paths]
}
