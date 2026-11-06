# Resource-assertion example for the MODULE_NAME module.
#
# variables_validation.tftest.hcl only proves inputs are accepted/rejected —
# it never proves the module actually plans the resource you think it does.
# Every module must ALSO have at least one command=plan test that asserts on
# a planned resource or output attribute, like this one. See CONTRIBUTING.md
# "Testing" for the full requirement and the vacuous-alltrue([]) warning.
#
# INSTRUCTIONS FOR USE:
#   1. Replace MODULE_NAME with your module's name throughout.
#   2. Replace aws_ssm_parameter.example with your module's real resource
#      address(es) and assert on an attribute that actually depends on input.
#   3. If the assertion iterates a for_each/count resource, also assert
#      length(...) > 0 so an empty set can't make the assertion vacuously pass.
#   4. Run: cd modules/your-module && terraform test

mock_provider "aws" {}

variables {
  name  = "example-param"
  value = "hello"
  tags  = { Component = "example" }
  # Add other required variables here
}

run "example_parameter_plans_with_expected_name" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.example.name == "example-param"
    error_message = "example parameter must be planned with the supplied name"
  }

  assert {
    condition     = aws_ssm_parameter.example.value == "hello"
    error_message = "example parameter must be planned with the supplied value"
  }

  # Every module must wire var.tags onto its taggable resources.
  assert {
    condition     = aws_ssm_parameter.example.tags["Component"] == "example"
    error_message = "var.tags must be applied to the example parameter"
  }

  assert {
    condition     = output.name == "example-param"
    error_message = "the name output must surface the planned parameter name"
  }
}
