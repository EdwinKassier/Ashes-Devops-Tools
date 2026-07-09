# Resource-assertion tests for the aws/account module.
#
# Asserts on configured attributes (parent_id, tags, for_each contact type) that
# are known at plan time under mock_provider. Provider-computed attributes (id,
# arn) are deliberately not asserted on here.

mock_provider "aws" {}

variables {
  account_name = "log-archive"
  email        = "aws+logarchive@example.com"
  parent_ou_id = "ou-abc1-def2ghi3"
}

run "account_placed_in_ou_with_managed_tag" {
  command = plan

  assert {
    condition     = aws_organizations_account.this.parent_id == "ou-abc1-def2ghi3"
    error_message = "Account must be created under the given OU"
  }

  assert {
    condition     = aws_organizations_account.this.tags["managed-by"] == "terraform"
    error_message = "Account must carry the managed-by=terraform tag"
  }
}

run "alternate_contact_type_configured" {
  command = plan

  variables {
    alternate_contacts = {
      security = {
        contact_type  = "SECURITY"
        name          = "Security Team"
        title         = "Security Contact"
        email_address = "security@example.com"
        phone_number  = "+1-555-0100"
      }
    }
  }

  assert {
    condition     = aws_account_alternate_contact.this["security"].alternate_contact_type == "SECURITY"
    error_message = "Alternate contact must be configured with type SECURITY"
  }
}
