# C2 regression suite: Terraform Cloud trust must be pinned to the TFC
# organization (and optionally its immutable ID + project allow-list), and every
# SA binding must match ONE workspace AND ONE run phase, so a speculative plan
# can never obtain an apply-phase (write) identity.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

override_resource {
  target          = google_iam_workload_identity_pool.pool
  override_during = plan
  values = {
    name = "projects/123456789012/locations/global/workloadIdentityPools/tfc-pool"
  }
}

variables {
  project_id          = "mock-project"
  pool_id             = "tfc-pool"
  display_name        = "TFC Pool"
  enable_tfc_provider = true
  tfc_organization    = "acme"
  tfc_sa_bindings = [
    {
      workspace_name        = "gcp-workload-dev"
      run_phase             = "plan"
      service_account_email = "acme-wl-dev-plan@mock-project.iam.gserviceaccount.com"
    },
    {
      workspace_name        = "gcp-workload-dev"
      run_phase             = "apply"
      service_account_email = "acme-wl-dev-apply@mock-project.iam.gserviceaccount.com"
    },
  ]
}

run "condition_pins_org_and_phase" {
  command = plan

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.tfc[0].attribute_condition, "assertion.terraform_organization_name == 'acme'")
    error_message = "TFC attribute_condition must pin the TFC organization name."
  }

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.tfc[0].attribute_condition, "assertion.terraform_run_phase in ['plan', 'apply']")
    error_message = "TFC attribute_condition must only admit the plan/apply run phases."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.tfc[0].attribute_mapping["attribute.workspace_phase"] == "assertion.terraform_workspace_name + ':' + assertion.terraform_run_phase"
    error_message = "The composite workspace_phase attribute must join workspace name and run phase."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.tfc[0].attribute_mapping["attribute.workspace_id_phase"] == "assertion.terraform_workspace_id + ':' + assertion.terraform_run_phase"
    error_message = "The composite workspace_id_phase attribute must join workspace ID and run phase."
  }
}

run "bindings_are_phase_scoped" {
  command = plan

  assert {
    condition     = length(google_service_account_iam_member.tfc_workload_identity) == 2
    error_message = "One binding per (workspace, run phase) must be planned."
  }

  assert {
    condition     = endswith(google_service_account_iam_member.tfc_workload_identity["gcp-workload-dev:plan"].member, "/attribute.workspace_phase/gcp-workload-dev:plan")
    error_message = "The plan binding must match the workspace_phase principalSet suffixed ':plan'."
  }

  assert {
    condition     = endswith(google_service_account_iam_member.tfc_workload_identity["gcp-workload-dev:apply"].member, "/attribute.workspace_phase/gcp-workload-dev:apply")
    error_message = "The apply binding must match the workspace_phase principalSet suffixed ':apply'."
  }

  assert {
    condition     = strcontains(google_service_account_iam_member.tfc_workload_identity["gcp-workload-dev:plan"].service_account_id, "acme-wl-dev-plan@") && strcontains(google_service_account_iam_member.tfc_workload_identity["gcp-workload-dev:apply"].service_account_id, "acme-wl-dev-apply@")
    error_message = "Each phase must be bound to its own SA (plan -> plan SA, apply -> apply SA)."
  }

  assert {
    condition = alltrue([
      for b in google_service_account_iam_member.tfc_workload_identity :
      startswith(b.member, "principalSet://") && !strcontains(b.member, "attribute.terraform_workspace_name/")
    ])
    error_message = "No binding may use the legacy name-only (phase-agnostic) principalSet."
  }
}

run "pins_org_id_project_and_workspace_id" {
  command = plan

  variables {
    tfc_organization_id = "org-AbC123"
    tfc_project_ids     = ["prj-111", "prj-222"]
    tfc_sa_bindings = [
      {
        workspace_name        = "gcp-organization"
        workspace_id          = "ws-XyZ789"
        run_phase             = "apply"
        service_account_email = "acme-organization-apply@mock-project.iam.gserviceaccount.com"
      },
    ]
  }

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.tfc[0].attribute_condition, "assertion.terraform_organization_id == 'org-AbC123'")
    error_message = "When tfc_organization_id is set the condition must pin the immutable org ID."
  }

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.tfc[0].attribute_condition, "assertion.terraform_project_id in ['prj-111', 'prj-222']")
    error_message = "When tfc_project_ids is set the condition must pin the TFC project allow-list."
  }

  assert {
    condition     = endswith(google_service_account_iam_member.tfc_workload_identity["gcp-organization:apply"].member, "/attribute.workspace_id_phase/ws-XyZ789:apply")
    error_message = "When workspace_id is supplied the binding must match the immutable workspace ID + phase."
  }
}

run "rejects_invalid_run_phase" {
  command         = plan
  expect_failures = [var.tfc_sa_bindings]

  variables {
    tfc_sa_bindings = [
      {
        workspace_name        = "gcp-workload-dev"
        run_phase             = "any"
        service_account_email = "x@mock-project.iam.gserviceaccount.com"
      },
    ]
  }
}

run "rejects_duplicate_workspace_phase" {
  command         = plan
  expect_failures = [var.tfc_sa_bindings]

  variables {
    tfc_sa_bindings = [
      {
        workspace_name        = "gcp-workload-dev"
        run_phase             = "apply"
        service_account_email = "a@mock-project.iam.gserviceaccount.com"
      },
      {
        workspace_name        = "gcp-workload-dev"
        run_phase             = "apply"
        service_account_email = "b@mock-project.iam.gserviceaccount.com"
      },
    ]
  }
}

run "rejects_malformed_workspace_id" {
  command         = plan
  expect_failures = [var.tfc_sa_bindings]

  variables {
    tfc_sa_bindings = [
      {
        workspace_name        = "gcp-workload-dev"
        workspace_id          = "not-a-ws-id"
        run_phase             = "plan"
        service_account_email = "a@mock-project.iam.gserviceaccount.com"
      },
    ]
  }
}

run "rejects_malformed_tfc_project_id" {
  command         = plan
  expect_failures = [var.tfc_project_ids]

  variables {
    tfc_project_ids = ["prj-ok", "bad'quote"]
  }
}

run "github_binds_on_immutable_repository_id" {
  command = plan

  variables {
    enable_tfc_provider        = false
    tfc_sa_bindings            = []
    enable_github_provider     = true
    github_repository_owner_id = "1111"
    github_sa_bindings = [
      {
        repository            = "acme/infra"
        repository_id         = "2222"
        service_account_email = "gh-readonly@mock-project.iam.gserviceaccount.com"
      },
    ]
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "assertion.repository_owner_id == \"1111\""
    error_message = "GitHub condition must pin the immutable owner ID when supplied."
  }

  assert {
    condition = alltrue([
      for b in google_service_account_iam_member.github_workload_identity :
      endswith(b.member, "/attribute.repository_id/2222")
    ]) && length(google_service_account_iam_member.github_workload_identity) == 1
    error_message = "GitHub binding must use the immutable attribute.repository_id when repository_id is supplied."
  }
}
