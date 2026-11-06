# Variable validation tests for the stages/bootstrap module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}
mock_provider "random" {}

variables {
  project_prefix   = "mock-org"
  org_id           = "123456789"
  billing_account  = "ABCDEF-123456-789012"
  admin_email      = "admin@example.com"
  tfc_organization = "my-tfc-org"
}

run "accepts_tfc_oidc_disabled" {
  command = plan

  variables {
    enable_tfc_oidc  = false
    tfc_organization = null
  }
}

run "accepts_tfc_oidc_enabled_with_workloads" {
  command = plan

  variables {
    enable_tfc_oidc       = true
    workload_environments = ["dev", "staging"]
  }
}

run "rejects_tfc_oidc_enabled_without_tfc_organization" {
  command         = plan
  expect_failures = [var.tfc_organization]

  variables {
    enable_tfc_oidc  = true
    tfc_organization = null
  }
}

run "rejects_github_wif_without_immutable_ids" {
  command         = plan
  expect_failures = [var.enable_github_wif]

  variables {
    enable_github_wif = true
    github_org        = "my-org"
    github_repo       = "my-repo"
  }
}

run "rejects_non_numeric_github_repository_id" {
  command         = plan
  expect_failures = [var.github_repository_id]

  variables {
    github_repository_id = "my-org/my-repo"
  }
}

run "rejects_workload_env_overflowing_sa_account_id" {
  command         = plan
  expect_failures = [var.workload_environments]

  variables {
    project_prefix        = "abcdefghij"
    workload_environments = ["development1"]
  }
}

run "rejects_owner_in_workload_folder_roles" {
  command         = plan
  expect_failures = [var.workload_folder_roles]

  variables {
    workload_folder_roles = {
      plan  = ["roles/viewer"]
      apply = ["roles/owner"]
    }
  }
}

run "rejects_unknown_control_plane_stage_key" {
  command         = plan
  expect_failures = [var.control_plane_workspaces]

  variables {
    control_plane_workspaces = {
      bootstrap    = "gcp-bootstrap"
      organization = "gcp-organization"
      projects     = "gcp-projects"
      network      = "gcp-network-hub"
    }
  }
}

run "rejects_non_numeric_access_policy_id" {
  command         = plan
  expect_failures = [var.vpc_sc_access_policy_id]

  variables {
    vpc_sc_access_policy_id = "accessPolicies/123"
  }
}

run "rejects_roles_viewer_in_workload_plan_roles" {
  command = plan
  variables {
    workload_folder_roles = {
      plan  = ["roles/viewer"]
      apply = []
    }
  }
  expect_failures = [var.workload_folder_roles]
}

run "rejects_data_plane_permission_in_plan_viewer_role" {
  command = plan
  variables {
    plan_viewer_permissions = ["storage.buckets.get", "storage.objects.get"]
  }
  expect_failures = [var.plan_viewer_permissions]
}

run "rejects_placeholder_tfc_workspace_id" {
  command = plan
  variables {
    tfc_workspace_ids = { "gcp-workload-prod" = "ws-REPLACEME" }
  }
  expect_failures = [var.tfc_workspace_ids]
}

run "rejects_production_env_not_in_workload_envs" {
  command = plan
  variables {
    workload_environments            = ["dev"]
    production_workload_environments = ["prod"]
  }
  expect_failures = [var.production_workload_environments]
}

run "rejects_legacy_access_policy_grants_without_policy" {
  command = plan
  variables {
    enable_legacy_org_access_policy_grants = true
  }
  expect_failures = [var.enable_legacy_org_access_policy_grants]
}

run "rejects_unknown_guardrail_owner_mode" {
  command = plan

  variables {
    guardrail_owner_mode = "nobody"
  }

  expect_failures = [var.guardrail_owner_mode]
}

run "rejects_malformed_guardrail_owner_member" {
  command = plan

  variables {
    guardrail_owner_members = ["guardrail-owners@example.com"]
  }

  expect_failures = [var.guardrail_owner_members]
}

run "rejects_non_numeric_github_repository_owner_id" {
  command = plan

  expect_failures = [var.github_repository_owner_id]

  variables {
    github_repository_owner_id = "my-org"
  }
}
