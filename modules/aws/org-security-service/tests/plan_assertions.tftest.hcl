# Resource-assertion tests for the aws/org-security-service module.
#
# Asserts on the count-gating of each service block, which is known at plan time
# under mock_provider. The module declares a configuration_aliases
# [aws.management]; declaring a second mock_provider with that alias satisfies it
# automatically in `terraform test`.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  enabled_services            = ["macie", "inspector"]
  security_tooling_account_id = "111111111111"
}

run "default_set_enables_macie_and_inspector_only" {
  command = plan

  assert {
    condition     = length(aws_macie2_account.this) == 1
    error_message = "Macie must be enabled when present in enabled_services"
  }

  assert {
    condition     = length(aws_inspector2_organization_configuration.this) == 1
    error_message = "Inspector org configuration must be enabled when inspector is present"
  }

  # Detective is not in the set — its resources must be gated off.
  assert {
    condition     = length(aws_detective_graph.this) == 0
    error_message = "Detective must be disabled when absent from enabled_services"
  }

  # Resource Explorer not in the set either.
  assert {
    condition     = length(aws_resourceexplorer2_index.this) == 0
    error_message = "Resource Explorer must be disabled when absent from enabled_services"
  }
}

run "enabling_detective_creates_the_graph" {
  command = plan

  variables {
    enabled_services            = ["macie", "inspector", "detective"]
    security_tooling_account_id = "111111111111"
  }

  assert {
    condition     = length(aws_detective_graph.this) == 1
    error_message = "Detective graph must be created when detective is enabled"
  }
}

run "enabling_resource_explorer_creates_index_and_view" {
  command = plan

  variables {
    enabled_services            = ["resource-explorer"]
    security_tooling_account_id = "111111111111"
  }

  assert {
    condition     = aws_resourceexplorer2_index.this[0].type == "AGGREGATOR"
    error_message = "Resource Explorer index must be of type AGGREGATOR"
  }

  assert {
    condition     = length(aws_resourceexplorer2_view.this) == 1
    error_message = "Resource Explorer view must be created alongside the index"
  }

  # Macie/inspector not requested here.
  assert {
    condition     = length(aws_macie2_account.this) == 0
    error_message = "Macie must be disabled when not in enabled_services"
  }
}
