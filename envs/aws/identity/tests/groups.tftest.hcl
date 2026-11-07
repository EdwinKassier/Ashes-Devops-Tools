# Name-based assignments (aws.identity.groups) and default permission sets.

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

variables {
  landing_zone_name = "acme"
}

run "default_permission_sets_present" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  }

  assert {
    condition = alltrue([
      for n in ["PlatformAdmin", "ReadOnly", "SecurityAudit", "Developer"] : contains(keys(var.permission_sets), n)
    ])
    error_message = "default permission sets must include PlatformAdmin, ReadOnly, SecurityAudit and Developer."
  }

  assert {
    condition     = contains(var.permission_sets["Developer"].managed_policy_names, "PowerUserAccess") && length(var.permission_sets["Developer"].managed_policy_names) == 1
    error_message = "Developer must be PowerUserAccess only."
  }

  assert {
    condition     = contains(var.permission_sets["SecurityAudit"].managed_policy_names, "SecurityAudit")
    error_message = "SecurityAudit must attach the AWS-managed SecurityAudit policy."
  }
}

run "groups_section_creates_named_assignments" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-groups.yaml"
  }

  assert {
    condition     = length(local.assignments) == 3
    error_message = "two accounts for Platform Admins plus one for Auditors must plan three assignments."
  }

  assert {
    condition     = contains(keys(local.group_assignments), "Platform Admins/PlatformAdmin/network") && local.group_assignments["Platform Admins/PlatformAdmin/network"].account_key == "network"
    error_message = "group assignments must be keyed <group>/<permission set>/<account key>."
  }
}

run "no_groups_section_is_noop" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  }

  assert {
    condition     = length(local.group_assignments) == 0 && length(local.assignments) == 0
    error_message = "without aws.identity.groups no assignments may be planned."
  }
}

run "unknown_account_key_fails_clearly" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-groups-bad-key.yaml"
  }

  expect_failures = [var.identity_groups]
}
