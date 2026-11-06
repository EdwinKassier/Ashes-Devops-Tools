# Variable-validation tests for tfc-oidc-baseline (mock_provider, no credentials).

mock_provider "aws" {}

variables {
  tfc_organization = "acme"
  account_bindings = {
    network = { account_id = "444444444444", workspaces = ["aws-network"] }
  }
  target_ou_ids = { Infrastructure = "ou-abcd-infra0000" }
}

run "valid_inputs_accepted" {
  command = plan
}

run "wildcard_organization_rejected" {
  command = plan

  variables {
    tfc_organization = "acme*"
  }

  expect_failures = [var.tfc_organization]
}

run "hostname_with_scheme_rejected" {
  command = plan

  variables {
    tfc_hostname = "https://app.terraform.io"
  }

  expect_failures = [var.tfc_hostname]
}

run "wildcard_project_rejected" {
  command = plan

  variables {
    tfc_project = "*"
  }

  expect_failures = [var.tfc_project]
}

run "workspace_wildcard_rejected_by_default" {
  command = plan

  variables {
    account_bindings = {
      network = { account_id = "444444444444", workspaces = ["aws-*"] }
    }
  }

  expect_failures = [var.account_bindings]
}

run "bare_star_workspace_rejected_even_with_wildcards" {
  command = plan

  variables {
    allow_workspace_wildcards = true
    account_bindings = {
      network = { account_id = "444444444444", workspaces = ["*"] }
    }
  }

  expect_failures = [var.account_bindings]
}

run "empty_workspace_list_rejected" {
  command = plan

  variables {
    account_bindings = {
      network = { account_id = "444444444444", workspaces = [] }
    }
  }

  expect_failures = [var.account_bindings]
}

run "colliding_logical_ids_rejected" {
  command = plan

  variables {
    account_bindings = {
      security_tooling = { account_id = "222222222222", workspaces = ["a"] }
      security-tooling = { account_id = "333333333333", workspaces = ["b"] }
    }
  }

  expect_failures = [var.account_bindings]
}

run "admin_plan_policy_rejected" {
  command = plan

  variables {
    plan_role_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  expect_failures = [var.plan_role_policy_arns]
}

run "invalid_call_as_rejected" {
  command = plan

  variables {
    call_as = "OTHER"
  }

  expect_failures = [var.call_as]
}

run "invalid_ou_id_rejected" {
  command = plan

  variables {
    target_ou_ids = { Infrastructure = "not-an-ou" }
  }

  expect_failures = [var.target_ou_ids]
}

run "short_session_rejected" {
  command = plan

  variables {
    max_session_duration = 900
  }

  expect_failures = [var.max_session_duration]
}

run "bad_thumbprint_rejected" {
  command = plan

  variables {
    oidc_thumbprints = ["xyz"]
  }

  expect_failures = [var.oidc_thumbprints]
}

run "invalid_boundary_arn_rejected" {
  command = plan

  variables {
    apply_permissions_boundary_arn = "not-an-arn"
  }

  expect_failures = [var.apply_permissions_boundary_arn]
}

run "service_wide_data_read_exemption_rejected" {
  command = plan

  variables {
    plan_role_data_read_exempt_arns = ["arn:aws:s3:::*"]
  }

  expect_failures = [var.plan_role_data_read_exempt_arns]
}

run "wildcard_break_glass_trusted_principal_rejected" {
  # The break-glass trust must be account-qualified (no arn:aws:iam::*:).
  command = plan

  variables {
    member_break_glass_trusted_principal_arns = ["arn:aws:iam::*:role/break-glass"]
  }

  expect_failures = [var.member_break_glass_trusted_principal_arns]
}

run "wildcard_break_glass_role_name_rejected" {
  command = plan

  variables {
    break_glass_role_name = "break-*"
  }

  expect_failures = [var.break_glass_role_name]
}
