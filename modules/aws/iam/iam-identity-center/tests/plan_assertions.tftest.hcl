# Resource-assertion tests for the aws/iam-identity-center module.
#
# Mocks the discovered Identity Center instances data source with a known ARN so
# local.instance_arn is deterministic, then asserts on plan-known attributes
# (session_duration derived from the default permission_sets, and the
# principal_type of an assignment). Provider-computed attributes (permission set
# ARNs) are deliberately not asserted on.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
  mock_data "aws_identitystore_group" {
    defaults = { group_id = "11111111-2222-3333-4444-555555555555" }
  }
}

run "default_permission_sets_have_valid_session_duration" {
  command = plan

  assert {
    condition     = aws_ssoadmin_permission_set.this["AdministratorAccess"].session_duration == "PT1H"
    error_message = "Default AdministratorAccess permission set must have session_duration PT1H"
  }

  assert {
    condition     = can(regex("^PT([0-9]|1[0-2])H$", aws_ssoadmin_permission_set.this["ReadOnly"].session_duration))
    error_message = "Default ReadOnly session_duration must match the <=PT12H ISO-8601 hour pattern"
  }

  assert {
    condition     = local.instance_arn == "arn:aws:sso:::instance/ssoins-0000000000000000"
    error_message = "instance_arn must be resolved from the discovered Identity Center instance"
  }
}

run "group_assignment_is_planned" {
  command = plan

  variables {
    assignments = {
      x = {
        permission_set = "AdministratorAccess"
        principal_type = "GROUP"
        principal_id   = "00000000-0000-0000-0000-000000000000"
        account_id     = "111111111111"
      }
    }
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["x"].principal_type == "GROUP"
    error_message = "The x assignment must bind a GROUP principal"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["x"].target_type == "AWS_ACCOUNT"
    error_message = "Account assignments must target an AWS account"
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["AdministratorAccess"].tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_ssoadmin_permission_set.this"
  }
}

# Defaults name AWS-managed policies; the ARN follows the partition, and the
# attachment keys stay in the canonical arn:aws form (no state churn).
run "default_policies_resolve_in_commercial_partition" {
  command = plan

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }

  assert {
    condition = (
      local.managed_attachments["AdministratorAccess/arn:aws:iam::aws:policy/AdministratorAccess"].arn == "arn:aws:iam::aws:policy/AdministratorAccess" &&
      local.managed_attachments["ReadOnly/arn:aws:iam::aws:policy/ReadOnlyAccess"].arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    )
    error_message = "default managed policy names must resolve to arn:aws ARNs in the commercial partition."
  }
}

run "default_policies_resolve_in_govcloud" {
  command = plan

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws-us-gov" }
  }

  variables {
    permission_sets = {
      Admin = {
        description          = "x"
        session_duration     = "PT1H"
        managed_policy_names = ["AdministratorAccess"]
        managed_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      }
    }
  }

  assert {
    condition = (
      local.managed_attachments["Admin/arn:aws:iam::aws:policy/AdministratorAccess"].arn == "arn:aws-us-gov:iam::aws:policy/AdministratorAccess" &&
      local.managed_attachments["Admin/arn:aws:iam::aws:policy/ReadOnlyAccess"].arn == "arn:aws-us-gov:iam::aws:policy/ReadOnlyAccess"
    )
    error_message = "policy names and AWS-managed ARNs must follow the partition (aws-us-gov)."
  }
}

# Assignments by Identity Store group display name and org account key: the
# group is looked up by DisplayName, the account key resolves via account_ids,
# and the existing explicit-ID form keeps its key and shape.
run "assignment_by_group_name_and_account_key" {
  command = plan

  variables {
    account_ids = { shared_services = "222222222222" }
    assignments = {
      by-name = {
        permission_set     = "ReadOnly"
        group_display_name = "Platform Admins"
        account_key        = "shared_services"
      }
      by-id = {
        permission_set = "ReadOnly"
        principal_type = "GROUP"
        principal_id   = "00000000-0000-0000-0000-000000000000"
        account_id     = "111111111111"
      }
    }
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["by-name"].target_id == "222222222222" && aws_ssoadmin_account_assignment.this["by-name"].principal_type == "GROUP"
    error_message = "account_key must resolve through account_ids and a group name implies a GROUP principal."
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["by-id"].target_id == "111111111111" && aws_ssoadmin_account_assignment.this["by-id"].principal_id == "00000000-0000-0000-0000-000000000000"
    error_message = "explicit principal_id / account_id assignments must be unchanged."
  }

  assert {
    condition     = length(data.aws_identitystore_group.this) == 1 && contains(keys(data.aws_identitystore_group.this), "Platform Admins")
    error_message = "exactly the named groups must be looked up by display name."
  }
}

run "customer_managed_policy_attached" {
  command = plan

  variables {
    permission_sets = {
      Custom = {
        description               = "x"
        session_duration          = "PT1H"
        customer_managed_policies = [{ name = "deny-iam", path = "/org/" }]
      }
    }
  }

  assert {
    condition     = aws_ssoadmin_customer_managed_policy_attachment.this["Custom//org/deny-iam"].customer_managed_policy_reference[0].name == "deny-iam"
    error_message = "customer_managed_policies must create a customer-managed policy attachment."
  }
}

run "no_named_assignments_means_no_lookups" {
  command = plan

  assert {
    condition     = length(data.aws_identitystore_group.this) == 0
    error_message = "without group_display_name assignments no identity-store lookups are made."
  }
}
