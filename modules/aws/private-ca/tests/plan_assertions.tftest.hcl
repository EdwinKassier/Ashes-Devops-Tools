# Resource-assertion tests for the aws/private-ca module.
#
# Asserts on configured attributes and count-derived resource cardinality,
# which are known at plan time under mock_provider. Provider-computed
# attributes (arns, ids) are deliberately not asserted on.

mock_provider "aws" {}

run "enabled_creates_ca_and_ram_share" {
  command = plan

  variables {
    enable_private_ca = true
    org_arn           = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
  }

  assert {
    condition     = aws_acmpca_certificate_authority.this[0].type == "ROOT"
    error_message = "Enabled CA must default to type ROOT"
  }

  assert {
    condition     = length(aws_ram_resource_share.this) == 1
    error_message = "A RAM resource share must exist when share_org is true (default)"
  }

  assert {
    condition     = length(aws_ram_principal_association.org) == 1
    error_message = "The organization principal must be associated with the RAM share"
  }
}

run "disabled_creates_nothing" {
  command = plan

  # enable_private_ca defaults to false.
  assert {
    condition     = length(aws_acmpca_certificate_authority.this) == 0
    error_message = "No CA must be created when the module is disabled"
  }

  assert {
    condition     = length(aws_ram_resource_share.this) == 0
    error_message = "No RAM share must be created when the module is disabled"
  }
}
