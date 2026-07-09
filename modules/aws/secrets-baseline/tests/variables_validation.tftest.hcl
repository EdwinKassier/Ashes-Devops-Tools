# Variable validation tests for the aws/secrets-baseline module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "enabled_with_valid_org_id_accepted" {
  # A valid o-xxxx org id with the module enabled must pass validation.
  command = plan

  variables {
    enable_secrets_baseline = true
    org_id                  = "o-exampleorgid"
  }
}

run "disabled_empty_org_id_accepted" {
  # When disabled the org_id is unused, so an empty default must pass.
  command = plan

  variables {
    enable_secrets_baseline = false
    org_id                  = ""
  }
}

run "enabled_invalid_org_id_rejected" {
  # An enabled module with a malformed org_id must trip the validation,
  # since the emitted aws:PrincipalOrgID condition would be ineffective.
  command = plan

  variables {
    enable_secrets_baseline = true
    org_id                  = "not-an-org-id"
  }

  expect_failures = [var.org_id]
}
