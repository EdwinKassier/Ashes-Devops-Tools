# Variable validation tests for the aws/account module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

variables {
  account_name = "log-archive"
  email        = "aws+logarchive@example.com"
  parent_ou_id = "ou-abc1-def2ghi3"
}

run "valid_inputs_accepted" {
  # Accept case: a valid email and no alternate contacts must pass validation.
  command = plan
}

run "bad_email_rejected" {
  # Reject case: a string with no @ / domain must trip the email validation.
  command = plan

  variables {
    email = "not-an-email"
  }

  expect_failures = [var.email]
}

run "bad_alternate_contact_type_rejected" {
  # Reject case: an unknown contact_type must trip the alternate_contacts validation.
  command = plan

  variables {
    alternate_contacts = {
      bogus = {
        contact_type  = "MARKETING"
        name          = "Someone"
        title         = "Someone"
        email_address = "someone@example.com"
        phone_number  = "+1-555-0100"
      }
    }
  }

  expect_failures = [var.alternate_contacts]
}
