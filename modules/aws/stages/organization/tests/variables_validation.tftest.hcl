# Variable-validation tests for the aws-organization stage.
#
# Uses mock_provider so no AWS credentials are required. module.organization is
# overridden with known IDs so the accept case reaches (and passes) plan; the
# reject case fails inside the account module's email validation before any
# resource is evaluated.

mock_provider "aws" {}

variables {
  terraform_run_role_arn   = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn     = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name  = "sra-log-archive-111111111111"
  tfc_organization         = "acme"
  github_federation_owners = ["acme"]
  guard_alert_emails       = ["secops@example.com"]
}

override_module {
  target = module.organization
  outputs = {
    organization_id       = "o-abc1234567"
    organization_arn      = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    roots_id              = "r-abcd"
    management_account_id = "111111111111"
    ou_ids = {
      "Security"          = "ou-abcd-security0"
      "Infrastructure"    = "ou-abcd-infra0000"
      "Workloads"         = "ou-abcd-workload0"
      "Sandbox"           = "ou-abcd-sandbox00"
      "Suspended"         = "ou-abcd-suspend00"
      "PolicyStaging"     = "ou-abcd-policyst0"
      "Exceptions"        = "ou-abcd-except000"
      "Transitional"      = "ou-abcd-transit00"
      "Workloads/Prod"    = "ou-abcd-prod0000"
      "Workloads/NonProd" = "ou-abcd-nonprod0"
    }
  }
}

# tfc-management-roles reads the partition / caller identity; mocks return
# random strings the provider's ARN validators reject, so pin real shapes.
override_data {
  target = module.tfc_management_roles[0].data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.tfc_management_roles[0].data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

run "defaults_accepted" {
  # Accept case: the default foundational account set + required carve-out ARNs
  # must pass all validations and plan cleanly.
  command = plan
}

run "wildcard_break_glass_role_arn_rejected" {
  # Reject case: role/* would turn the break-glass carve-out into "any role".
  command = plan

  variables {
    break_glass_role_arn = "arn:aws:iam::111111111111:role/*"
  }

  expect_failures = [var.break_glass_role_arn]
}

run "invalid_account_email_rejected" {
  # Reject case: an account with a malformed root email must fail the account
  # module's email validation.
  command = plan

  variables {
    workload_accounts = {
      broken = { email = "not-an-email", ou = "Workloads" }
    }
  }

  expect_failures = [var.workload_accounts]
}

run "tfc_organization_required_when_baseline_enabled" {
  command = plan

  variables {
    tfc_organization = null
  }

  expect_failures = [var.tfc_organization]
}

run "binding_to_unknown_account_rejected" {
  command = plan

  variables {
    tfc_workspace_bindings = {
      does_not_exist = { workspaces = ["aws-workload-dev"] }
    }
  }

  expect_failures = [var.tfc_workspace_bindings]
}

run "wildcard_member_break_glass_trusted_principal_rejected" {
  # The member break-glass trust must be account-qualified (no arn:aws:iam::*:).
  command = plan

  variables {
    member_break_glass_trusted_principal_arns = ["arn:aws:iam::*:role/break-glass"]
  }

  expect_failures = [var.member_break_glass_trusted_principal_arns]
}

run "guard_alert_emails_must_be_addresses" {
  command = plan

  variables {
    guard_alert_emails = ["not-an-email"]
  }

  expect_failures = [var.guard_alert_emails]
}

run "aws_enabled_regions_must_not_be_empty" {
  command = plan

  variables {
    aws_enabled_regions = []
  }

  expect_failures = [var.aws_enabled_regions]
}

run "cloudtrail_delegated_admin_needs_security_tooling" {
  command = plan

  variables {
    enable_cloudtrail_delegated_admin = true
    accounts = {
      log_archive     = { email = "aws+log-archive@example.com", ou = "Security" }
      shared_services = { email = "aws+shared-services@example.com", ou = "Infrastructure" }
    }
    central_detection_account_keys = ["log_archive"]
    tfc_workspace_bindings         = {}
  }

  expect_failures = [var.enable_cloudtrail_delegated_admin]
}

run "rejects_invalid_member_backup_vault_name" {
  command = plan

  variables {
    member_backup_vault_name = "bad vault!"
  }

  expect_failures = [var.member_backup_vault_name]
}
