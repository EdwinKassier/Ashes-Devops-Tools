# Resource-assertion tests for the aws/access-analyzer-org module.
#
# Asserts on configured attributes (analyzer type) which are known at plan time
# under mock_provider. Provider-computed attributes (arn) are deliberately not
# asserted on here.

mock_provider "aws" {}

run "analyzers_are_organization_scoped" {
  command = plan

  assert {
    condition     = aws_accessanalyzer_analyzer.external.type == "ORGANIZATION"
    error_message = "External analyzer must be organization scoped"
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.unused.type == "ORGANIZATION_UNUSED_ACCESS"
    error_message = "Unused analyzer must be organization unused-access scoped"
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.external.tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_accessanalyzer_analyzer.external"
  }
}

run "home_region_analyzer_address_present" {
  command = plan

  # Default inputs: the unkeyed home-region analyzers keep their state
  # addresses and nothing extra is created.
  assert {
    condition     = aws_accessanalyzer_analyzer.external.analyzer_name == "org-external-access" && aws_accessanalyzer_analyzer.unused.analyzer_name == "org-unused-access"
    error_message = "unkeyed external and unused analyzers must remain"
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.external_extra) == 0 && length(aws_accessanalyzer_analyzer.internal) == 0 && length(aws_accessanalyzer_analyzer.internal_extra) == 0
    error_message = "default inputs must create no extra-region or internal analyzers"
  }
}

run "external_and_internal_in_every_region" {
  command = plan

  variables {
    home_region                     = "eu-west-2"
    regions                         = ["eu-west-2", "eu-west-1", "us-east-1"]
    enable_internal_access_analyzer = true
  }

  assert {
    condition     = toset(keys(aws_accessanalyzer_analyzer.external_extra)) == toset(["eu-west-1", "us-east-1"])
    error_message = "external analyzers must cover every enabled region other than home"
  }

  assert {
    condition     = toset(keys(aws_accessanalyzer_analyzer.internal_extra)) == toset(["eu-west-1", "us-east-1"]) && length(aws_accessanalyzer_analyzer.internal) == 1
    error_message = "internal analyzers must cover home (unkeyed) and every other region"
  }

  assert {
    condition     = alltrue([for k, a in aws_accessanalyzer_analyzer.external_extra : a.region == k && a.type == "ORGANIZATION"]) && alltrue([for k, a in aws_accessanalyzer_analyzer.internal_extra : a.region == k && a.type == "ORGANIZATION_INTERNAL_ACCESS"])
    error_message = "extra analyzers must set the region meta-argument and the right type"
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.unused.type == "ORGANIZATION_UNUSED_ACCESS"
    error_message = "unused-access analysis stays a single home-region analyzer"
  }
}
