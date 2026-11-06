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
