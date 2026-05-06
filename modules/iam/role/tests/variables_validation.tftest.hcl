# Variable validation tests for the iam/role module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  role_id     = "myCustomRole"
  title       = "My Custom Role"
  permissions = ["storage.objects.get"]
  project_id  = "mock-project"
}

# ── level ──────────────────────────────────────────────────────────────────────

run "accepts_project_level" {
  command = plan

  variables {
    level = "project"
  }
}

run "accepts_organization_level" {
  command = plan

  variables {
    level      = "organization"
    project_id = null
    org_id     = "123456789"
  }
}

run "rejects_invalid_level" {
  command = plan

  expect_failures = [var.level]

  variables {
    level = "folder"
  }
}

# ── role_id ────────────────────────────────────────────────────────────────────

run "accepts_valid_role_id" {
  command = plan

  variables {
    role_id = "storageAdmin"
  }
}

run "accepts_role_id_with_periods_and_underscores" {
  command = plan

  variables {
    role_id = "myOrg.custom_Role123"
  }
}

run "rejects_role_id_starting_with_digit" {
  command = plan

  expect_failures = [var.role_id]

  variables {
    role_id = "1badRole"
  }
}

run "rejects_role_id_too_short" {
  command = plan

  expect_failures = [var.role_id]

  variables {
    role_id = "ab"
  }
}

# ── permissions ────────────────────────────────────────────────────────────────

run "accepts_valid_service_resource_action_permissions" {
  command = plan

  variables {
    permissions = [
      "storage.objects.get",
      "compute.instances.list",
      "iam.serviceAccounts.actAs",
    ]
  }
}

run "rejects_empty_permissions_list" {
  command = plan

  expect_failures = [var.permissions]

  variables {
    permissions = []
  }
}

run "rejects_permission_missing_action_segment" {
  command = plan

  expect_failures = [var.permissions]

  variables {
    permissions = ["storage.objects"]
  }
}

# ── stage ──────────────────────────────────────────────────────────────────────

run "accepts_all_valid_stages" {
  command = plan

  variables {
    stage = "ALPHA"
  }
}

run "accepts_ga_stage" {
  command = plan

  variables {
    stage = "GA"
  }
}

run "rejects_invalid_stage" {
  command = plan

  expect_failures = [var.stage]

  variables {
    stage = "STABLE"
  }
}

# ── org_id ─────────────────────────────────────────────────────────────────────

run "accepts_null_org_id" {
  command = plan

  variables {
    org_id = null
  }
}

run "accepts_numeric_org_id" {
  command = plan

  variables {
    org_id = "123456789"
  }
}

run "rejects_org_id_with_prefix" {
  command = plan

  expect_failures = [var.org_id]

  variables {
    org_id = "organizations/123456789"
  }
}

run "rejects_non_numeric_org_id" {
  command = plan

  expect_failures = [var.org_id]

  variables {
    org_id = "abc123"
  }
}
